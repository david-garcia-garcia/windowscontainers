Start-Service 'MSSQLSERVER';
Set-DbatoolsConfig -FullName sql.connection.trustcert -Value $true -Register;
$sqlInstance = Connect-DbaInstance -SqlInstance localhost;
Set-DbaNetworkConfiguration -SqlInstance $sqlInstance -EnableProtocol TcpIp -Confirm:$false;
Set-ItemProperty -Path "HKLM:\Software\Microsoft\Microsoft SQL Server\MSSQLServer\" -Name "LoginMode" -Value 2;

# Install https://ola.hallengren.com/
Write-Host "Install https://ola.hallengren.com/";
Install-DbaMaintenanceSolution -SqlInstance $sqlInstance -CleanupTime 72 -LogToTable -InstallJobs;