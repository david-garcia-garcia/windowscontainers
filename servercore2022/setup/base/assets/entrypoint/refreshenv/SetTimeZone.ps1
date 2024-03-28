$SBS_CONTAINERTIMEZONE = [Environment]::GetEnvironmentVariable("SBS_CONTAINERTIMEZONE")

# Check if the timezone value was retrieved
if (-not [string]::IsNullOrWhiteSpace($SBS_CONTAINERTIMEZONE)) {
    # Set the timezone
    Set-TimeZone -Id $SBS_CONTAINERTIMEZONE;
    SbsWriteHost "Timezone set to $SBS_CONTAINERTIMEZONE from SBS_CONTAINERTIMEZONE";
}

SbsWriteHost "Configured System Timezone: [$((Get-TimeZone).Id)] - $((Get-TimeZone).DisplayName)";