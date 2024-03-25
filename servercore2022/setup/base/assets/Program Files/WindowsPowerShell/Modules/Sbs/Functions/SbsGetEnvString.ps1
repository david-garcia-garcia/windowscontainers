function SbsGetEnvString {
    [OutputType([string])]
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