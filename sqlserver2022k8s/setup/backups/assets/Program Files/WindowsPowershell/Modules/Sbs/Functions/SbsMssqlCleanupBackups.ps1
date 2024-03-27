# La función de cleanup backups de Hallengren no funcion
# con el parámetro -CleanupTime cuando trabajamos con blobs
# de Azure. Por lo tanto, se ha creado esta función para suplir
# la carencia.
function SbsMssqlCleanupBackups {
    param(
        [Parameter(Mandatory = $true)]
        [object]$SqlInstance,
        [Parameter(Mandatory = $true)]
        [string]$Url,
        [ValidateSet('FULL', 'DIFF', 'LOG')]
        [string] $Type,
        [string] $DatabaseName,
        [int] $CleanupTime,
        [bool] $WhatIf
    )

    $backupUrl = SbsParseSasUrl -Url $Url;
    if ($null -eq $backupUrl) {
        SbsWriteWarning "Invalid backup URL $($Url)";
    }

    # Make sure the credential is updated
    SbsEnsureCredentialForSasUrl -SqlInstance $SqlInstance -Url $Url;

    $ctx = New-AzStorageContext -StorageAccountName $backupUrl.storageAccountName -SasToken $backupUrl.sasToken;
    $blobs = Get-AzStorageBlob -Container $backupUrl.container -Context $ctx -Prefix $backupUrl.prefix |
    Where-Object { ($_.AccessTier -ne 'Archive') -and ($_.Length -gt 0) };
    $blobUrls = $blobs | ForEach-Object { $backupUrl.baseUrl + "/" + $_.Name }
    
    # Define the cache directory path
    $cacheDirectory = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "MSSQLHEADERS\$($backupUrl.storageAccountName)\$($backupUrl.container)";
    New-Item -ItemType Directory -Path $cacheDirectory -Force | Out-Null

    # Delete the json files that are older than 1 hour
    Get-ChildItem -Path $cacheDirectory -Filter "*.json" | Where-Object { $_.CreationTime -lt (Get-Date).AddHours(-12) } | Remove-Item -Force;

    # Loop through the $blobUrls and check if the metadata is already present in the cache
    $cachedFiles = @{}
    foreach ($blobUrl in $blobUrls) {
        $blobName = ($blobUrl -replace $backupUrl.baseUrl, '').TrimStart('/');
        $cacheFilePath = (Join-Path -Path $cacheDirectory -ChildPath ($blobName -replace '[/:]', '_')) + ".json"
        if (Test-Path -Path $cacheFilePath) {
            $cachedFile = Get-Content -Path $cacheFilePath | ConvertFrom-Json
            $cachedFiles[$blobUrl] = $cachedFile
        }
    }

    # Get the files that are not present in the cache
    $filesToFetch = $blobUrls | Where-Object { -not $cachedFiles.ContainsKey($_) }

    # Fetch the missing files using Get-DbaBackupInformation
    if ($filesToFetch.Count -gt 0) {
        Write-Host "Fetching backup metadata for $($filesToFetch.Count) files"
        $files = Get-DbaBackupInformation -SqlInstance $SqlInstance -Path $filesToFetch;
        foreach ($file in $files) {
            $blobName = ($file.Path[0] -replace $backupUrl.baseUrl, '').TrimStart('/');
            $cacheFilePath = (Join-Path -Path $cacheDirectory -ChildPath ($blobName -replace '[/:]', '_')) + ".json"
            $file | ConvertTo-Json -Depth 100 | Set-Content -Path $cacheFilePath
            $cachedFiles[$blobUrl] = Get-Content -Path $cacheFilePath | ConvertFrom-Json
        }
    }

    $files = $cachedFiles.Values | Where-Object { $_.Database -eq $databaseName }

    if ($files.Count -eq 0) {
        Write-Host "No backups found for database $databaseName"
        return;
    }

    $fullType = "Database";
    $diffType = "Database Differential";
    $logType = "Transaction Log";

    $filterType = $null;

    switch ($Type) {
        'FULL' {
            $filterType = $fullType;
        }
        'DIFF' {
            $filterType = $diffType;
        }
        'LOG' {
            $filterType = $logType;
        }
    }

    # Get candidates for deletion
    $filteredFiles = $files | Where-Object {
        $_.Type -eq $filterType -and
        $_.Start -lt (Get-Date).AddHours(-$CleanupTime)
    } | Sort-Object -Property Start;

    # Loop through the sorted files
    foreach ($file in $filteredFiles) {
        if ($file.Type -eq $fullType) {

            # Any new full backup
            $newerBackup = $files | Where-Object {
                $_.Type -eq $fullType -and
                $_.Start -gt $file.Start
            }

            if ($null -eq $newerBackup) {
                Write-Host "No newer full backup found for $($file.Path)"
                continue
            }

            # Check if there are any DIFF or LOG backups that depend on this full backup
            $dependentBackups = $files | Where-Object {
                (($_.Type -eq $diffType) -or ($_.Type -eq $logType)) -and
                $_.LastLSN -eq $file.FirstLSN
            }

            if ($dependentBackups.Count -gt 0) {
                Write-Host "The following backups depend on the full backup $($file.Path): $($dependentBackups.Path -join ', ')"
                continue;
            }
        }
        elseif ($file.Type -eq $diffType) {

            # Any new diff
            $newerBackup = $files | Where-Object {
                $_.Type -eq $diffType -and
                $_.Start -gt $file.Start
            }

            if ($null -eq $newerBackup) {
                Write-Host "No newer full backup found for $($file.Path)"
                continue
            }

            # Check if there are any LOG backups that depend on this diff backup
            $dependentBackups = $files | Where-Object {
                ($_.Type -eq $logType) -and
                $_.FirstLSN -eq $file.LastLSN
            }

            if ($dependentBackups.Count -gt 0) {
                Write-Host "The following backups dpend on the full backup $($file.Path): $($dependentBackups.Path -join ', ')"
                continue;
            }
        }
        elseif ($file.Type -eq $logType) {
            # Only delete LOG if there is a newer full or diff
            $newerBackup = $files | Where-Object {
                (($_.Type -eq $diffType) -or ($_.Type -eq $fullType)) -and
                ($_.Start -gt $file.Start)
            }

            if ($newerBackup.Count -eq 0) {
                Write-Host "No newer full or diff backup found for $($file.Path)"
                continue
            }
        }

        # Perform cleanup for the file
        if ($WhatIf) {
            Write-Host "Would delete blob $($file.Path)"
        }
        else {
            # Full uri is not supported, we need the blob name
            $blobName = ($file.Path[0] -replace $backupUrl.baseUrl, '').TrimStart("/");
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