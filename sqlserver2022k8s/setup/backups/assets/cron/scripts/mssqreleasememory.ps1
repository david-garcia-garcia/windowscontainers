Import-Module Sbs;
$MSSQL_RELEASEMEMORY = SbsGetEnvInt -Name "MSSQL_RELEASEMEMORY" -DefaultValue $null;

if ($null -ne $MSSQL_RELEASEMEMORY) {
    SbsMssqlResetMemory -reduceTo $MSSQL_RELEASEMEMORY;
} else {
    SbsWriteDebug "MSSQL_RELEASEMEMORY not configured";
}