
Import-Module dbatools;
$sqlInstance = Connect-DbaInstance -SqlInstance localhost;
SbsWriteHost "Connected to localhost database.";
$dbaDefaultPath = Get-DbaDefaultPath -SqlInstance $sqlInstance;
$dataPath = $dbaDefaultPath.Data;
SbsWriteHost "Default data path: $dataPath";

# Stop all backup related scheduled tasks
[int]$autoBackup = SbsGetEnvInt -Name "MSSQL_AUTOBACKUP" -DefaultValue 0;

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

# Set all databases in readonly mode
Set-DbaDbState -SqlInstance $sqlInstance -AllDatabases -ReadOnly -Force;

if ($autoBackup -eq 1) {
    # Run a final backup before getting rid of the pod
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
        Stop-Service MSSQLSERVER;
    }
}