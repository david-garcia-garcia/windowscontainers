$MSSQL_AGENT_ENABLED = SbsGetEnvBool "MSSQL_AGENT_ENABLED"

if ($MSSQL_AGENT_ENABLED) {
    Set-Service -name "SQLSERVERAGENT" -StartupType Manual;
    Start-Service "SQLSERVERAGENT"
}
else {
    SbsStopServiceWithTimeout -ServiceName "SQLSERVERAGENT"
    Set-Service -name "SQLSERVERAGENT" -StartupType Disabled;
}