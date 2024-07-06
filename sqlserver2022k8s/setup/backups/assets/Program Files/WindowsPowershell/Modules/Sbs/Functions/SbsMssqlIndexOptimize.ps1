function SbsMssqlIndexOptimize {

    param(
        [Object]
        $sqlInstance = $null
    )

    $MSSQL_OPTIMIZE_TIMELIMIT = SbsGetEnvInt -Name "MSSQL_OPTIMIZE_TIMELIMIT" -DefaultValue 600;
    $MSSQL_OPTIMIZE_MINNUMBEROFPAGES = SbsGetEnvInt -Name "MSSQL_OPTIMIZE_MINNUMBEROFPAGES" -DefaultValue 1000;
    $MSSQL_OPTIMIZE_FRAGMENTATIONLEVEL1 = SbsGetEnvInt -Name "MSSQL_OPTIMIZE_FRAGMENTATIONLEVEL1" -DefaultValue 30;
    $MSSQL_OPTIMIZE_FRAGMENTATIONLEVEL2 = SbsGetEnvInt -Name "MSSQL_OPTIMIZE_FRAGMENTATIONLEVEL2" -DefaultValue 50;

    # Workaround for https://github.com/dataplat/dbatools/issues/9335
    # Import-Module Az.Accounts, Az.Storage
    Import-Module dbatools;

    Set-DbatoolsConfig -FullName logging.errorlogenabled -Value $false
    Set-DbatoolsConfig -FullName logging.errorlogfileenabled -Value $false
    Set-DbatoolsConfig -FullName logging.messagelogenabled -Value $false
    Set-DbatoolsConfig -FullName logging.messagelogfileenabled -Value $false

    Set-DbatoolsConfig -FullName sql.connection.trustcert -Value $true -Register
    Set-DbatoolsConfig -FullName sql.connection.encrypt -Value $false -Register 

    if (($null -eq $sqlInstance) -or ($sqlInstance -eq "")) {
        # "Server=$instance;Database=master;Integrated Security=True;TrustServerCertificate=True;"
        $sqlInstance = Connect-DbaInstance "localhost";
        SbsWriteDebug "Defaulting to LOCALHOST as database.";
    }

    $serverName = Invoke-DbaQuery -SqlInstance $sqlInstance -Query "SELECT @@SERVERNAME AS name" -EnableException;

    if ($null -eq $serverName) {
        SbsWriteError "Could not obtain @@SERVERNAME. Verify the connection to the database.";
        return;
    }

    SbsWriteDebug "Server name: $($serverName['name'])";

    $StopWatch = new-object system.diagnostics.stopwatch
    $StopWatch.Start();
		
    SbsWriteHost "Starting IndexOptimize for '$($serverName)'"

    # Recorremos todas las bases de datos
    # Check for null and determine count
    $dbs = Get-DbaDatabase -SqlInstance $sqlInstance -Status @('Normal') -ExcludeSystem:$true;

    if (-not [String]::IsNullOrWhitespace($Env:MSSQL_DATABASE)) {
        $dbs = $dbs | Where-Object { $_.Name -eq $Env:MSSQL_DATABASE };
        if ($dbs.Count -eq 0) {
            SbsWriteHost "Database $($Env:MSSQL_DATABASE) not found in instance: $($instanceFriendlyName)";
            return;
        }
    }

    # Check for null and determine count
    $dbCount = 0;

    if ($null -ne $dbs) {
        $dbCount = $dbs.Count;
    }
    else {
        SbsWriteWarning "Could not obtain databases to IndexOptimize in instance: $($instanceFriendlyName)";
        return;
    }

    # Write to the event log
    SbsWriteHost "Found $dbCount databases for IndexOptimize";

    $exceptions = @();

    foreach ($db in $dbs) {

        Try {
            SbsWriteHost "Starting IndexOptimize for $($db)";
            $parameters2 = @{}
            $parameters2["@Databases"] = $db.Name;
            $parameters2["@FragmentationLevel1"] = $MSSQL_OPTIMIZE_FRAGMENTATIONLEVEL1;
            $parameters2["@FragmentationLevel2"] = $MSSQL_OPTIMIZE_FRAGMENTATIONLEVEL2;
            $parameters2["@FragmentationLow"] = $null;
            $parameters2["@FragmentationMedium"] = 'INDEX_REORGANIZE';
            $parameters2["@FragmentationHigh"] = 'INDEX_REBUILD_ONLINE,INDEX_REBUILD_OFFLINE';
            $parameters2["@MinNumberOfPages"] = $MSSQL_OPTIMIZE_MINNUMBEROFPAGES;
            $parameters2["@TimeLimit"] = $MSSQL_OPTIMIZE_TIMELIMIT;
            $parameters2["@LogToTable"] = 'Y';
            Invoke-DbaQuery -SqlInstance $sqlInstance -QueryTimeout ($MSSQL_OPTIMIZE_TIMELIMIT + 120) -Database "master" -Query "IndexOptimize" -SqlParameter $parameters2 -CommandType StoredProcedure -EnableException;
            SbsWriteHost "Finished IndexOptimize for $($db)";
			
        } 
        Catch {
            $exceptions += $_.Exception
            SbsWriteWarning "Error performing IndexOptimize for the database $($db) and instance $($serverName): $($_.Exception.Message)"
            SbsWriteWarning "Exception Stack Trace: $($_.Exception.StackTrace)"
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