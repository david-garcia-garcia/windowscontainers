$NEW_RELIC_LICENSE_KEY = [System.Environment]::GetEnvironmentVariable("NEW_RELIC_LICENSE_KEY");

# We need to use these templates to overcome the configmap can only be readonly in K8S :/
$configTemplatePath = "C:\ProgramData\New Relic\.NET Agent\newrelic.config.template\newrelic.config";
$configPath = "C:\ProgramData\New Relic\.NET Agent\newrelic.config";

if (Test-Path $configTemplatePath) {
    Copy-Item -Path $configTemplatePath -Destination $configPath -Force
    if (![string]::IsNullOrEmpty($NEW_RELIC_LICENSE_KEY)) {
        [xml]$config = Get-Content $configPath;
        $config.configuration.SetAttribute("agentEnabled", "true");
        $config.configuration.service.SetAttribute("licenseKey", $NEW_RELIC_LICENSE_KEY);
        $config.Save($configPath);
        SbsWriteHost "New Relic agent has been enabled through NEW_RELIC_LICENSE_KEY environment.";
    }
    else {
        SbsWriteHost "NEW_RELIC_LICENSE_KEY environment variable is not set or empty, APM might not be enabled.";
    }
}
else {
    SbsWriteHost "Missing template $configTemplatePath"
}