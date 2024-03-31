Import-Module dbatools;

$maxMemory = SbsGetEnvInt -name "MSSQL_MAXMEMORY" -defaultValue $null;

if (($null -ne $maxMemory)) {
    if ($maxMemory -lt 320) {
        SbsWriteHost "MSSQL_MAXMEMORY is less than 320MB. Will not apply configuration to prevent SQL Server from crashing."
    }
    $sqlInstance = "localhost";
    $sqlServer = Connect-DbaInstance -SqlInstance $sqlInstance;
    $currentMaxMemory = (Get-DbaMaxMemory -SqlInstance $sqlServer).MaxValue;
    if ($currentMaxMemory -ne $maxMemory) {
        SbsWriteHost "Setting max memory to $($maxMemory)Mb";
        Set-DbaMaxMemory -SqlInstance $sqlInstance -Max $maxMemory;
    }
}