$global:ErrorActionPreference = if ($null -ne $Env:SBS_ENTRYPOINTERRORACTION ) { $Env:SBS_ENTRYPOINTERRORACTION } else { 'Stop' }

# Read the environment variable
$timezone = [Environment]::GetEnvironmentVariable("SBS_CONTAINERTIMEZONE")

# Check if the timezone value was retrieved
if (-not [string]::IsNullOrWhiteSpace($timezone)) {
    # Set the timezone
    Set-TimeZone -Id $timezone;
    Write-Host "Timezone set to $timezone from SBS_CONTAINERTIMEZONE";
} else {
    $timeZone = Get-TimeZone;
    Write-Host "System Timezone: ${$timeZone.Id}";
}
