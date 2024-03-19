$global:ErrorActionPreference = if ($null -ne $Env:SBS_ENTRYPOINTERRORACTION ) { $Env:SBS_ENTRYPOINTERRORACTION } else { 'Stop' }

# Default to 20s
$timeout = SbsGetEnvInt -name "SBS_SHUTDOWNTIMEOUT" -defaultValue 20;

# Check if the timeout value was retrieved and is numeric
$timeoutMilliseconds = [int]$timeout * 1000;

reg add hklm\system\currentcontrolset\services\cexecsvc /v ProcessShutdownTimeoutSeconds /t REG_DWORD /d $timeout /f;
reg add hklm\system\currentcontrolset\control /v WaitToKillServiceTimeout /t REG_SZ /d $timeoutMilliseconds /f;

SbsWriteHost "Container shutdown timeout set to $($timeout)s";