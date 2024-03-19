function SbsGetEnvInt {
    param (
        [string]$name,
        [int]$defaultValue
    )

    $envValue = [System.Environment]::GetEnvironmentVariable($name);
    [int]$result = $null;
    if ([string]::IsNullOrWhiteSpace($envValue)) {
        return $defaultValue;
    } elseif ([int]::TryParse($envValue, [ref]$result)) {
        return $result;
    } else {
        SbsWriteHost "The environment variable value for '$name' is not a valid number. Using default value: $defaultValue";
        return $defaultValue;
    }
}
