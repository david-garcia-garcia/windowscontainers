Import-Module Sbs;
$reduceTo = SbsGetEnvInt -Name "MSSQL_BACKUP_RELEASEMEMORY" -DefaultValue $null;
SbsMssqlResetMemory -reduceTo $reduceTo;