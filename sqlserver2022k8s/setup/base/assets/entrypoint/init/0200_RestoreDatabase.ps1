########################################################
# Restore or attach the database
########################################################

$global:ErrorActionPreference = if ($null -ne $Env:SBS_ENTRYPOINTERRORACTION ) { $Env:SBS_ENTRYPOINTERRORACTION } else { 'Stop' }

Import-Module dbatools;

$sqlInstance = Connect-DbaInstance -SqlInstance localhost;

$restored = $false;

# Prepare path for data, log, backup, temporary and control
$dbaDefaultPath = Get-DbaDefaultPath -SqlInstance localhost;

$backupPath = $dbaDefaultPath.Backup;
$dataPath = $dbaDefaultPath.Data;
$logPath = $dbaDefaultPath.Log;
$tempDir = $Env:SBS_TEMPORARY;

if (-not (Test-Path $backupPath)) { New-Item -ItemType Directory -Path $backupPath; }
if (-not (Test-Path $dataPath)) { New-Item -ItemType Directory -Path $dataPath; }
if (-not (Test-Path $logPath)) { New-Item -ItemType Directory -Path $logPath; }
if (-not (Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir; }

SbsWriteHost "SQL Backup Path: $backupPath";
SbsWriteHost "SQL Data Path: $dataPath";
SbsWriteHost "SQL Log Path: $logPath";

$controlPath = $Env:MSSQL_PATH_CONTROL;

$databaseName = SbsGetEnvString -Name "MSSQL_DB_NAME" -DefaultValue "";
$databaseRecoveryModel = SbsGetEnvString -Name "MSSQL_DB_RECOVERYMODEL" -DefaultValue "SIMPLE";

if ($null -eq $tempDir) {
    SbsWriteWarning "No temporary directory set in ENV SBS_TEMPORARY, using default c:\windows\temp. Note that this will consume storage inside the container mount (MAX 20GB) and can become an issue with very large databases.";
    $tempDir = "c:\windows\temp";
}

# Make sure the credential is available for the given URL
if (-not [string]::isNullOrWhiteSpace($Env:MSSQL_PATH_BACKUPURL)) {
    $backupUrl = SbsParseSasUrl -Url $Env:MSSQL_PATH_BACKUPURL;
    SbsEnsureCredentialForSasUrl -SqlInstance $sqlInstance -Url $Env:MSSQL_PATH_BACKUPURL;
}

if ($restored -eq $false -and $Env:MSSQL_LIFECYCLE -eq 'ATTACH') {

    SbsWriteHost "Lifecycle attach mode starting up..."
    $structurePath = Join-Path -Path $dataPath -ChildPath "structure.json";

    if (Test-Path $structurePath) {

        $jsonContent = Get-Content $structurePath | ConvertFrom-Json;
        
        foreach ($db in $jsonContent.databases) {
            $databaseName = $db.DatabaseName;
            $dataFiles = $db.Files | ForEach-Object { $_.PhysicalName };
            Mount-DbaDatabase -SqlInstance $sqlInstance -Database $databaseName -File $dataFiles;
            SbsWriteHost "Successfully attached database '$databaseName'";
        }
        
        $restored = $true
    }
    else {
        SbsWriteHost "Lifecycle attach mode did not find any databases to attach. Probably running a fresh installation."
    }
}

if (($false -eq $restored) -and ($Env:MSSQL_LIFECYCLE -ne 'ATTACH')) {
    $hasData = (Get-ChildItem $dataPath -File | Measure-Object).Count -gt 0 -or (Get-ChildItem $logPath -File | Measure-Object).Count -gt 0;
    if ($hasData -eq $true) {
        $clearDataPaths = SbsGetEnvBool -Name "MSSQL_CLEARDATAPATHS" -DefaultValue $false;
        if ($clearDataPaths -and $Env:MSSQL_LIFECYCLE -eq "BACKUP") {
            # This is only here because on docker images have state. If we are using BACKUP lifecyle we
            # are expecting to have NO STATE whatsoever.
            SbsWriteWarning "######################################";
            SbsWriteWarning "# Clearing data and log paths. This is only happening because";
            SbsWriteWarning "# MSSQL_LIFECYCLE=BACKUP and MSSQL_CLEARDATAPATHS=True";
            SbsWriteWarning "######################################";
            Get-DbaDatabase -SqlInstance $sqlInstance -ExcludeSystem | Remove-DbaDatabase -Verbose -Confirm:$false;
            Get-ChildItem -Path $dataPath | Remove-Item -Recurse -Force;
            Get-ChildItem -Path $logPath | Remove-Item -Recurse -Force;
        }
        else {
            Write-Error "No structure.json file was found to attach database, yet there are files in the data and log directories. Please clear them. You can use the MSSQL_CLEARDATAPATHS=True in combination with MSSQL_LIFECYCLE=BACKUP to clear the paths automatically.";
            return;
        }
    }
}

# One time startup-instructions are provided in a stand-alone file that will be consumed
# and renamed. These instructions allow things such as:
# Restore from a remote backpack file
# Restore from a remote backup file
# Restore to a point in time
# Define the path to the startup file
$startupFile = Join-Path -Path $controlPath -ChildPath "startup.yaml";

# Check if the startup file exists
if (Test-Path $startupFile) {

    SbsWriteHost "Initiating startup instructions...";

    # Load the steps from the startup file
    $steps = (Get-Content $startupFile -Raw | ConvertFrom-Yaml).steps

    # Check if there are any steps defined
    if ($steps -and $steps.Count -gt 0) {
        foreach ($step in $steps) {
            switch ($step.type) {
                'restore_bacpac' {
                    if ($step.url -match "\.zip$" -or $step.url -match "\.7z$") {
                        # Handle decompression for .zip or .7z files
                        $tempPath = [System.IO.Path]::GetTempFileName();
                        Invoke-WebRequest -Uri $step.url -OutFile $tempPath -UseBasicParsing
                        if ($step.url -match "\.zip$") {
                            Expand-Archive -Path $tempPath -DestinationPath "tempDir" -Force
                        }
                        elseif ($step.url -match "\.7z$") {
                            # Assuming 7z.exe is available in the system PATH
                            Start-Process 7z.exe -ArgumentList "x `"$tempPath`" -o`"tempDir`" -p`"$($step.pwd)`" -y" -Wait;
                        }
                        $bacpacPath = Get-ChildItem "tempDir" -Filter "*.bacpac" | Select-Object -ExpandProperty FullName -First 1;
                        Restore-DbaDatabase -SqlInstance 'localhost' -Path $bacpacPath;
                        Remove-Item "tempDir" -Recurse -Force;
                        Remove-Item $tempPath -Force;
                    }
                    else {
                        # Direct restore from URL without decompression
                        Restore-DbaDatabase -SqlInstance 'localhost' -Path $step.url;
                    }
                    $restored = $true;
                }
                'restore_full' {
                    SbsWriteHost "Initiating full backup restore";
                    # Download and import the backup certificate
                    $certUrl = $step.cert;
                    $backupUrl = $step.url;
                    if ($null -ne $certUrl) {
                        $certPath = "C:\windows\temp\tempCert.zip";
                        Invoke-WebRequest -Uri $certUrl -OutFile $certPath -UseBasicParsing -TimeoutSec 60;
                        SbsRestoreCertificateFromZip 'localhost' $certPath;
                        SbsWriteHost "Certificate restored";
                    }
                    SbsWriteHost "Initiating restore...";
                    # Rename and download
                    $fileName = [System.IO.Path]::GetFileName($backupUrl -replace '\?.*$');
                    $localFilePath = Join-Path -Path $tempDir -ChildPath $fileName;
                    if (Test-Path $localFilePath) { Remove-Item $localFilePath }
                    SbsDownloadFile $backupUrl $localFilePath $localFilePath;
                    # Grant permissions
                    icacls $localFilePath /grant "NT Service\MSSQLSERVER:F"
                    # Restore
                    Restore-DbaDatabase -SqlInstance 'localhost' -DatabaseName $databaseName -Path $localFilePath -WithReplace -UseDestinationDefaultDirectories -Verbose;
                    # Clean
                    Remove-Item -Path $localFilePath -Force;
                    $restored = $true;
                    SbsWriteHost "Restored database from $backupUrl.";
                }
                default {
                    SbsWriteHost "$($step.type) not supported.";
                }
            }
        }
    }

    SbsArchiveFile $startupFile;
}
else {
    SbsWriteHost "Startup file not found at path $startupFile, resuming regular lifecycle startup."
}

# If nothing was restored try from a backup
if (($restored -eq $false) -and ($null -ne $databaseName)) {
    SbsWriteHost "Starting database restore...";
    $files = @();
    if ($null -ne $backupUrl) {
        $ctx = New-AzStorageContext -StorageAccountName $backupUrl.storageAccountName -SasToken $backupUrl.sasToken;
        $blobs = Get-AzStorageBlob -Container $backupUrl.container -Context $ctx -Prefix $backupUrl.prefix |
        Where-Object { ($_.AccessTier -ne 'Archive') -and ($_.Length -gt 0) };
        if ($blobs -and $blobs.Count -gt 0) {
            $blobUrls = $blobs | ForEach-Object { $backupUrl.baseUrl + "/" + $_.Name } 
            $files = Get-DbaBackupInformation -SqlInstance $sqlInstance -Path $blobUrls | Where-Object { $_.Database -eq $databaseName };
        }
    }
    else {
        $files = Get-DbaBackupInformation -SqlInstance $sqlInstance -Path $backupPath | Where-Object { $_.Database -eq $databaseName };
    }
    if ($null -ne $files -and $files.Count -gt 0) {
        $files | Restore-DbaDatabase -SqlInstance $sqlInstance -DatabaseName $databaseName -EnableException -WithReplace -UseDestinationDefaultDirectories -Verbose;
        $database = Get-DbaDatabase -SqlInstance $sqlInstance -Database $databaseName;
        if ($database) {
            SbsWriteHost "Database $($databaseName) restored successfully."
            $restored = $true;
            # The teardown scripts puts the backup in ReadOnly, and this will be the state after restore
            $database | Set-DbaDbState -ReadWrite -Force;
        }
        else {
            SbsWriteError "Database $($databaseName) was not restored successfully."
        }
    }
    else {
        SbsWriteWarning "No backup files found for database $databaseName. This might happen if this is the first time you spin up this instance.";
    }
}

if (($restored -eq $false) -and (-not [String]::isNullOrWhitespace($databaseName))) {
    # Create the database
    New-DbaDatabase -SqlInstance $sqlInstance -Name $databaseName;
}

if (-not [String]::isNullOrWhitespace($databaseName)) {
    Get-DbaDatabase -SqlInstance $sqlInstance -Database $databaseName | Set-DbaDbRecoveryModel -RecoveryModel $databaseRecoveryModel -Confirm:$false | Out-Null;
}