# Function to check and create or update the credential
function SbsMssqlPrepareRestoreFiles {
    [OutputType([array])]
    param (
        [Parameter(Mandatory = $true)]
        [string]$SqlInstance,
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$DatabaseName
    )

    # Path could either be a SAS URL, a regular URL o a local/network path
    $backupUrl = SbsParseSasUrl -Url $Path;

    $files = @();

    if ($null -ne $backupUrl) {
        SbsWriteHost "Checking for backups in $($backupUrl.baseUrlWithPrefix)";
        $ctx = New-AzStorageContext -StorageAccountName $backupUrl.storageAccountName -SasToken $backupUrl.sasToken;
        $blobs = Get-AzStorageBlob -Container $backupUrl.container -Context $ctx -Prefix $backupUrl.prefix |
        Where-Object { ($_.AccessTier -ne 'Archive') -and ($_.Length -gt 0) };
        if ($blobs -and $blobs.Count -gt 0) {
            $blobUrls = $blobs | ForEach-Object { $backupUrl.baseUrl + "/" + $_.Name } 
            $files = Get-DbaBackupInformation -SqlInstance $SqlInstance -Path $blobUrls | Where-Object { $_.Database -eq $DatabaseName };
        }
    }
    else {
        SbsWriteHost "Checking for backups in $($Path)";
        $files = Get-DbaBackupInformation -SqlInstance $SqlInstance -Path $Path | Where-Object { $_.Database -eq $DatabaseName };
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

    return $files;
}