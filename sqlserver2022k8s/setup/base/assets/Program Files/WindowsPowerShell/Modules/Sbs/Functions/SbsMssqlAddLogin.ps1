function SbsMssqlAddLogin {
    param (
        [Parameter(Mandatory = $false)]
        [string]$instanceName,
        [Parameter(Mandatory = $false)]
        [string]$LoginConfiguration
    )

    # Parse the login configuration
    $parsedLoginConfiguration = $LoginConfiguration | ConvertFrom-Yaml -ErrorAction Stop;

    # Let's be safe on what an application can do
    $allowedPermissions = @(
        "CONNECT SQL",
        "VIEW SERVER STATE",
        "VIEW ANY DEFINITION",
        "VIEW ANY DATABASE",
        "VIEW ANY STATISTICS",
        "VIEW DATABASE STATE"
    )

    $allowedRoles = @(
        "db_datareader",
        "db_accesadmin",
        "db_datawriter",
        "db_ddladmin",
        "db_owner",
        "db_securityadmin"
    )

    # Prepare all the parameters from the configuration object
    SbsWriteDebug "Parsing login configuration object"
    
    $loginName = $parsedLoginConfiguration["Login"];
    $password = $parsedLoginConfiguration["Password"];
    $defaultDatabase = $parsedLoginConfiguration["DefaultDatabase"];
    $databasesRegex = $parsedLoginConfiguration["DatabasesRegex"];
    $permissions = ($parsedLoginConfiguration["Permissions"] -split ",") | Where-Object { $allowedPermissions -contains $_.Trim() }
    $roles = ($parsedLoginConfiguration["Roles"] -split ",") | Where-Object { $allowedRoles -contains $_ }

    SbsWriteDebug "Setting up MSSQL server user $($loginName)";

    # https://github.com/dataplat/dbatools/issues/9364
    Set-DbatoolsConfig -FullName commands.connect-dbainstance.smo.computername.source -Value 'instance.ComputerName'
    $instance = Connect-DbaInstance $instanceName;

    # Check if the login exists
    $loginExists = Get-DbaLogin -SqlInstance $instance -Login $loginName;

    if (-not $loginExists) {
        # Create the login if it does not exist
        New-DbaLogin -SqlInstance $instance -Login $loginName -SecurePassword (ConvertTo-SecureString $password -AsPlainText -Force) -DefaultDatabase $defaultDatabase;
        SbsWriteHost "Created $loginName login.";
    }
    else {
        Set-DbaLogin -SqlInstance $instance -Login $loginName -SecurePassword (ConvertTo-SecureString $password -AsPlainText -Force) -GrantLogin:$true -DefaultDatabase $defaultDatabase;
        SbsWriteDebug "Login $loginName already exists."
    }

    if ($permissions) {
        $permissionsLiteral = $permissions -Join ", "
        Invoke-DbaQuery -SqlInstance $instance -Query "GRANT $permissionsLiteral TO [$(SbsMssqlEscapeIdentifier -identifier $loginName )]"
    }

    $databases = Get-DbaDatabase -SqlInstance $instance -ExcludeSystem | Where-Object { 
        $_.Status -ne 'Restoring' -and $_.Status -ne 'Offline' -and $_.Name -match $databasesRegex
    } | Select-Object -ExpandProperty Name;

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

        foreach ($role in $roles) {
            Add-DbaServerRoleMember -SqlInstance $instance -ServerRole $role -Login $loginName;
        }
    }
}
