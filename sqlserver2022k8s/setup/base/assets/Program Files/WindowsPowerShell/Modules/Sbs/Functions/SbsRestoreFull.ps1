<#
.SYNOPSIS
Restore a FULL database backup or a bacpac file from a remote URL, a local or a network path.

.DESCRIPTION
Long description

.PARAMETER SqlInstance
Parameter description

.PARAMETER Path
Parameter description

.PARAMETER CertificatePath
The local or remote path to a zip file containing
certificates for an encrypted backup

.PARAMETER TempPath
Temporary path for downloads. Defaults to the system temporary path

.EXAMPLE
SbsRestoreFull -SqlInstance "localhost" -DatabaseNAME "mydatabase" -Path "https://xx.blob.core.windows.net/temp/export.bacpac?sp=r&st=2024-06-26T14:17:33Z&se=2024-06-28T22:17:33Z&spr=https&sv=2022-11-02&sr=b&sig="

.NOTES
General notes
#>

function SbsRestoreFull {
    param(
        [Parameter(Mandatory = $true)]
        [DbaInstanceParameter]$SqlInstance,
        [Parameter(Mandatory = $true)]
        [string]$DatabaseName,
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $false)]
        [string]$CertificatePath,
        [Parameter(Mandatory = $false)]
        [string]$TempPath
    )

    if ([String]::IsNullOrWhiteSpace($TempPath)) {
        $TempPath = [System.IO.Path]::GetTempPath();
    }

    if ($SqlInstance -is [String]) {
        $SqlInstance = Connect-DbaInstance -SqlInstance $SqlInstance;
    }

    SbsWriteHost "Initiating full backup restore from path or URL";
    $certificateRequested = $false;

    if ($CertificatePath) {
        $certificateRequested = $true;
        SbsRestoreCertificateFromZip -sqlInstance $SqlInstance -zipPath $CertificatePath;
    }

    SbsWriteHost "Initiating restore...";

    $sasUrl = SbsParseSasUrl -Url $Path;
    $isBak = ($Path -Like "*.bak" -or $sasUrl.baseUrlWithPrefix -Like "*.bak")
    
    # We can only remote restore when using plain .BAK files and it is a SAS URL
    if ($null -ne $sasUrl -and $certificateRequested -eq $false -and $isBak -eq $true) {
        SbsWriteHost "Restoring directly using MSSQL URL Restore."
        SbsEnsureCredentialForSasUrl -SqlInstance $sqlInstance -Url $Path;
        Restore-DbaDatabase -SqlInstance $SqlInstance -DatabaseName $DatabaseName -Path $localFilePath -WithReplace -UseDestinationDefaultDirectories -Verbose;
    }
    else {
        
        $deleteAfterRestore = $false;

        # Rename and download
        $fileName = [System.IO.Path]::GetFileName($Path -replace '\?.*$');

        $localFilePath = Join-Path -Path $TempPath -ChildPath $fileName;

        if (Test-Path $localFilePath) { 
            Remove-Item $localFilePath 
        }

        if ($null -ne $sasUrl) {
            SbsWriteHost "Downloading from remote $($sasUrl.baseUrlWithPrefix)"
            SbsDownloadFile $Path $localFilePath $localFilePath;
            $deleteAfterRestore = $true;
        }
        else {
            # This is already something local we can deal with
            $localFilePath = $Path;
        }

        # We might need to decompress
        $isArchive = ($localFilePath -match "\.zip$|\.7z$");
        if ($isArchive) {
            SbsWriteHost "Extracting archive $($localFilePath)"
            $uniqueName = [System.Guid]::NewGuid().ToString()
            $tempDir = Join-Path -Path $tempPath -ChildPath $uniqueName
            Start-Process 7z.exe -ArgumentList "x `"$localFilePath`" -o`"$tempDir`" -y" -Wait;
            SbsWriteDebug "File extracted to $($tempDir)"
            $newLocalFilePath = Get-ChildItem -Path $tempDir -Recurse -Include "*.bacpac", "*.bak" -File | Select-Object -ExpandProperty FullName -First 1
            if ($null -eq $newLocalFilePath) {
                Remove-Item $tempDir -Recurse;
                SbsWriteError -Message "Unable to find backup file in downloaded archive.";
                return;
            }
            if ($deleteAfterRestore -eq $true) {
                Remove-Item -Path $localFilePath -Force;
            }
            $localFilePath = $newLocalFilePath;
        }

        SbsWriteDebug "Local backup file: $($localFilePath)"
        $isBacpac = ($localFilePath -Like "*.bacpac");

        # Grant permissions
        icacls $localFilePath /grant "NT Service\MSSQLSERVER:F"

        # Restore
        if ($isBacpac -eq $false) {
            SbsWriteHost "Restoring '$($localFilePath)' as '$($DatabaseName)' with dbatools"
            Restore-DbaDatabase -SqlInstance $SqlInstance -DatabaseName $DatabaseName -Path $localFilePath -WithReplace -UseDestinationDefaultDirectories -ReplaceDbNameInFile -Verbose -EnableException;
        }
        else {
            SbsWriteHost "Preparing connection string for SQL Package"
            # https://github.com/dataplat/dbatools/issues/9411
            # $connectionString = New-DbaConnectionString -SqlInstance $SqlInstance;
            # $connectionString2 = New-DbaConnectionStringBuilder -ConnectionString $connectionString -InitialCatalog $DatabaseName;
            # Until https://github.com/dataplat/dbatools/issues/9411 just hardcode a simple connectionstring
            $connectionString2 = "Server=$($SqlInstance.ComputerName);Initial Catalog=$DatabaseName;TrustServerCertificate=True;Trusted_Connection=True;";
            # example import to Azure SQL Database using SQL authentication and a connection string
            SbsWriteHost "Restoring using SqlPackage"
            SqlPackage /Action:Import `
                /SourceFile:"$localFilePath" `
                /TargetConnectionString:"$connectionString2"
        }

        # Clean
        if ($deleteAfterRestore -eq $true) {
            Remove-Item -Path $localFilePath -Force;
        }
    }

    SbsWriteHost "Restored database from $($sasUrl.baseUrl)";
}