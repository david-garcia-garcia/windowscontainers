$envVar = [System.Environment]::GetEnvironmentVariable("NEW_RELIC_LICENSE_KEY");

if (![string]::IsNullOrEmpty($envVar)) {
    $configPath = "C:\ProgramData\New Relic\.NET Agent\newrelic.config";
    if (Test-Path $configPath) {
        [xml]$config = Get-Content $configPath;
        $config.configuration.SetAttribute("agentEnabled", "true");
        $config.configuration.service.SetAttribute("licenseKey", $envVar);
        $config.Save($configPath);
        Write-Host "New Relic agent has been enabled.";
    }
    else {
        Write-Host "Config file not found at $configPath";
    }
}
else {
    Write-Host "NEW_RELIC_LICENSE_KEY environment variable is not set or empty.";
}
