# We want to set MAXMEMORY after all the startup scripts have run, so
# that startup (and eventually restore) is not memory constrained.
$maxMemory = SbsGetEnvInt -name "MSSQL_MAXMEMORY" -defaultValue $null;
if (($null -ne $maxMemory)) {
    if ($maxMemory -gt 280) {
        SbsWriteHost "Setting max memory to $($maxMemory)Mb";
        Set-DbaMaxMemory -SqlInstance $sqlInstance -Max $maxMemory;
    }
    else {
        SbsWriteHost "Max memory is less than 280MB, not setting."
    }
}