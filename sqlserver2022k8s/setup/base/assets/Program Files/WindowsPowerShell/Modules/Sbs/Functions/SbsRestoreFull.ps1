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

    Import-Module dbatools;

    if ($SqlInstance -is [String]) {
        $SqlInstance = Connect-DbaInstance -SqlInstance $SqlInstance;
    }

    SbsWriteHost "Initiating full backup restore from path or URL";
    $certificateRequested = $false;

    if (-not [String]::IsNullOrWhiteSpace($CertificatePath)) {

        $certificateRequested = $true;
        $certPath = Join-Path $TempPath "tempCert_$((Get-Random -Maximum 50)).zip";

        if ($CertificatePath -match "^http") {
            SbsWriteDebug "Downloading certificate from URL"
            Invoke-WebRequest -Uri $certUrl -OutFile $certPath -UseBasicParsing -TimeoutSec 45;
        }
        else {
            Copy-Item $CertificatePath $certPath;
        }
        
        SbsRestoreCertificateFromZip 'localhost' $certPath;
        Remove-Item $certPath;
    }

    SbsWriteHost "Initiating restore...";

    $sasUrl = SbsParseSasUrl -Url $Path;
    $isBacpac = ($Path -Like "*.bacpac" -or $sasUrl.baseUrlWithPrefix -Like "*.bacpac")

    # If this was a SAS url and it is not encrypted, directly restore
    # MSSQL built in functionality.
    if ($null -ne $sasUrl -and $certificateRequested -eq $false -and $isBacpac -eq $false) {
        SbsWriteHost "Restoring directly using MSSQL URL Restore."
        SbsEnsureCredentialForSasUrl -SqlInstance $sqlInstance -Url $Path;
        Restore-DbaDatabase -SqlInstance $SqlInstance -DatabaseName $DatabaseName -Path $localFilePath -WithReplace -UseDestinationDefaultDirectories -Verbose;
    }
    else {
        SbsWriteHost "Downloading and restoring from a local copy."

        # Rename and download
        $fileName = [System.IO.Path]::GetFileName($Path -replace '\?.*$');

        $localFilePath = Join-Path -Path $TempPath -ChildPath $fileName;

        if (Test-Path $localFilePath) { 
            Remove-Item $localFilePath 
        }

        SbsDownloadFile $Path $localFilePath $localFilePath;

        # Grant permissions
        icacls $localFilePath /grant "NT Service\MSSQLSERVER:F"

        # Restore
        if ($isBacpac -eq $false) {
            Restore-DbaDatabase -SqlInstance $SqlInstance -DatabaseName $DatabaseName -Path $localFilePath -WithReplace -UseDestinationDefaultDirectories -Verbose;
        }
        else {
            $connectionString = New-DbaConnectionString -SqlInstance $SqlInstance;
            $connectionString2 = New-DbaConnectionStringBuilder -ConnectionString $connectionString -InitialCatalog $DatabaseName;
            # example import to Azure SQL Database using SQL authentication and a connection string
            SqlPackage /Action:Import `
            /SourceFile:"$localFilePath" `
            /TargetConnectionString:"$connectionString2" `
        }

        # Clean
        Remove-Item -Path $localFilePath -Force;
    }

    SbsWriteHost "Restored database from $backupUrl.";
}