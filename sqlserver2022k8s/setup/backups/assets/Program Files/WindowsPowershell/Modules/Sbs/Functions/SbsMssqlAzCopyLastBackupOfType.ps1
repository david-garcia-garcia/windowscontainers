function SbsMssqlAzCopyLastBackupOfType {

	param(
        # The SQL instance
        [Parameter(Mandatory = $true)]
        [object] $SqlInstance,
        # The database name
        [Parameter(Mandatory = $true)]
        [string]$Database,
        # The source BlobSAS, we need because
        # credentials are not stored neither retrievable
        # from sql server
        [Parameter(Mandatory = $true)]
        [string]$OriginalBackupUrl,
        # Backup type to copy to remote location, or
        # EMPTY to use the most recent backup type
		[ValidateSet('FULL', 'DIFF', 'LOG')]
		[string]$BackupType
	)

	Import-Module dbatools;

	Set-DbatoolsConfig -FullName sql.connection.trustcert -Value $true -Register
	Set-DbatoolsConfig -FullName sql.connection.encrypt -Value $false -Register

	# To support LTR on immutable storage
	$azCopyUrlDiff = SbsGetEnvString -Name "MSSQL_BACKUP_AZCOPY_DIFF" -DefaultValue $null;
	$azCopyUrlFull = SbsGetEnvString -Name "MSSQL_BACKUP_AZCOPY_FULL" -DefaultValue $null;
	$azCopyUrlLog = SbsGetEnvString -Name "MSSQL_BACKUP_AZCOPY_LOG" -DefaultValue $null;

    $backupHistory = Get-DbaDbBackupHistory -SqlInstance $SqlInstance -Database $Database -Last -Force;
    if ($BackupType) {
        $backupHistory = $backupHistory | Where-Object { $.Type -eq  $BackupType};
    }

    $lastBackup = $backupHistory | Sort-Object -Property FirstLsn -Descending | Select-Object -First 1;

    if ($null -eq $lastBackup) {
        SbsWriteHost "Could not find any backups to AZCOPY";
        return;
    }

    SbsWriteHost "Last backup type is $($lastBackup.Type)";
    SbsWriteHost "Last backup url is $($lastBackup.Path)";

    $azCopyUrl = $null;

    switch ($lastBackup.Type) {
        "Full" {
            $azCopyUrl = $azCopyUrlFull;
        }
        "Diff" {
            $azCopyUrl = $azCopyUrlDiff;
        }
        "Log" {
            $azCopyUrl = $azCopyUrlLog;
        }
    }

    $destinationUrl = SbsParseSasUrl -Url $azCopyUrl;

    if ($null -eq $destinationUrl) {
        SbsWriteHost "No LTR url provided for backups of type $($lastBackup.Type)";
        return;
    }

    $sourceUrl = SbsParseSasUrl -Url $OriginalBackupUrl;
    $backupUrl = SbsParseSasUrl -Url $lastBackup.Path[0]; #This one does not have the token!

    # We need to ensure that backup URL is contained in the source URL
    if (-not $backupUrl.baseUrlWithPrefix.StartsWith($sourceUrl.baseUrlWithPrefix)) {
        SbsWriteWarning "Backup URL $($backupUrl.baseUrlWithPrefix) is not a subpath of the provided sourceURL $($sourceUrl.baseUrlWithPrefix)";
    }

    $backupSubPath = $backupUrl.baseUrlWithPrefix.Replace($sourceUrl.baseUrlWithPrefix, "");
    SbsWriteHost "Backup partial path $backupSubPath";

    if ($azCopyUrl) {

        $finalSource = $backupUrl.baseUrlWithPrefix + $sourceUrl.query;
        $finalDestination = $destinationUrl.baseUrlWithPrefix + $backupSubPath + $destinationUrl.query;

        $azCopyCommand = "azcopy copy `"$finalSource`" `"$finalDestination`" --overwrite=false"
        Invoke-Expression $azCopyCommand
    }
}