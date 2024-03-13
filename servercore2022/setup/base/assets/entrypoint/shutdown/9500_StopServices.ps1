#######################################
# Stops services gracefully on shutdown using
# a ; separated list of service names defined
# in the SBS_SRVSTOP env
#######################################

$global:ErrorActionPreference = if ($null -ne $Env:SBS_ENTRYPOINTERRORACTION ) { $Env:SBS_ENTRYPOINTERRORACTION } else { 'Stop' }

$SBS_SRVSTOP = [System.Environment]::GetEnvironmentVariable("SBS_SRVSTOP");

if (-not [string]::IsNullOrWhiteSpace($SBS_SRVSTOP)) {
    $services = ($SBS_SRVSTOP).Split(';');
    foreach ($service in $services) {
        SbsStopServiceWithTimeout $service;
    }
}