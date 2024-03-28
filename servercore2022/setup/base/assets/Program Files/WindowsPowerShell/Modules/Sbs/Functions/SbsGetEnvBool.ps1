function SbsGetEnvBool {
    [OutputType([bool])]
    param (
        [string]$name
    )

    $envValue = [System.Environment]::GetEnvironmentVariable($name)
    if ([string]::IsNullOrWhiteSpace($envValue)) {
        return $false;
    }
    else {
        return ($envValue -match "^(true|1|yes)$");
    }
}