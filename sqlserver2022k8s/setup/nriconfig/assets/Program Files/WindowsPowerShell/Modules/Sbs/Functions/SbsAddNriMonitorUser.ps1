function SbsAddNriMonitorUser {
    param (
        [Parameter(Mandatory = $true)]
        [string]$instanceName,
        [string]$User,
        [string]$Password
    )

    # https://github.com/dataplat/dbatools/issues/9364
    Set-DbatoolsConfig -FullName commands.connect-dbainstance.smo.computername.source -Value 'instance.ComputerName'
    $instance = Connect-DbaInstance $instanceName;

    # These login name and password are shared among all instances
    $loginName = $User;

    $password = $Password;

    # Check if the login exists
    $loginExists = Get-DbaLogin -SqlInstance $instance -Login $loginName;

    if (-not $loginExists) {
        # Create the login if it does not exist
        New-DbaLogin -SqlInstance $instance -Login $loginName -SecurePassword (ConvertTo-SecureString $password -AsPlainText -Force);
        SbsWriteHost "Created $loginName login.";
    }
    else {
        Set-DbaLogin -SqlInstance $instance -Login $loginName -SecurePassword (ConvertTo-SecureString $password -AsPlainText -Force);
        SbsWriteDebug "Login $loginName already exists."
    }

    Invoke-DbaQuery -SqlInstance $instance -Query "GRANT CONNECT SQL, VIEW SERVER STATE, VIEW ANY DEFINITION TO [$loginName]";

    $databases = Get-DbaDatabase -SqlInstance $instance | Where-Object { -not $_.IsSystemObject -and $_.Status -ne 'Restoring' -and $_.Status -ne 'Offline' } | Select-Object -ExpandProperty Name;

    foreach ($db in $databases) {
        $user = Get-DbaDbUser -SqlInstance $instance -Database $db -User $loginName;
        if ($user) {
            Remove-DbaDbOrphanUser -SqlInstance $instance -Database $db -User $user;
        }
        $user = Get-DbaDbUser -SqlInstance $instance -Database $db -User $loginName;
        if (-not $user) {
            New-DbaDbUser -SqlInstance $instance -Database $db -Login $loginName -User $loginName;
        }
        else {
            SbsWriteDebug "User $loginName already exists in database $db.";
        }
    }

    # Add login to model database
    Invoke-DbaQuery -SqlInstance $instance -Query "USE [model]; IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = '$loginName') BEGIN CREATE USER [$loginName] FOR LOGIN [$loginName] END"
	
    # Add login to master database
    Invoke-DbaQuery -SqlInstance $instance -Query "USE [master]; IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = '$loginName') BEGIN CREATE USER [$loginName] FOR LOGIN [$loginName] END"
	
    # Grant db_datareader in master
    Invoke-DbaQuery -SqlInstance $instance -Query "USE [master]; EXEC sp_addrolemember 'db_datareader', '$loginName'"
}
