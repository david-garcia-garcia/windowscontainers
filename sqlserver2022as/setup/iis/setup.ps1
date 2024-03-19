# Install IIS Web Server Role
Install-WindowsFeature -Name Web-Server
Install-WindowsFeature -Name Web-Windows-Auth, Web-Basic-Auth, Web-Url-Auth, Web-IP-Security
Install-WindowsFeature -Name Web-CGI, Web-ISAPI-Ext

# Install web management service, only for diagnosis and dormant.
Install-WindowsFeature  Web-Mgmt-Service;
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\WebManagement\Server" -Name "EnableRemoteManagement" -Value 1;
Set-Service -name WMSVC -StartupType Disabled;
Write-Host "IIS Remote Management enabled";

# Clean temp data
Get-ChildItem -Path $env:TEMP, 'C:\Windows\Temp' -Recurse | Remove-Item -Force -Recurse;
Remove-Item -Path "$env:TEMP\*" -Recurse -Force;