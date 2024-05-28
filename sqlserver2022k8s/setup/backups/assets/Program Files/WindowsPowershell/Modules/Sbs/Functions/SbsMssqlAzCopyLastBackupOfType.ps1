<#
.SYNOPSIS
This methods uses AZCOPY to copy blob-to-blob an existing backup, it can be used
to copy regular backups to an immutable blob storage.

.DESCRIPTION
Long description

.PARAMETER SqlInstance
The sql server instance

.PARAMETER Database
The database name

.PARAMETER OriginalBackupUrl
The original backup URL, that MUST include the SAS token

.PARAMETER BackupType
The backup type to look for, if not specified, it will attempt to copy
the last backup file (be it diff, log or full)

.EXAMPLE
An example

.NOTES
General notes
#>
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
        [string]$OriginalBackupUrl
	)

	Import-Module dbatools;

	Set-DbatoolsConfig -FullName sql.connection.trustcert -Value $true -Register
	Set-DbatoolsConfig -FullName sql.connection.encrypt -Value $false -Register

	# To support LTR on immutable storage
	$azCopyUrl = SbsGetEnvString -Name "MSSQL_BACKUP_AZCOPYLTS" -DefaultValue $null;

    $backupHistory = Get-DbaDbBackupHistory -SqlInstance $SqlInstance -Database $Database -Last -Force;

    # Only consider full and differential
    if ($BackupType) {
        $backupHistory = $backupHistory | Where-Object { ($_.Type -eq  "Full") -or ($_.Type -eq  "Differential")};
    }

    $lastBackup = $backupHistory | Sort-Object -Property FirstLsn -Descending | Select-Object -First 1;

    if ($null -eq $lastBackup) {
        SbsWriteHost "Could not find any backups to AZCOPY";
        return;
    }

    SbsWriteHost "Last backup type is $($lastBackup.Type)";
    SbsWriteHost "Last backup url is $($lastBackup.Path)";

    $destinationUrl = SbsParseSasUrl -Url $azCopyUrl;

    if ($null -eq $destinationUrl) {
        SbsWriteHost "No LTR url provided for backups.";
        return;
    }

    $sourceUrl = SbsParseSasUrl -Url $OriginalBackupUrl;
    $backupUrl = SbsParseSasUrl -Url $lastBackup.Path[0]; #This one does not have the token!

    # We need to ensure that backup URL is contained in the source URL
    if (-not $backupUrl.baseUrlWithPrefix.StartsWith($sourceUrl.baseUrlWithPrefix)) {
        SbsWriteError "Backup URL $($backupUrl.baseUrlWithPrefix) is not a subpath of the provided sourceURL $($sourceUrl.baseUrlWithPrefix)";
        return;
    }

    # We need to ensure that the LTS URL is not contained in the SOURCE URL, to avoid duplication of backups
    if ($destinationUrl.baseUrlWithPrefix.StartsWith($sourceUrl.baseUrlWithPrefix)) {
        SbsWriteError "LTS URL $($destinationUrl.baseUrlWithPrefix) should not be a subpatch of $($sourceUrl.baseUrlWithPrefix)";
        return;
    }

    $backupSubPath = $backupUrl.baseUrlWithPrefix.Replace($sourceUrl.baseUrlWithPrefix, "");
    SbsWriteHost "Backup partial path $backupSubPath";

    if ($azCopyUrl) {

        $finalSource = $backupUrl.baseUrlWithPrefix + $sourceUrl.query;
        $finalDestination = $destinationUrl.baseUrlWithPrefix + $backupSubPath + $destinationUrl.query;

        $finalSourceParsed = SbsParseSasUrl -Url $finalSource;
        $finalDestinationParsed = SbsParseSasUrl -Url $finalDestination;

        SbsWriteHost "LTS Copying $($finalSourceParsed.baseUrlWithPrefix) to $($finalDestinationParsed.baseUrlWithPrefix)"

        $azCopyCommand = "azcopy copy `"$finalSource`" `"$finalDestination`" --overwrite=false"
        Invoke-Expression $azCopyCommand
    }
}