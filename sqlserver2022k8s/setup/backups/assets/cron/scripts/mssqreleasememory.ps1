Import-Module Sbs;
$reduceTo = SbsGetEnvInt -Name "MSSQL_BACKUP_RELEASEMEMORY" -DefaultValue $null;

if ($null -ne $MSSQL_BACKUP_RELEASEMEMORY) {
    SbsMssqlResetMemory -reduceTo $reduceTo;
} else {
    SbsWriteDebug "MSSQL_BACKUP_RELEASEMEMORY not configured";
}