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

if ($null -eq $tempDir) {
    $tempDir = $Env:TMP;
}

if (-not (Test-Path $backupPath)) { New-Item -ItemType Directory -Path $backupPath; }
if (-not (Test-Path $dataPath)) { New-Item -ItemType Directory -Path $dataPath; }
if (-not (Test-Path $logPath)) { New-Item -ItemType Directory -Path $logPath; }
if (-not (Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir; }

SbsWriteHost "SQL Backup Path: $backupPath";
SbsWriteHost "SQL Data Path: $dataPath";
SbsWriteHost "SQL Log Path: $logPath";

$databaseName = SbsGetEnvString -Name "MSSQL_DB_NAME" -DefaultValue $null;
$databaseRecoveryModel = SbsGetEnvString -Name "MSSQL_DB_RECOVERYMODEL" -DefaultValue "SIMPLE";

if ($null -eq $tempDir) {
    SbsWriteWarning "No temporary directory set in ENV SBS_TEMPORARY, using default c:\windows\temp. Note that this will consume storage inside the container mount (MAX 20GB) and can become an issue with very large databases.";
    $tempDir = "c:\windows\temp";
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

if (($false -eq $restored) -and ($Env:MSSQL_LIFECYCLE -ne 'ATTACH') -and ($Env:MSSQL_LIFECYCLE -ne 'PERSISTENT')) {
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

# If nothing was restored try from a backup
if (($restored -eq $false) -and (-not [String]::isNullOrWhitespace($databaseName))) {
    $backupPathForRestore = $backupPath;
    if (-not [string]::IsNullOrWhiteSpace($Env:MSSQL_PATH_BACKUPURL)) {
        $backupPathForRestore = $Env:MSSQL_PATH_BACKUPURL;
    }

    $restored = SbsRestoreDatabase -SqlInstance $sqlInstance -DatabaseName $databaseName -Path $backupPathForRestore;
}

if (($restored -eq $false) -and (-not [String]::isNullOrWhitespace($databaseName))) {
    # Create the database
    SbsWriteHost "Creating database $databaseName"
    New-DbaDatabase -SqlInstance $sqlInstance -Name $databaseName;
}

if (-not [String]::IsNullOrWhiteSpace($databaseName)) {
    SbsWriteDebug "Testing that database $($databaseName) exists."
    Get-DbaDatabase -SqlInstance $sqlInstance -Database $databaseName | Set-DbaDbRecoveryModel -RecoveryModel $databaseRecoveryModel -Confirm:$false | Out-Null;
}