function SbsGetEnvString {
    param (
        [string]$name,
        [string]$defaultValue
    )

    $envValue = [System.Environment]::GetEnvironmentVariable($name)
    if ([string]::IsNullOrWhiteSpace($envValue)) {
        return $defaultValue
    } else {
        return $envValue
    }
}