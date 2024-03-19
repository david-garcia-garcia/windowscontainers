$global:ErrorActionPreference = 'Stop'

Start-Service 'MSSQLSERVER';
Set-DbatoolsConfig -FullName sql.connection.trustcert -Value $true -Register;
$sqlInstance = Connect-DbaInstance -SqlInstance localhost;
Set-DbaNetworkConfiguration -SqlInstance $sqlInstance -EnableProtocol TcpIp -Confirm:$false;
Set-ItemProperty -Path "HKLM:\Software\Microsoft\Microsoft SQL Server\MSSQLServer\" -Name "LoginMode" -Value 2;

# Enable SQL Server Agent
Set-DbaSpConfigure -SqlInstance $sqlInstance -Name 'Agent XPs' -Value 1;