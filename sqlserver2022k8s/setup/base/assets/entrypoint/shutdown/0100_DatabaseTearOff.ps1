Import-Module dbatools;

$sqlInstance = Connect-DbaInstance -SqlInstance localhost;
$dbaDefaultPath = Get-DbaDefaultPath -SqlInstance $sqlInstance;
$dataPath = $dbaDefaultPath.Data;

# Stop all backup related scheduled tasks
[bool]$autoBackup = SbsGetEnvBool -Name "MSSQL_AUTOBACKUP";

try {

    # Stop all backup tasks
    Stop-ScheduledTask -TaskName "MssqlDifferential";
    Stop-ScheduledTask -TaskName "MssqlFull";
    Stop-ScheduledTask -TaskName "MssqlLog";
    Stop-ScheduledTask -TaskName "MssqlSystem";
    Stop-ScheduledTask -TaskName "MssqlReleaseMemory";

    Disable-ScheduledTask -TaskName "MssqlDifferential"
    Disable-ScheduledTask -TaskName "MssqlFull"
    Disable-ScheduledTask -TaskName "MssqlLog"
    Disable-ScheduledTask -TaskName "MssqlSystem"
    Disable-ScheduledTask -TaskName "MssqlReleaseMemory"

    # Disable all remote access, so no new transactions happen before the closing backup
    # if database is set in READONLY mode, then the last LOG backup will by COPY_ONLY
    # which will NOT work for a restore secuence chain (it works, but it's more difficult)
    # to determine the restore sequence.
    SbsWriteHost "Disabling remote access...."
    Set-DbaSpConfigure -SqlInstance $sqlInstance -Name 'remote access' -Value 0;

    if ($autoBackup -eq $true) {
        SbsWriteHost "Performing shutdown backups...."
        SbsMssqlRunBackups -backupType "LOGNOW";
        SbsMssqlRunBackups -backupType "SYSTEM";
    }
    elseif ($Env:MSSQL_LIFECYCLE -eq "BACKUP") {
        SbsWriteHost "Performing shutdown backups...."
        SbsMssqlRunBackups -backupType "LOGNOW";
    }

    switch ($Env:MSSQL_LIFECYCLE) {
        'ATTACH' {
            # Although this image is aimed at only being able to handle one database per MSSQL instance,
            # there is no harm in supporting attaching/dettaching multiple user databases in the ATTACH
            # lifecycle so it can be used in development environments or ad-hoc setups to handle
            # multiple databases.
            SbsWriteHost "Dumping database state and detaching...";
            $jsonFilePath = Join-Path -Path $dataPath -ChildPath "structure.json";
            $allDatabases = Get-DbaDatabase -SqlInstance $sqlInstance | Where-Object { $_.IsSystemObject -eq $false }
            $databasesInfo = @();
            foreach ($database in $allDatabases) {
                SbsWriteHost "Processing database $($database.Name)";
                $dataFiles = @()  # Initialize an empty array to hold file details
                # Iterate through each FileGroup and each file within that group
                foreach ($fileGroup in $database.FileGroups) {
                    SbsWriteHost "Processing file group $($fileGroup.Name)";
                    foreach ($file in $fileGroup.Files) {
                        # Create a custom object with the LogicalName and PhysicalName for each file
                        SbsWriteHost "Processing file $($file.Name) at path $($file.FileName)";
                        $fileInfo = New-Object PSObject -Property @{
                            "LogicalName"  = $file.Name  # Assuming 'Name' is the logical name of the file
                            "PhysicalName" = $file.FileName  # Assuming 'FileName' is the physical path of the file
                        }
                        $dataFiles += $fileInfo
                    }
                }
                $dbInfo = @{
                    "DatabaseName" = $database.Name
                    "Files"        = $dataFiles
                }
                $databasesInfo += $dbInfo;
                SbsWriteHost "Taking $($database.Name) offline....";
                Set-DbaDbState -SqlInstance $sqlInstance -Database $database.Name -Offline -Force -Confirm:$false;
                SbsWriteHost "Dettaching $($database.Name)....";
                Dismount-DbaDatabase -SqlInstance $sqlInstance -Database $database.Name -Confirm:$false;
            }

            $output = @{
                "databases" = $databasesInfo
            }

            $output | ConvertTo-Json -Depth 99 | Out-File $jsonFilePath;
        }
        'PERSISTENT' {
            # Do nothing but stop the sql service, in persitent mode
        }
    }
}
finally {
    # Make sure we stop the service
    Stop-Service MSSQLSERVER;
}