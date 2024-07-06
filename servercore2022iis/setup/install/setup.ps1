$global:ErrorActionPreference = 'Stop'

Write-Host "`n---------------------------------------"
Write-Host " Enabling IIS common components for application hosting"
Write-Host "-----------------------------------------`n"

Import-Module ServerManager;

# Componentes generales
$features = @(
    'IIS-WebServerRole'
	'IIS-HttpRedirect',
	'NetFx4Extended-ASPNET45',
	'IIS-NetFxExtensibility45',
	'IIS-HealthAndDiagnostics',
	'IIS-RequestFiltering',
	'IIS-HttpCompressionDynamic',
	'IIS-HttpCompressionStatic',
	'IIS-ApplicationInit',
	'IIS-LoggingLibraries',
	'IIS-RequestMonitor',
	'IIS-HttpTracing',
	'IIS-ASPNET45',
	'IIS-StaticContent',
	'IIS-CGI'
);

Foreach ($featureName in $features) {
	if (((Get-WindowsOptionalFeature -Online -FeatureName $featureName).length -eq 0) -Or (Get-WindowsOptionalFeature -Online -FeatureName $featureName).State -eq "Disabled") {
		Write-Host "Enabling feature: $featureName";
		Enable-WindowsOptionalFeature -All -Online -FeatureName $featureName;
	}
	else {
		Write-Host "Feature already installed: $featureName";
	}
}

Write-Host "`n---------------------------------------"
Write-Host " Installing IIS URL rewrite"
Write-Host "-----------------------------------------`n"

choco upgrade urlrewrite -y --version=2.1.20190828 --no-progress;

Get-ChildItem -Path $env:TEMP, 'C:\Windows\Temp' -Recurse | Remove-Item -Force -Recurse;