$global:ErrorActionPreference = if ($null -ne $Env:SBS_ENTRYPOINTERRORACTION ) { $Env:SBS_ENTRYPOINTERRORACTION } else { 'Stop' }

$NEW_RELIC_LICENSE_KEY = [System.Environment]::GetEnvironmentVariable("NEW_RELIC_LICENSE_KEY");

if (-not [string]::IsNullOrEmpty($NEW_RELIC_LICENSE_KEY)) {
    Import-Module powershell-yaml;
    $yamlFilePath = "C:\Program Files\New Relic\newrelic-infra\newrelic-infra.yml"
    $yamlContent = Get-Content -Path $yamlFilePath -Raw | ConvertFrom-Yaml;
    $yamlContent.license_key = $NEW_RELIC_LICENSE_KEY;
    $updatedYaml = $yamlContent | ConvertTo-Yaml;
    $updatedYaml | Set-Content -Path $yamlFilePath;
    SbsWriteHost "NEW_RELIC_LICENSE_KEY used to configure the new relic infrastructure service. The service is disabled by default. Use SBS_SRVENSURE to enable this service."
} else {
    SbsWriteHost "NEW_RELIC_LICENSE_KEY environment variable is not set or empty, infrastructrure agent not configured.";
}