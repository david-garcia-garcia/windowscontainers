#################################################
# Check container timeout. Only makes sense on docker
# where we will not be using lifecycle hooks
#################################################

$global:ErrorActionPreference = if ($null -ne $Env:SBS_ENTRYPOINTERRORACTION ) { $Env:SBS_ENTRYPOINTERRORACTION } else { 'Stop' }

# Check timeouts - in K8S use lifecycle hooks
if ($null -eq $Env:MSSQL_DISABLESHUTDOWNTIMEOUTCHECK) {
    $timeout = (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\cexecsvc").ProcessShutdownTimeoutSeconds;
    $minimium = 20;
    if (($Env:MSSQL_LIFECYCLE -eq "BACKUP") -or ($Env:MSSQL_AUTOBACKUP -eq "1")) {
        $minimium = 60;
    }
    if ($timeout -lt $minimium) {
        Write-Error "Current shutdown timeout of $($timeout)s is lower than the minimum of $($minimium)s for this workload. Use SBS_SHUTDOWNTIMEOUT to set a bigger timeout. If this is running in K8S, configure a LifeCycleHook for shutdown instead of increasing the timeout and set the MSSQL_DISABLESHUTDOWNTIMEOUTCHECK environment variable."
    }
}
