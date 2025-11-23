$global:ErrorActionPreference = 'Stop';

Write-Host "`n---------------------------------------";
Write-Host " Installing .Net agent";
Write-Host "-----------------------------------------`n";

choco upgrade newrelic-dotnet -y --version=10.47.0 --no-progress;
if ($LASTEXITCODE -ne 0) {
    throw "NewRelic .NET agent installation failed with exit code $LASTEXITCODE"
}

Write-Host "`n---------------------------------------"
Write-Host " Configuring COR_ENABLE_PROFILING for IIS only"
Write-Host "-----------------------------------------`n"

# Disable COR_ENABLE_PROFILING at system level (the installer sets it globally)
# Remove it from system environment variables
[System.Environment]::SetEnvironmentVariable("COR_ENABLE_PROFILING", $null, "Machine")
Write-Host "Removed COR_ENABLE_PROFILING from system environment"

# Set COR_ENABLE_PROFILING=0 explicitly at system level to ensure it's disabled globally
[System.Environment]::SetEnvironmentVariable("COR_ENABLE_PROFILING", "0", "Machine")
Write-Host "Set COR_ENABLE_PROFILING=0 at system level"

# Enable COR_ENABLE_PROFILING only for W3SVC (IIS) service
# Service environment variables are stored in the registry
$w3svcEnvPath = "HKLM:\SYSTEM\CurrentControlSet\Services\W3SVC\Environment"
if (-not (Test-Path $w3svcEnvPath)) {
    New-Item -Path $w3svcEnvPath -Force | Out-Null
    Write-Host "Created W3SVC Environment registry key"
}

Set-ItemProperty -Path $w3svcEnvPath -Name "COR_ENABLE_PROFILING" -Value "1" -Type String
Write-Host "Set COR_ENABLE_PROFILING=1 for W3SVC service only"

# https://docs.newrelic.com/docs/apm/agents/net-agent/troubleshooting/no-data-appears-after-disabling-tls-10/#strongcrypto
# Esto hace falta para que el framework utilice por defecto TLS en lugar de SSL
Set-ItemProperty -Path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\.NETFramework\v4.0.30319" -Name "SchUseStrongCrypto" -Value 1 -Type DWord;
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\.NETFramework\v4.0.30319" -Name "SchUseStrongCrypto" -Value 1 -Type DWord;

Write-Host "`n---------------------------------------"
Write-Host " Deploying DeleteOldApmLogs Scheduled Task"
Write-Host "-----------------------------------------`n"

Register-ScheduledTask -Xml (Get-Content "c:\setup\cron\DeleteOldApmLogs.xml" -Raw) -TaskName "DeleteOldApmLogs";

# Clean temp data
Get-ChildItem -Path $env:TEMP, 'C:\Windows\Temp' -Recurse | Remove-Item -Force -Recurse;
Remove-Item -Path "$env:TEMP\*" -Recurse -Force;

