# La función de cleanup backups de Hallengren no funciona
# con el parámetro -CleanupTime cuando trabajamos con blobs
# de Azure. Por lo tanto, se ha creado esta función para suplir
# la carencia.
function SbsMssqlCleanupBackups {
    param(
        [Parameter(Mandatory = $true)]
        [object]$SqlInstance,
        [Parameter(Mandatory = $true)]
        [string]$Url,
        [Parameter(Mandatory = $true)]
        [string] $DatabaseName,
        [int] $CleanupTimeFull = $null,
        [int] $CleanupTimeDiff = $null,
        [int] $CleanupTimeLog = $null,
        [bool] $WhatIf = $false
    )

    if ($null -eq $cleanupTimeLog) {
	    $cleanupTimeLog = SbsGetEnvInt -Name "MSSQL_BACKUP_CLEANUPTIME_LOG" -DefaultValue 0;
    }

    if ($null -eq $cleanupTimeDiff) {
	    $cleanupTimeDiff = SbsGetEnvInt -Name "MSSQL_BACKUP_CLEANUPTIME_DIFF" -DefaultValue 0;
    }

    if ($null -eq $cleanupTimeFull) {
	    $cleanupTimeFull = SbsGetEnvInt -Name "MSSQL_BACKUP_CLEANUPTIME_FULL" -DefaultValue 0;
    }

    $backupUrl = SbsParseSasUrl -Url $Url;

    if ($null -eq $backupUrl) {
        SbsWriteWarning "Invalid backup URL. This method is only supported for Azure Blob Storage URLs.";
        return;
    }

    SbsEnsureCredentialForSasUrl -SqlInstance $SqlInstance -Url $backupUrl.url;

    SbsWriteDebug "Connecting to storage account $($backupUrl.baseUrlWithPrefix) to search for stale backups.";
    $ctx = New-AzStorageContext -StorageAccountName $backupUrl.storageAccountName -SasToken $backupUrl.sasToken;

    SbsWriteDebug "Retrieving backup information from storage account $($backupUrl.baseUrlWithPrefix) to search for stale backups.";
    $blobs = Get-AzStorageBlob -Container $backupUrl.container -Context $ctx -Prefix $backupUrl.prefix |
        Where-Object { ($_.AccessTier -ne 'Archive') -and ($_.Length -gt 0) };

    if ($blobs.Count -eq 0) {
        SbsWriteWarning "Found $($blobs.Count) blobs in container $($backupUrl.baseUrl)";
        return;
    }

    if ($blobs.Count -gt 100) {
        SbsWriteWarning "Found $($blobs.Count) blobs in container $($backupUrl.baseUrl). Reading backup headers for remote files is slow and will not scale. Keep LTS storage separate from active backups."
    }
    
    $blobUrls = $blobs | ForEach-Object { $backupUrl.baseUrl + "/" + $_.Name }
    
    # Define the cache directory path
    $cacheDirectory = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "MSSQLHEADERS\$($backupUrl.storageAccountName)\$($backupUrl.container)";
    New-Item -ItemType Directory -Path $cacheDirectory -Force | Out-Null
    SbsWriteDebug "Cache directory: $cacheDirectory"

    # Get rid of old cached items
    Get-ChildItem -Path $cacheDirectory -Filter "*.json" | Where-Object { $_.CreationTime -lt (Get-Date).AddDays(-7) } | Remove-Item -Force;

    # Loop through the $blobUrls and check if the metadata is already present in the cache
    $cachedFiles = @{}
    foreach ($blobUrl in $blobUrls) {
        $blobName = ($blobUrl -replace $backupUrl.baseUrl, '').TrimStart('/');
        $cacheFilePath = (Join-Path -Path $cacheDirectory -ChildPath ($blobName -replace '[/:]', '_')) + ".json"
        if (Test-Path -Path $cacheFilePath) {
            $cachedFile = Get-Content -Path $cacheFilePath | ConvertFrom-Json
            
            $hashTable = @{}
            $cachedFile.PSObject.Properties | ForEach-Object {
                $hashTable[$_.Name] = $_.Value;
            }

            # Workaround for BigInt not serializing properly!
            # https://github.com/PowerShell/PowerShell/pull/21000
            $hashTable['LastLsn'] = [bigint]::Parse($hashTable['LastLsn']);
            $hashTable['FirstLsn'] = [bigint]::Parse($hashTable['FirstLsn']);
            $hashTable['DatabaseBackupLsn'] = [bigint]::Parse($hashTable['DatabaseBackupLsn']);
            $hashTable['CheckpointLsn'] = [bigint]::Parse($hashTable['CheckpointLsn']);
            
            SbsWriteDebug "$backupUrl <- $cacheFilePath"
            $cachedFiles[$blobUrl] = $cachedFile
        }
    }

    # Get the files that are not present in the cache
    $filesToFetch = $blobUrls | Where-Object { -not $cachedFiles.ContainsKey($_) }
    SbsWriteDebug "Fetching backup metadata for $($filesToFetch.Count) files";

    # Fetch the missing files using Get-DbaBackupInformation
    if ($filesToFetch.Count -gt 0) {
        $files = Get-DbaBackupInformation -SqlInstance $SqlInstance -Path $filesToFetch;
        foreach ($file in $files) {
         
            $blobUrl = $file.Path[0];
            $blobName = ($blobUrl -replace $backupUrl.baseUrl, '').TrimStart('/');
            $cacheFilePath = (Join-Path -Path $cacheDirectory -ChildPath ($blobName -replace '[/:]', '_')) + ".json"

            # Workaround for BigInt not serializing properly!
            # https://github.com/PowerShell/PowerShell/pull/21000
            $hashTable = @{}
            $file.PSObject.Properties | ForEach-Object {
                $hashTable[$_.Name] = $_.Value;
            }

            $hashTable['LastLsn'] = $hashTable['LastLsn'].ToString();
            $hashTable['FirstLsn'] = $hashTable['FirstLsn'].ToString();
            $hashTable['DatabaseBackupLsn'] = $hashTable['DatabaseBackupLsn'].ToString();
            $hashTable['CheckpointLsn'] = $hashTable['CheckpointLsn'].ToString();

            $hashTable | ConvertTo-Json -Depth 100 | Set-Content -Path $cacheFilePath
            
            $cachedFiles[$blobUrl] = Get-Content -Path $cacheFilePath | ConvertFrom-Json
            SbsWriteDebug "$blobUrl <- $cacheFilePath"
        }
    }

    $files = $cachedFiles.Values | Where-Object { $_.Database -eq $databaseName }

    if ($files.Count -eq 0) {
        SbsWriteDebug "No backups found for database $databaseName"
        return;
    }

    $fullType = "Database";
    $diffType = "Database Differential";
    $logType = "Transaction Log";

    # Get candidates for deletion
    $filteredFiles = $files | Where-Object {
        ($_.Type -eq $fullType -and $_.Start -lt (Get-Date).AddHours(-$CleanupTimeFull)) -or
        ($_.Type -eq $diffType -and $_.Start -lt (Get-Date).AddHours(-$CleanupTimeDiff)) -or
        ($_.Type -eq $logType -and $_.Start -lt (Get-Date).AddHours(-$CleanupTimeLog))
    } | Sort-Object -Property LastLSN;

    if ($filteredFiles.Count -eq 0) {
        SbsWriteDebug "No backups found for database $databaseName that are older than $CleanupTime hours"
        SbsWriteDebug $files | Format-List;
        return;
    }

    # Loop through the sorted files
    foreach ($file in $filteredFiles) {
        $blobName = ($file.Path[0] -replace $backupUrl.baseUrl, '').TrimStart("/");
        SbsWriteDebug "Processing '$($file.Type)' backup deletion candidate '$($blobName)'";
        SbsWriteDebug "Backup from $($file.FirstLSN) to $($file.LastLSN)";
        if ($file.Type -eq $fullType) {

            # Any new full backup
            $newerBackup = $files | Where-Object {
                $_.Type -eq $fullType -and
                $_.FirstLsn -gt $file.FirstLsn
            }

            if ($null -eq $newerBackup) {
                SbsWriteDebug "No newer full backup found";
                continue;
            }

            # Check if there are any DIFF or LOG backups that depend on this full backup
            $dependentBackups = $files | Where-Object {
                (($_.Type -eq $diffType) -or ($_.Type -eq $logType)) -and
                $_.FirstLsn -eq $file.LastLsn
            }

            if ($dependentBackups.Count -gt 0) {
                SbsWriteDebug "The following backups depend on the full backup $($file.Path): $($dependentBackups.Path -join ', ')"
                continue;
            }
        } elseif ($file.Type -eq $diffType) {

            # Any new diff
            $newerBackup = $files | Where-Object {
                $_.Type -eq $diffType -and
                $_.FirstLsn -gt $file.LastLsn
            }

            if ($null -eq $newerBackup) {
                SbsWriteDebug "No newer diff backup found."
                continue
            }

            # Check if there are any LOG backups that depend on this diff backup
            $dependentBackups = $files | Where-Object {
                ($_.Type -eq $logType) -and
                $_.FirstLsn -eq $file.LastLsn
            }

            if ($dependentBackups.Count -gt 0) {
                SbsWriteDebug "The following backups dpend on the diff backup $($file.Path): $($dependentBackups.Path -join ', ')"
                continue;
            }
        } elseif ($file.Type -eq $logType) {
            # Only delete LOG if there is a newer full or diff
            $newerBackup = $files | Where-Object {
                (($_.Type -eq $diffType) -or ($_.Type -eq $fullType)) -and
                ($_.FirstLsn -gt $file.LastLsn)
            }

            if ($newerBackup.Count -eq 0) {
                SbsWriteDebug "No newer full or diff backup found."
                continue;
            }
        }

        # Perform cleanup for the file
        if ($WhatIf) {
            SbsWriteDebug "Would delete blob $($file.Path)"
        } else {
            # Full uri is not supported, we need the blob name
            SbsWriteHost "Deleting backup blob '$($blobName)'"
            Remove-AzStorageBlob -Container $backupUrl.container -Context $ctx -Blob $blobName;
        }
    }

    # This is what we have for each $file object
    # $historyObject = New-Object Dataplat.Dbatools.Database.BackupHistory
    # $historyObject.ComputerName = $group.Group[0].MachineName
    # $historyObject.InstanceName = $group.Group[0].ServiceName
    # $historyObject.SqlInstance = $group.Group[0].ServerName
    # $historyObject.Database = $group.Group[0].DatabaseName
    # $historyObject.UserName = $group.Group[0].UserName
    # $historyObject.Start = [DateTime]$group.Group[0].BackupStartDate
    # $historyObject.End = [DateTime]$group.Group[0].BackupFinishDate
    # $historyObject.Duration = ([DateTime]$group.Group[0].BackupFinishDate - [DateTime]$group.Group[0].BackupStartDate)
    # $historyObject.Path = [string[]]$group.Group.BackupPath
    # $historyObject.FileList = ($group.Group.FileList | Select-Object Type, LogicalName, PhysicalName, @{
    #         Name       = "Size"
    #         Expression = { [dbasize]$PSItem.Size }
    #     } -Unique)
    # $historyObject.TotalSize = $group.Group[0].BackupSize.Byte
    # $HistoryObject.CompressedBackupSize = $group.Group[0].CompressedBackupSize.Byte
    #  $historyObject.Type = $description
    # $historyObject.BackupSetId = $group.group[0].BackupSetGUID
    # $historyObject.DeviceType = 'Disk'
    # $historyObject.FullName = $group.Group.BackupPath
    # $historyObject.Position = $group.Group[0].Position
    # $historyObject.FirstLsn = $group.Group[0].FirstLSN
    # $historyObject.DatabaseBackupLsn = $dbLsn
    # $historyObject.CheckpointLSN = $group.Group[0].CheckpointLSN
    # $historyObject.LastLsn = $group.Group[0].LastLsn
    # $historyObject.SoftwareVersionMajor = $group.Group[0].SoftwareVersionMajor
    # $historyObject.RecoveryModel = $group.Group.RecoveryModel
}