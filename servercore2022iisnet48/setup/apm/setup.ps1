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

# https://github.com/DataDog/dd-trace-dotnet/issues/343
# https://github.com/DataDog/dd-trace-dotnet/blob/12926d187c16467d5c60e36d28b9c3fa6398c28a/deploy/Datadog.Trace.ClrProfiler.WindowsInstaller/Product.wxs#L148-L150

# Set COR_ENABLE_PROFILING=0 explicitly at system level to ensure it's disabled globally
[System.Environment]::SetEnvironmentVariable("COR_ENABLE_PROFILING", "0", "Machine")
Write-Host "Set COR_ENABLE_PROFILING=0 at system level"

# Enable COR_ENABLE_PROFILING only for W3SVC (IIS) and WAS services
# Service environment variables are stored in the registry
$services = @("W3SVC", "WAS")
foreach ($serviceName in $services) {
    $serviceEnvPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$serviceName\Environment"
    if (-not (Test-Path $serviceEnvPath)) {
        New-Item -Path $serviceEnvPath -Force | Out-Null
        Write-Host "Created $serviceName Environment registry key"
    }
    
    Set-ItemProperty -Path $serviceEnvPath -Name "COR_ENABLE_PROFILING" -Value "1" -Type String
    Write-Host "Set COR_ENABLE_PROFILING=1 for $serviceName service"
}

Write-Host "`n---------------------------------------"
Write-Host " Default to strong crypto for .NET Framework"
Write-Host "-----------------------------------------`n"

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

