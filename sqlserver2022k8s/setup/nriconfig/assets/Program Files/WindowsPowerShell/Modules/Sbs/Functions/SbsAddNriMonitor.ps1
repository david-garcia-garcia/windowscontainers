function SbsAddNriMonitor {
    param (
        [Parameter(Mandatory = $true)]
        [string]$sqlInstance
    )

    $mypath = Split-Path $MyInvocation.MyCommand.Path;

    # These login name and password are shared among all instances
    $loginName = "newrelic";
    $password = SbsRandomPassword 30;

    Write-Host "`n---------------------------------------"
    Write-Host " Processing instance with connection string: [$ConnectionString]"
    Write-Host "-----------------------------------------`n"

    # ***************************************
    # CHECK THAT NAMED PIPES AND TCP IP ARE ENABLED IN THE SERVER
    # ***************************************

    $serverNameStart = $connectionString.IndexOf("Data Source=") + 12
    $serverNameEnd = $connectionString.IndexOf(";", $serverNameStart)
    $serverName = $connectionString.Substring($serverNameStart, $serverNameEnd - $serverNameStart)
	
    SbsWriteHost "Veryfing server enabled protocols [$serverName]"

    $sqlConnection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
    $sqlConnection.Open();
    $sqlCommand = New-Object System.Data.SqlClient.SqlCommand("SELECT registry_key, value_name, value_data FROM sys.dm_server_registry WHERE registry_key LIKE '%SuperSocketNetLib%'", $sqlConnection)
    $protocols = $sqlCommand.ExecuteReader()

    $namedPipesEnabled = $false
    $tcpIpEnabled = $false

    while ($protocols.Read()) {
        $registryKey = $protocols.GetValue(0)
        $valueName = $protocols.GetValue(1)
        $valueData = $protocols.GetValue(2)

        if ($valueName -eq "Enabled" -and $registryKey -like "*SuperSocketNetLib\Np") {
            $namedPipesEnabled = $valueData -eq "1"
        }
        elseif ($valueName -eq "Enabled" -and $registryKey -like "*SuperSocketNetLib\Tcp") {
            $tcpIpEnabled = $valueData -eq "1"
        }
    }

    if ($tcpIpEnabled -eq $false) {
        throw "TCP/IP NOT enabled on $serverName";
    }

    $sqlConnection.Close()

    SbsWriteHost " Creating monitoring user [newrelic] and giving permissions in [$serverName]"

    # Define variables
    $databaseList = "SELECT name FROM sys.databases WHERE name NOT IN ('master', 'msdb', 'tempdb', 'model', 'rdsadmin', 'distribution') AND state != 6"
    $grantStatement = "GRANT CONNECT SQL, VIEW SERVER STATE, VIEW ANY DEFINITION TO [$loginName]"

    # Parse connection string to extract server name, instance name, and port number
    $connectionBuilder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder($ConnectionString)
    $serverName = $connectionBuilder.DataSource
    $hostname = $serverName.Split(',')[0].TrimStart('tcp:/')
    if ($hostname.Contains('\')) {
        $hostname = $hostname.Split('\')[0]
    }

    # If the server name is a named instance, extract the instance name
    if ($serverName.Contains('\')) {
        $instanceName = $serverName.Split('\')[1]
    }
    else {
        $instanceName = $null
    }

    # If the server name contains a port number, extract the port number
    if ($serverName.Contains(',')) {
        $portNumber = $serverName.Split(',')[1].Split('=')[1]
    }
    else {
        $portNumber = $null
    }

    # Create SQL connection
    $sqlConn = New-Object System.Data.SqlClient.SqlConnection
    $sqlConn.ConnectionString = $ConnectionString

    # Open SQL connection
    $sqlConn.Open()

    # Upsert login with random password
    $sqlCmd = New-Object System.Data.SqlClient.SqlCommand
    $sqlCmd.Connection = $sqlConn
    $sqlCmd.CommandText = "IF NOT EXISTS (SELECT * FROM sys.server_principals WHERE name = '$loginName') BEGIN CREATE LOGIN [$loginName] WITH PASSWORD = '$password', CHECK_POLICY = OFF END ELSE BEGIN ALTER LOGIN [$loginName] WITH PASSWORD = '$password', CHECK_POLICY = OFF END"
    $sqlCmd.ExecuteNonQuery() | out-null

    # Grant permissions to login
    $sqlCmd.CommandText = $grantStatement
    $sqlCmd.ExecuteNonQuery() | out-null

    # Add login to existing databases
    $databaseCmd = New-Object System.Data.SqlClient.SqlCommand
    $databaseCmd.Connection = $sqlConn
    $databaseCmd.CommandText = $databaseList
    $databaseReader = $databaseCmd.ExecuteReader()

    # Execute the command and store the results in an array
    $databaseNames = @()
    while ($databaseReader.Read()) {
        $databaseNames += $databaseReader.GetString(0)
    }
    $databaseReader.Close()
    $databaseCmd.Dispose()

    # Iterate through the database names and execute the SQL commands
    foreach ($databaseName in $databaseNames) {
        SbsWriteHost "Processing login for database: $databaseName";
        $sqlCmd2 = New-Object System.Data.SqlClient.SqlCommand
        $sqlCmd2.Connection = $sqlConn
        $sqlCmd2.CommandText = "USE [$databaseName]; IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = '$loginName') BEGIN CREATE USER [$loginName] FOR LOGIN [$loginName] END;"
        $sqlCmd2.ExecuteNonQuery() | out-null;
        $sqlCmd2.Dispose() 
    }

    # Add login to model database
    $sqlCmd.CommandText = "USE [model]; IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = '$loginName') BEGIN CREATE USER [$loginName] FOR LOGIN [$loginName] END"
    $sqlCmd.ExecuteNonQuery() | out-null
	
    # Add login to master database
    $sqlCmd.CommandText = "USE [master]; IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = '$loginName') BEGIN CREATE USER [$loginName] FOR LOGIN [$loginName] END"
    $sqlCmd.ExecuteNonQuery() | out-null
	
    # Grant db_datareader in master
    $sqlCmd.CommandText = "USE [master]; EXEC sp_addrolemember 'db_datareader', '$loginName'"
    $sqlCmd.ExecuteNonQuery() | Out-Null
	
    # Close the connection
    $sqlConn.Close()
	
    # ***************************************
    # Add a table and information about backup status
    # ***************************************
    $template = Get-Content -Path "$mypath\mssql_nri_templates\mssql-config.yml" | ConvertFrom-Yaml

    # Create a new empty configuration object
    $newConfig = [ordered]@{
        integrations = [System.Collections.ArrayList]@()
    }

    # Loop through each connection string
    foreach ($ConnectionString in $ConnectionStrings) {

        $connectionBuilder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder($ConnectionString)
        $serverName = $connectionBuilder.DataSource
        $hostname = $serverName.Split(',')[0].TrimStart('tcp:/')
        if ($hostname.Contains('\')) {
            $hostname = $hostname.Split('\')[0]
        }

        # If the server name is a named instance, extract the instance name
        if ($serverName.Contains('\')) {
            $instanceName = $serverName.Split('\')[1]
        }
        else {
            $instanceName = $null
        }

        # If the server name contains a port number, extract the port number
        if ($serverName.Contains(',')) {
            $portNumber = $serverName.Split(',')[1].Split('=')[1]
        }
        else {
            $portNumber = $null
        }

        # Load the template YAML file for this connection string
        $config = $template | ConvertTo-Yaml | ConvertFrom-Yaml

        # Modify the "env" section with the new server information
        foreach ($integration in $config.integrations) {
            $integration.env.HOSTNAME = $hostname;
            $integration.env.USERNAME = "newrelic";
            $integration.env.PASSWORD = $password;
            $integration.env.PORT = $portNumber;
            $integration.env.INSTANCE = $instanceName;
            $integration.labels.environment = $Env;
        }

        # Add the modified integration section to the new configuration object
        foreach ($integration in $config.integrations) {
            $newConfig.integrations.Add($integration) | Out-Null
        }
    }

    # Save the modified YAML file with all integration sections
    $newConfig | ConvertTo-Yaml | Out-File "C:\Program Files\New Relic\newrelic-infra\integrations.d\mssql-config.yml";

    # Load the YAML file
    $config = Get-Content -Path "$mypath\mssql_nri_templates\mssql-config.yml" | ConvertFrom-Yaml

    $sqlQueryPath = "C:\Program Files\New Relic\newrelic-infra\mssqlquery";

    if (!(Test-Path $sqlQueryPath)) {
        New-Item -ItemType Directory -Force -Path $sqlQueryPath
    }

    Copy-Item "$mypath\mssql_nri_templates\mssql-custom-query.yml" "$sqlQueryPath\mssql-custom-query.yml" -Force;
    Copy-Item "$mypath\mssql_nri_templates\mssql-custom-query-daily.yml" "$sqlQueryPath\mssql-custom-query-daily.yml" -Force;
}
