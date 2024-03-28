$global:ErrorActionPreference = if ($null -ne $Env:SBS_ENTRYPOINTERRORACTION ) { $Env:SBS_ENTRYPOINTERRORACTION } else { 'Stop' }

$SBS_SRVENSURE = [System.Environment]::GetEnvironmentVariable("SBS_SRVENSURE");

if (-not [string]::IsNullOrWhiteSpace($SBS_SRVENSURE)) {
    $services = ($SBS_SRVENSURE).Split(';');
    foreach ($service in $services) {
        SbsWriteHost "Starting Service $($service)";
        Set-Service -Name $service -StartupType Automatic;
        Start-Service -Name $service;
    }
}
