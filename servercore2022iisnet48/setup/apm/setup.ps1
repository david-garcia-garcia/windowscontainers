$global:ErrorActionPreference = 'Stop';

Write-Host "`n---------------------------------------";
Write-Host " Installing .Net agent";
Write-Host "-----------------------------------------`n";

choco upgrade newrelic-dotnet -y --version=10.20.2 --no-progress;

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

