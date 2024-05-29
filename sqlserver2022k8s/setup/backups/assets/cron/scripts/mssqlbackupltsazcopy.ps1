Import-Module Sbs;
Import-Module Az.Accounts, Az.Storage
Import-Module dbatools;

if ([string]::IsNullOrEmpty($Env:MSSQL_PATH_BACKUPURL)) {
    SbsWriteDebug "MSSQLCLEANBACKUPS: MSSQL_PATH_BACKUPURL environment is empty.";
    return;
}

$sqlInstance = Connect-DbaInstance "localhost";

$backupUrl = SbsParseSasUrl -Url $Env:MSSQL_PATH_BACKUPURL;

if ($null -ne $backupUrl) {
    SbsWriteDebug "MSSQLCLEANBACKUPS: Loading environment MSSQL_PATH_BACKUPURL";
    SbsEnsureCredentialForSasUrl -SqlInstance $sqlInstance -Url $backupUrl.url;
}
else {
    SbsWriteWarning "MSSQLCLEANBACKUPS: MSSQL_PATH_BACKUPURL could not be parsed";
    return;
}

$userDatabases = Get-DbaDatabase -SqlInstance $sqlInstance -ExcludeSystem

foreach ($database in $userDatabases) {
    SbsMssqlAzCopyLastBackupOfType -SqlInstance $sqlInstance -Database $database.Name -OriginalBackupUrl $backupUrl -BackupType "Full";
}
