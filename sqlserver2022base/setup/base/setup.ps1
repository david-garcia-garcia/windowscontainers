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