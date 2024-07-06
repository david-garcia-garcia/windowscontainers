function SbsMssqlIndexOptimize {

    param(
        [Object]
        $sqlInstance = $null
    )

    $backupType = $backupType.ToUpper();
	
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
		
    SbsWriteHost "Starting '$($backupType)' IndexOptimize for '$($instanceFriendlyName)'"

    $systemDatabases = Get-DbaDatabase -SqlInstance $sqlInstance -ExcludeUser;

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
            SbsWriteHost "Starting IndexOptimize";
            $parameters2 = @{}
            $parameters2["@Databases"] = $db.Name;
            $parameters2["@FragmentationLevel1"] = 30;
            $parameters2["@FragmentationLevel2"] = 50;
            $parameters2["@FragmentationLow"] = $null;
            $parameters2["@FragmentationMedium"] = 'INDEX_REORGANIZE';
            $parameters2["@FragmentationHigh"] = 'INDEX_REBUILD_ONLINE,INDEX_REBUILD_OFFLINE';
            $parameters2["@MinNumberOfPages"] = 1000;
            $parameters2["@TimeLimit"] = 600;
            $parameters2["@LogToTable"] = 'Y';
            Invoke-DbaQuery -SqlInstance $sqlInstance -QueryTimeout 1200 -Database "master" -Query "IndexOptimize" -SqlParameter $parameters2 -CommandType StoredProcedure -EnableException;
            SbsWriteHost "Finished IndexOptimize";
			
        } 
        Catch {
            $exceptions += $_.Exception
            SbsWriteWarning "Error performing $($backupType) backup for the database $($db) and instance $($instanceFriendlyName): $($_.Exception.Message)"
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
    SbsWriteHost "$($backupType) Index optimized finished in $($Minutes) min";
}