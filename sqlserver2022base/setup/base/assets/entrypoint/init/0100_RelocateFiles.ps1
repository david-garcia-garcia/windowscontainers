$global:ErrorActionPreference = if ($null -ne $Env:SBS_ENTRYPOINTERRORACTION ) { $Env:SBS_ENTRYPOINTERRORACTION } else { 'Stop' }

$id = "MSSQL16.MSSQLSERVER";
Set-itemproperty -path ('HKLM:\software\microsoft\microsoft sql server\' + $id + '\mssqlserver\supersocketnetlib\tcp\ipall') -name tcpdynamicports -value '' ;
Set-itemproperty -path ('HKLM:\software\microsoft\microsoft sql server\' + $id + '\mssqlserver\supersocketnetlib\tcp\ipall') -name tcpdynamicports -value '' ;
Set-itemproperty -path ('HKLM:\software\microsoft\microsoft sql server\' + $id + '\mssqlserver\supersocketnetlib\tcp\ipall') -name tcpport -value 1433 ;
Set-itemproperty -path ('HKLM:\software\microsoft\microsoft sql server\' + $id + '\mssqlserver') -name LoginMode -value 2;

if ($null -ne $Env:MSSQL_PATH_DATA) {
    New-Item -ItemType Directory -Force -Path $Env:MSSQL_PATH_DATA;
    Set-itemproperty -path ('HKLM:\software\microsoft\microsoft sql server\' + $id + '\mssqlserver') -name "DefaultData" -value $Env:MSSQL_PATH_DATA;
}

if ($null -ne $Env:MSSQL_PATH_LOG) {
    New-Item -ItemType Directory -Force -Path $Env:MSSQL_PATH_LOG;
    Set-itemproperty -path ('HKLM:\software\microsoft\microsoft sql server\' + $id + '\mssqlserver') -name "DefaultLog" -value $Env:MSSQL_PATH_LOG; 
}

if ($null -ne $Env:MSSQL_PATH_BACKUP) {

    New-Item -ItemType Directory -Force -Path $Env:MSSQL_PATH_BACKUP;
    Set-itemproperty -path ('HKLM:\software\microsoft\microsoft sql server\' + $id + '\mssqlserver') -name "BackupDirectory" -value $Env:MSSQL_PATH_BACKUP;
}

if ($null -ne $Env:MSSQL_PATH_SYSTEM) {

    SbsWriteHost "System Path Override: $($Env:MSSQL_PATH_SYSTEM)";

    # Create the directories if they don't exist
    New-Item -ItemType Directory -Force -Path $Env:MSSQL_PATH_SYSTEM;

    # Determine the current location of the master database files
    $currentMasterPath = (Get-ItemProperty -Path "HKLM:\software\microsoft\microsoft sql server\$id\mssqlserver\parameters").SQLArg0 -replace '-d', ''
    $currentLogPath = (Get-ItemProperty -Path "HKLM:\software\microsoft\microsoft sql server\$id\mssqlserver\parameters").SQLArg2 -replace '-l', ''

    SbsWriteHost "Image default master Data Path: $($currentMasterPath)";
    SbsWriteHost "Image default master Log Path: $($currentLogPath)";

    # Check that current master exists. During DEV i found it common to clear the
    # volume contents, but because docker insists in keeping container internal state
    # it will be pointing to a non existing master database
    if (-not (Test-Path $currentMasterPath) -or -not (Test-Path $currentLogPath)) {
        SbsWriteHost "Master data not found: $currentMasterPath";
        SbsWriteHost "Master log not found: $currentLogPath";
        SbsWriteError "Currently configured MASTER database for the engine does not exist. If you deleted them reset the container state to reset to internal defaults.";
    }

    # Update the registry to point to the new locations
    Set-ItemProperty -Path "HKLM:\software\microsoft\microsoft sql server\$id\mssqlserver\parameters" -Name "SQLArg0" -Value "-d$($Env:MSSQL_PATH_SYSTEM)\master.mdf"
    Set-ItemProperty -Path "HKLM:\software\microsoft\microsoft sql server\$id\mssqlserver\parameters" -Name "SQLArg2" -Value "-l$($Env:MSSQL_PATH_SYSTEM)\mastlog.ldf"

    # Check if the master database files exist in the new location
    if (-not (Test-Path "$($Env:MSSQL_PATH_SYSTEM)\master.mdf") -and -not (Test-Path "$($Env:MSSQL_PATH_SYSTEM)\mastlog.ldf")) {
        SbsWriteHost "Moving existing system databases to new system path";
        # Move the master database files to the new location if this is the first setup
        Copy-Item -Path $currentMasterPath -Destination "$($Env:MSSQL_PATH_SYSTEM)\master.mdf";
        Copy-Item -Path $currentLogPath -Destination "$($Env:MSSQL_PATH_SYSTEM)\mastlog.ldf";
    }
    else {
        SbsWriteHost "System databases already found at destionation path, skipping system database initialization.";
    }
}

###############################
# START THE SERVER
###############################
SbsWriteHost "MSSQLSERVER Service Starting...";
Start-Service 'MSSQLSERVER';
SbsWriteHost "MSSQLSERVER Service started";

$sqlInstance = Connect-DbaInstance -SqlInstance localhost;

if ($null -ne $Env:MSSQL_PATH_SYSTEM) {
    # Move system databases to the new location
    # This is a simplified example; consider each database's requirements
    # TODO: Figure out what to do with tempdb
    # Get system databases
    $systemDatabases = Get-DbaDatabase -SqlInstance $sqlInstance | Where-Object { $_.IsSystemObject -eq $true }

    # Iterate over system databases and generate ALTER DATABASE commands for each
    $filesToMove = @{}

    foreach ($db in $systemDatabases) {

        # Not these ones
        if (($db.Name -eq "master") -or ($db.Name -eq "tempdb")) {
            continue;
        }
 
        SbsWriteHost "Processing system database $($db.Name)";

        $newDataPath = "$($Env:MSSQL_PATH_SYSTEM)\$($db.Name)";
        $newLogPath = "$($Env:MSSQL_PATH_SYSTEM)\$($db.Name)";

        New-Item -ItemType Directory -Force -Path $newLogPath;
        New-Item -ItemType Directory -Force -Path $newDataPath;

        foreach ($file in $db.FileGroups.Files) {
            $newFilename = $newDataPath + "\" + $file.Name + ".mdf"
            if (-not (Test-Path $newFilename)) {
                $filesToMove[$file.FileName] = $newFilename;
                $sql = "ALTER DATABASE $($db.Name) MODIFY FILE ( NAME = $($file.Name), FILENAME = '$newFilename' );"
                Invoke-DbaQuery -SqlInstance $sqlInstance -Query $sql;
            }
        } 

        foreach ($file in $db.LogFiles) {
            $newFilename = $newLogPath + "\" + $file.Name + ".ldf"
            if (-not (Test-Path $newFilename)) {
                $filesToMove[$file.FileName] = $newFilename;
                $sql = "ALTER DATABASE $($db.Name) MODIFY FILE ( NAME = $($file.Name), FILENAME = '$newFilename' );"
                Invoke-DbaQuery -SqlInstance $sqlInstance -Query $sql;
            }
        }
    }
 
    if ($filesToMove.Count -gt 0) {
        Stop-Service 'MSSQLSERVER';
        foreach ($sourcePath in $filesToMove.Keys) {
            $destinationPath = $filesToMove[$sourcePath];
            SbsWriteHost "Moving $($sourcePath) to $($destinationPath)";
            Move-Item -Path $sourcePath -Destination $destinationPath
        }
        Start-Service 'MSSQLSERVER';
    }
}

# Prepare path for data, log, backup, temporary and control
$dbaDefaultPath = Get-DbaDefaultPath -SqlInstance $sqlInstance;

$backupPath = $dbaDefaultPath.Backup;
$dataPath = $dbaDefaultPath.Data;
$logPath = $dbaDefaultPath.Log;

if (-not (Test-Path $backupPath)) { New-Item -ItemType Directory -Path $backupPath; }
if (-not (Test-Path $dataPath)) { New-Item -ItemType Directory -Path $dataPath; }
if (-not (Test-Path $logPath)) { New-Item -ItemType Directory -Path $logPath; }

SbsWriteHost "SQL Backup Path: $backupPath";
SbsWriteHost "SQL Data Path: $dataPath";
SbsWriteHost "SQL Log Path: $logPath";
