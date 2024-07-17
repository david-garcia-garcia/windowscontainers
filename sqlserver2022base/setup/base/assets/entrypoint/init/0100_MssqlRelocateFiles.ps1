$global:ErrorActionPreference = if ($null -ne $Env:SBS_ENTRYPOINTERRORACTION ) { $Env:SBS_ENTRYPOINTERRORACTION } else { 'Stop' }

###############################
# LOGIN MODE AND CONNECTION
###############################

$id = "MSSQL16.MSSQLSERVER";

Set-itemproperty -path ('HKLM:\software\microsoft\microsoft sql server\' + $id + '\mssqlserver\supersocketnetlib\tcp\ipall') -name tcpdynamicports -value '' ;
Set-itemproperty -path ('HKLM:\software\microsoft\microsoft sql server\' + $id + '\mssqlserver\supersocketnetlib\tcp\ipall') -name tcpport -value 1433 ;
Set-itemproperty -path ('HKLM:\software\microsoft\microsoft sql server\' + $id + '\mssqlserver') -name LoginMode -value 2;

###############################
# FILE PATHS
###############################

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

# Make sure we set permissions for the system databases directory
if ($null -ne $Env:MSSQL_PATH_SYSTEM) {
    New-Item -ItemType Directory -Force -Path $Env:MSSQL_PATH_SYSTEM | Out-Null;
    icacls $Env:MSSQL_PATH_SYSTEM /grant "NT Service\MSSQLSERVER:F" /t
}

if ($null -ne $Env:MSSQL_PATH_SYSTEM) {

    SbsWriteHost "System Path Override: $($Env:MSSQL_PATH_SYSTEM)";

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
    Set-ItemProperty -Path "HKLM:\software\microsoft\microsoft sql server\$id\mssqlserver\parameters" -Name "SQLArg2" -Value "-l$($Env:MSSQL_PATH_SYSTEM)\master.ldf"

    # Check if the master database files exist in the new location
    if (-not (Test-Path "$($Env:MSSQL_PATH_SYSTEM)\master.mdf") -and -not (Test-Path "$($Env:MSSQL_PATH_SYSTEM)\master.ldf")) {
        SbsWriteHost "Moving existing system databases to new system path";
        # Move the master database files to the new location if this is the first setup
        $newMasterPath = "$($Env:MSSQL_PATH_SYSTEM)\master.mdf"
        $newMasterLog = "$($Env:MSSQL_PATH_SYSTEM)\master.ldf"

        Copy-Item -Path $currentMasterPath -Destination $newMasterPath;
        Copy-Item -Path $currentLogPath -Destination $newMasterLog;
    }
    else {
        SbsWriteHost "System databases already found at destionation path, skipping system database initialization.";
    }
}

########################################################
# START IN MINIMAL MODE TO BE ABLE TO SET SERVERNAME,
# THIS MIGHT MAKE NO SENSE WHEN MASTER IS PRESERVED
# BETWEEN USAGES, BUT IN K8S STATE-LESS BACKUP BASED
# RECREATION, WE NEED TO SET THIS UP EVERY TIME
# THE SERVER BOOTS AS ONLY THE ACTUAL USER DATABASE DATA
# IS PRESERVED
########################################################

$newServerName = SbsGetEnvString -Name "MSSQL_SERVERNAME" -DefaultValue $null;

if ($newServerName) {
    SbsWriteHost "Starting MSSQL in minimal mode to change @@servername to $($newServerName)"
    Start-Process -FilePath "C:\Program Files\Microsoft SQL Server\$($id)\mssql\binn\SQLSERVR.EXE" -ArgumentList "/f /c /m""SQLCMD""" -NoNewWindow -PassThru -RedirectStandardOutput c:\mssql_stdout.txt -RedirectStandardError c:\mssql_stderr.txt

    $processId = (Get-Process -Name "SQLSERVR").Id
    SbsWriteHost "MSSQL process id $($processId)"

    $safetyStopwatch = [System.Diagnostics.Stopwatch]::StartNew();

    # Get current server name
    do {
        Start-Sleep -Milliseconds 250;
        $oldServerName = sqlcmd -S localhost -Q "SELECT @@servername" -h -1 -W | Out-String
        if ($safetyStopwatch.Elapsed.TotalSeconds -gt 10) {
            SbsWriteWarning "@@servername retrieval back off";
            break;
        }
    } while ([string]::IsNullOrWhiteSpace($oldServerName))
    $oldServerName = ($oldServerName -split "`n")[0].Replace("`r", '').Replace("`n", '')

    SbsWriteHost "Renaming $($oldServerName) to $($newServerName)"

    # Define the server name change command
    do {
        Start-Sleep -Milliseconds 1000;
        SbsWriteHost "Attempting sp_dropserver $($oldServerName)..."
        $res = sqlcmd -S localhost -Q "EXEC sp_dropserver $($oldServerName)" | Out-String
        SbsWriteDebug $res;
        if ($safetyStopwatch.Elapsed.TotalSeconds -gt 10) {
            SbsWriteWarning "sp_dropserver retrieval back off";
            break;
        }
    } while (-not [string]::IsNullOrWhiteSpace($res))

    SbsWriteDebug "Addserver $($newServerName)"
    sqlcmd -S localhost -Q "EXEC sp_addserver '$($newServerName)', 'local';"
    
    Stop-Process -Id $processId
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
    SbsWriteDebug "Moving system databases to new location"
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

        New-Item -ItemType Directory -Force -Path $newLogPath | Out-Null; ;
        New-Item -ItemType Directory -Force -Path $newDataPath | Out-Null; ;

        foreach ($file in $db.FileGroups.Files) {
            $newFilename = $newDataPath + "\" + $file.Name + ".mdf"
            if (-not (Test-Path $newFilename)) {
                $filesToMove[$file.FileName] = $newFilename;
                $sql = "ALTER DATABASE $($db.Name) MODIFY FILE ( NAME = $($file.Name), FILENAME = '$newFilename' ); "
                Invoke-DbaQuery -SqlInstance $sqlInstance -Query $sql;
            }
        } 

        foreach ($file in $db.LogFiles) {
            $newFilename = $newLogPath + "\" + $file.Name + ".ldf"
            if (-not (Test-Path $newFilename)) {
                $filesToMove[$file.FileName] = $newFilename;
                $sql = "ALTER DATABASE $($db.Name) MODIFY FILE ( NAME = $($file.Name), FILENAME = '$newFilename' ); "
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
SbsWriteDebug "Calling Get-DbaDefaultPath to retrieve default path configuration"
$dbaDefaultPath = Get-DbaDefaultPath -SqlInstance $sqlInstance;

$backupPath = $dbaDefaultPath.Backup;
$dataPath = $dbaDefaultPath.Data;
$logPath = $dbaDefaultPath.Log;

if (-not (Test-Path $backupPath)) { New-Item -ItemType Directory -Path $backupPath | Out-Null }
if (-not (Test-Path $dataPath)) { New-Item -ItemType Directory -Path $dataPath | Out-Null }
if (-not (Test-Path $logPath)) { New-Item -ItemType Directory -Path $logPath | Out-Null }

SbsWriteHost "SQL Backup Path: $backupPath";
SbsWriteHost "SQL Data Path: $dataPath";
SbsWriteHost "SQL Log Path: $logPath";
