$global:ErrorActionPreference = 'Stop'

Start-Service 'MSSQLSERVER';
Set-DbatoolsConfig -FullName sql.connection.trustcert -Value $true -Register;
$sqlInstance = Connect-DbaInstance -SqlInstance localhost;

#################################
# Admin groups
#################################

New-DbaLogin -SqlInstance $sqlInstance -Login 'BUILTIN\Administrators' -Force -EnableException
Add-DbaServerRoleMember -SqlInstance $sqlInstance -ServerRole sysadmin -Login 'BUILTIN\Administrators' -EnableException -Confirm:$false

#################################
# Basic MSSQL configuration
#################################

# Enable mixed mode authentication
Set-ItemProperty -Path "HKLM:\Software\Microsoft\Microsoft SQL Server\MSSQLServer\" -Name "LoginMode" -Value 2;

# Enable TCP IP

Set-DbaNetworkConfiguration -SqlInstance $sqlInstance -EnableProtocol TcpIp -Confirm:$false;

# Server defaults
Set-DbaSpConfigure -SqlInstance $sqlInstance -Name 'backup compression default' -Value 1;
Set-DbaMaxDop -SqlInstance $sqlInstance -MaxDop 1;
Set-DbaMaxMemory -SqlInstance $sqlInstance -Max 512;

#################################
# Disable uneeded services
#################################

# This service has to do with the Always Encrypted with Enclaves feature. I have sent a note to the team to get this more explicitly documented for customers. Some scenarios will break if that service is not enabled.
# Stop-Service AzureAttestService;
# Set-Service AzureAttestService -StartupType Disabled;

# This has to do with VM snapshots, it freezes MSSQL during
# a VM snapshot. But inside a container... this probably
# does not even work.
Stop-Service SQLWriter;
Set-Service SQLWriter -StartupType Disabled;

# If agent is needed, then enable it in the dockerfile config
Stop-Service SQLSERVERAGENT;
Set-Service SQLSERVERAGENT -StartupType Disabled;

# Whatever
Stop-Service SQLTELEMETRY;
Set-Service SQLTELEMETRY -StartupType Disabled;

# Uneeded
Stop-Service SQLBrowser;
Set-Service SQLBrowser -StartupType Disabled;

#################################
# Disable telemetry
# https://stackoverflow.com/questions/43548794/how-to-turn-off-telemetry-for-sql-2016
#################################

Get-Service | 
Where-Object { $_.Name -like '*telemetry*' -or $_.DisplayName -like '*CEIP*' } | 
ForEach-Object { 
    $servicename = $_.Name; 
    $displayname = $_.DisplayName; 
    Set-Service -Name $servicename  -StartupType Disabled 
    $serviceinfo = Get-Service -Name $servicename 
    $startup = $serviceinfo.StartType
    Write-Host "$servicename : $startup : $displayname";  
}

Set-Location "HKLM:\"
$sqlentries = @( "\Software\Microsoft\Microsoft SQL Server\", "\Software\Wow6432Node\Microsoft\Microsoft SQL Server\" ) 
Get-ChildItem -Path $sqlentries -Recurse |
ForEach-Object {
    $keypath = $_.Name
        (Get-ItemProperty -Path $keypath).PSObject.Properties |
    Where-Object { $_.Name -eq "CustomerFeedback" -or $_.Name -eq "EnableErrorReporting" } |
    ForEach-Object {
        $itemporpertyname = $_.Name
        $olditemporpertyvalue = Get-ItemPropertyValue -Path $keypath -Name $itemporpertyname
        Set-ItemProperty  -Path $keypath -Name $itemporpertyname -Value 0
        $newitemporpertyvalue = Get-ItemPropertyValue -Path $keypath -Name $itemporpertyname
        Write-Host "$keypath.$itemporpertyname = $olditemporpertyvalue --> $newitemporpertyvalue" 
    }
}

# Clean temp data
Get-ChildItem -Path $env:TEMP, 'C:\Windows\Temp' -Recurse | Remove-Item -Force -Recurse;
Remove-Item -Path "$env:TEMP\*" -Recurse -Force;