function SbsMssqlAddLogin {
    param (
        [Parameter(Mandatory = $false)]
        [object]$instance,
        [Parameter(Mandatory = $false)]
        [string]$LoginConfiguration
    )

    # Parse the login configuration
    $parsedLoginConfiguration = $LoginConfiguration | ConvertFrom-Json -ErrorAction Stop;

    if ($null -eq $parsedLoginConfiguration) {
        SbsWriteError "Unable to parse login configuration.";
        return;
    }

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
    
    $loginName =  $parsedLoginConfiguration.Login;
    $password = $parsedLoginConfiguration.Password;
    $defaultDatabase = $parsedLoginConfiguration.DefaultDatabase;
    $databasesRegex = $parsedLoginConfiguration.DatabasesRegex;
    $permissions = ($parsedLoginConfiguration.Permissions -split ",") | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $allowedPermissions -contains $_ }
    $roles = ($parsedLoginConfiguration.Roles -split ",") | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $allowedRoles -contains $_ }

    if ([string]::IsNullOrWhiteSpace($loginName)) {
        SbsWriteError "Empty loginName";
        return;
    }

    if ([string]::IsNullOrWhiteSpace($password)) {
        SbsWriteError "Empty password";
        return;
    }

    SbsWriteDebug "Setting up MSSQL server login '$($loginName)'";

    # https://github.com/dataplat/dbatools/issues/9364
    Set-DbatoolsConfig -FullName commands.connect-dbainstance.smo.computername.source -Value 'instance.ComputerName'
    if ($instance -is [string]) {
        $instance = Connect-DbaInstance $instance;
    }

    # Check if the login exists
    $loginExists = Get-DbaLogin -SqlInstance $instance -Login $loginName;

    if (-not $loginExists) {
        # Create the login if it does not exist
        SbsWriteDebug "Creating $loginName login.";
        New-DbaLogin -SqlInstance $instance -Login $loginName -SecurePassword (ConvertTo-SecureString $password -AsPlainText -Force) -DefaultDatabase $defaultDatabase;
        SbsWriteHost "Created $loginName login.";
    }
    else {
        SbsWriteDebug "Updating login $loginName"
        Set-DbaLogin -SqlInstance $instance -Login $loginName -SecurePassword (ConvertTo-SecureString $password -AsPlainText -Force) -GrantLogin:$true -DefaultDatabase $defaultDatabase;
        SbsWriteDebug "Updated login $loginName"
    }

    if ($permissions) {
        $permissionsLiteral = $permissions -Join ", "
        SbsWriteDebug "Granting $($permissionsLiteral) to $loginName";
        Invoke-DbaQuery -SqlInstance $instance -Query "GRANT $permissionsLiteral TO [$(SbsMssqlEscapeIdentifier -identifier $loginName)]"
    }

    $databases = Get-DbaDatabase -SqlInstance $instance -ExcludeSystem | Where-Object { 
        ($_.Status -ne 'Restoring') -and ($_.Status -ne 'Offline') -and ($_.Name -match $databasesRegex)
    } | Select-Object -ExpandProperty Name;

    foreach ($db in $databases) {
        SbsWriteDebug "Preparing login for database $db"
        Repair-DbaDbOrphanUser -SqlInstance $instance -Database $db -User $loginName -Confirm:$false;
        $user = Get-DbaDbUser -SqlInstance $instance -Database $db -User $loginName;
        if (-not $user) {
            SbsWriteDebug "Creating database user $loginName for '$($db)'"
            New-DbaDbUser -SqlInstance $instance -Database $db -Login $loginName -User $loginName -EnableException;
        }
        else {
            SbsWriteDebug "User $loginName already exists in database $db.";
        }

        $addDbaRolesArguments = @{
            SqlInstance     = $instance
            Role            = $roles
            Member          = $loginName
            EnableException = $true
            Database        = $db
            Confirm         = $false
        }

        SbsWriteHost "Adding roles '$($roles -Join ", ")' to '$($loginName)' in '$($db)'"
        Add-DbaDbRoleMember @addDbaRolesArguments;

        # Now remove roles
        $rolesToDelete = Get-DbaDbRoleMember -SqlInstance $instance -Database $db -ExcludeRole $roles | Where-Object { 
            $_.Login -eq $loginName
        } | Select-object -ExpandProperty "Role" | Where-Object { 
            -not($roles -contains $_.Role) 
        };

        if ($rolesToDelete) {
            SbsWriteWarning "Removing roles '$($rolesToDelete -Join ", ")' to '$($loginName)' in '$($db)'"
            Remove-DbaDbRoleMember -SqlInstance $instance -Database $db -User $loginName -Role $rolesToDelete -Confirm:$false;
        }
    }
}
