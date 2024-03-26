# La función de cleanup backups de Hallengren no funcion
# con el parámetro -CleanupTime cuando trabajamos con blobs
# de Azure. Por lo tanto, se ha creado esta función para suplir
# la carencia.
function SbsCleanupBackups {
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

    $ctx = New-AzStorageContext -StorageAccountName $backupUrl.storageAccountName -SasToken $backupUrl.sasToken;
    $blobs = Get-AzStorageBlob -Container $backupUrl.container -Context $ctx -Prefix $backupUrl.prefix |
    Where-Object { ($_.AccessTier -ne 'Archive') -and ($_.Length -gt 0) };
    $blobUrls = $blobs | ForEach-Object { $backupUrl.baseUrl + $_.Name } 
    $files = Get-DbaBackupInformation -SqlInstance $SqlInstance -Path $blobUrls | Where-Object { $_.Database -eq $databaseName };

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
                ($_.Type -eq $diffType -or $_.Type -eq $logType) -and
                $_.FirstLSN -eq $file.LastLSN
            }

            if ($dependentBackups.Count -gt 0) {
                Write-Host "The following backups dpend on the full backup $($file.Path): $($dependentBackups.Path -join ', ')"
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

            if ($newerBackup.Count -eq 0){
                Write-Host "No newer full or diff backup found for $($file.Path)"
                continue
            }
        }

        # Perform cleanup for the file
        if ($WhatIf) {
            Write-Host "Would delete $($file.Path)"
        }
        else {
            Write-Host "Deleting $($file.Path)"
            Remove-AzStorageBlob -Container $backupUrl.container -Context $ctx -Blob $file.Path;
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
    #  $historyObject.SoftwareVersionMajor = $group.Group[0].SoftwareVersionMajor
    #  $historyObject.RecoveryModel = $group.Group.RecoveryModel
}