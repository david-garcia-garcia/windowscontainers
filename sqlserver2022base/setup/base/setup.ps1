# Enable mixed mode authentication
Set-ItemProperty -Path "HKLM:\Software\Microsoft\Microsoft SQL Server\MSSQLServer\" -Name "LoginMode" -Value 2;

# Enable TCP IP
Start-Service 'MSSQLSERVER';
Set-DbatoolsConfig -FullName sql.connection.trustcert -Value $true -Register;
$sqlInstance = Connect-DbaInstance -SqlInstance localhost;
Set-DbaNetworkConfiguration -SqlInstance $sqlInstance -EnableProtocol TcpIp -Confirm:$false;

# Server defaults
Set-DbaSpConfigure -SqlInstance localhost -Name 'backup compression default' -Value 1;
Set-DbaMaxDop -SqlInstance $sqlInstance -MaxDop 1;

# Clean temp data
Get-ChildItem -Path $env:TEMP, 'C:\Windows\Temp' -Recurse | Remove-Item -Force -Recurse;
Remove-Item -Path "$env:TEMP\*" -Recurse -Force;

#################################
# Disable uneeded services
#################################

# This service has to do with the Always Encrypted with Enclaves feature. I have sent a note to the team to get this more explicitly documented for customers. Some scenarios will break if that service is not enabled.
Stop-Service AzureAttestService;
Set-Service AzureAttestService -StartupType Disabled;

# This has to do with snapshots, not even sure if this has any sense inside a container
Stop-Service SQLWriter;
Set-Service SQLWriter -StartupType Disabled;

# If agent is needed, then enable it in the dockerfile config
Stop-Service SQLSERVERAGENT;
Set-Service SQLSERVERAGENT -StartupType Disabled;

# Clean temp data
Get-ChildItem -Path $env:TEMP, 'C:\Windows\Temp' -Recurse | Remove-Item -Force -Recurse;
Remove-Item -Path "$env:TEMP\*" -Recurse -Force;