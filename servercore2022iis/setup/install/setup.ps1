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
	'IIS-CertProvider',
	'IIS-HttpCompressionDynamic',
	'IIS-HttpCompressionStatic',
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
Write-Host " Configuring IIS log directory and disabling logging"
Write-Host "-----------------------------------------`n"

# Create IIS log directory
New-Item -Path "C:\var\log\iis" -ItemType Directory -Force | Out-Null
Write-Host "Created C:\var\log\iis directory"

# Configure default log directory (even though logging is disabled, this sets the path if someone enables it later)
Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter 'system.applicationHost/sites/siteDefaults/logFile' -Name 'directory' -Value 'C:\var\log\iis'
Write-Host "Set default IIS log directory to C:\var\log\iis"

# Disable logging at the server level (for all future sites)
Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter 'system.applicationHost/sites/siteDefaults/logFile' -Name 'enabled' -Value 'False'
Write-Host "Server-level logging disabled"

# Disable logging for all existing sites
Import-Module WebAdministration
Get-Website | ForEach-Object {
    Set-ItemProperty "IIS:\Sites\$($_.Name)" -Name logFile.enabled -Value $false
    Write-Host "Logging disabled for site: $($_.Name)"
}

Write-Host "`n---------------------------------------"
Write-Host " choco upgrade urlrewrite"
Write-Host "-----------------------------------------`n"

choco upgrade urlrewrite -y --version=2.1.20190828 --no-progress;
if ($LASTEXITCODE -ne 0) {
    throw "URL Rewrite installation failed with exit code $LASTEXITCODE"
}

Write-Host "`n---------------------------------------"
Write-Host " choco upgrade iis-arr"
Write-Host "-----------------------------------------`n"

choco upgrade iis-arr -y --version=3.0.20210521 --no-progress;
if ($LASTEXITCODE -ne 0) {
    throw "IIS Application Request Routing installation failed with exit code $LASTEXITCODE"
}

Get-ChildItem -Path $env:TEMP, 'C:\Windows\Temp' -Recurse | Remove-Item -Force -Recurse;