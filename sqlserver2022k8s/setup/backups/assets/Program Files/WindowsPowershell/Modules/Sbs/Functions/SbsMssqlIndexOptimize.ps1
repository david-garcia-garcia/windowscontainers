function SbsMssqlIndexOptimize {

    param(
        [Object]
        $sqlInstance = $null
    )

    $MSSQL_OPTIMIZE_TIMELIMIT = SbsGetEnvInt -Name "MSSQL_OPTIMIZE_TIMELIMIT" -DefaultValue 600;
    $MSSQL_OPTIMIZE_MINNUMBEROFPAGES = SbsGetEnvInt -Name "MSSQL_OPTIMIZE_MINNUMBEROFPAGES" -DefaultValue 1000;
    $MSSQL_OPTIMIZE_FRAGMENTATIONLEVEL1 = SbsGetEnvInt -Name "MSSQL_OPTIMIZE_FRAGMENTATIONLEVEL1" -DefaultValue 30;
    $MSSQL_OPTIMIZE_FRAGMENTATIONLEVEL2 = SbsGetEnvInt -Name "MSSQL_OPTIMIZE_FRAGMENTATIONLEVEL2" -DefaultValue 50;

	if (($null -eq $sqlInstance) -or ($sqlInstance -eq "")) {
		# "Server=$instance;Database=master;Integrated Security=True;TrustServerCertificate=True;"
		$sqlInstance = SbsEnsureConnectionString -SqlInstanceOrConnectionString "localhost";
		SbsWriteDebug "Defaulting to LOCALHOST as database.";
	}

    $connectionString = SbsEnsureConnectionString -SqlInstanceOrConnectionString $sqlInstance;

	# Get server name
	$r = (SbsMssqlRunQuery -Instance $connectionString -CommandText "SELECT @@SERVERNAME AS name");
	$serverName = $r.name
	if ($null -eq $serverName) {
		SbsWriteError "SbsMssqlIndexOptimize: Could not obtain @@SERVERNAME. Verify the connection to the database.";
		return;
	}

    SbsWriteDebug "Server name: $($serverName['name'])";

    $StopWatch = new-object system.diagnostics.stopwatch
    $StopWatch.Start();
		
    SbsWriteHost "Starting IndexOptimize for '$($serverName)'"

    # Recorremos todas las bases de datos
    # Check for null and determine count
	$databases = SbsMssqlRunQuery -Instance $connectionString -CommandText "SELECT name FROM sys.databases WHERE state_desc = 'ONLINE'"

	if (-not [String]::IsNullOrWhitespace($Env:MSSQL_DB_NAME)) {
		$databases = $databases | Where-Object { $_.name -eq $Env:MSSQL_DB_NAME };
		if ($databases.Count -eq 0) {
			SbsWriteHost "Database $($Env:MSSQL_DB_NAME) not found in instance $($serverName)";
			return;
		}
	}

	# Check for null and determine count
	$dbCount = 0;

	if ($null -ne $databases) {
		$dbCount = $databases.Count;
	}
	else {
		SbsWriteWarning "SbsMssqlIndexOptimize: Could not obtain databases to backup in instance: $($serverName)";
		return;
	}

    # Write to the event log
    SbsWriteHost "Found $dbCount databases for IndexOptimize";

    $exceptions = @();

    foreach ($db in $databases) {

        Try {
            SbsWriteHost "Starting IndexOptimize for $($db.Name)";
            $parameters = @{}
            $parameters["@Databases"] = $db.Name;
            $parameters["@FragmentationLevel1"] = $MSSQL_OPTIMIZE_FRAGMENTATIONLEVEL1;
            $parameters["@FragmentationLevel2"] = $MSSQL_OPTIMIZE_FRAGMENTATIONLEVEL2;
            $parameters["@FragmentationLow"] = $null;
            $parameters["@FragmentationMedium"] = 'INDEX_REORGANIZE';
            $parameters["@FragmentationHigh"] = 'INDEX_REBUILD_ONLINE,INDEX_REBUILD_OFFLINE';
            $parameters["@MinNumberOfPages"] = $MSSQL_OPTIMIZE_MINNUMBEROFPAGES;
            $parameters["@TimeLimit"] = $MSSQL_OPTIMIZE_TIMELIMIT;
            $parameters["@LogToTable"] = 'Y';
            SbsWriteHost "Calling IndexOptimize for $($db.Name)";
            SbsMssqlRunQuery -Instance $connectionString -CommandType "StoredProcedure" -CommandText "dbo.IndexOptimize" -CommandTimeout ($MSSQL_OPTIMIZE_TIMELIMIT + 120) -Parameters $parameters;
            SbsWriteHost "Finished IndexOptimize for $($db.Name)";
			
        } 
        Catch {
            $exceptions += $_.Exception
            SbsWriteWarning "SbsMssqlIndexOptimize: error performing IndexOptimize for the database $($db.Name) and instance $($serverName): $($_.Exception.Message)"
            SbsWriteWarning "SbsMssqlIndexOptimize: exception Stack Trace: $($_.Exception.StackTrace)"
        }
    }
	
    if ($exceptions.Count -gt 1) {
        throw (New-Object System.AggregateException -ArgumentList $exceptions)
    }
    elseif ($exceptions.Count -gt 0) {
        throw $exceptions[0];
    }

    $StopWatch.Stop()
    $Minutes = $StopWatch.Elapsed.TotalMinutes;
    SbsWriteHost "IndexOptimize finished in $($Minutes) min";
}