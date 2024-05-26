function SbsMssqlRunBackups {

	param(
		# FULL = FULL backup
		# DIFF = DIFF backup, will be promoted to FULL according to MSSQL_BACKUP_CHANGEBACKUPTYPE+MSSQL_BACKUP_MODIFICATIONLEVEL
		# LOG = LOG backup, only taken if MSSQL_BACKUP_LOGSIZESINCELASTBACKUP/MSSQL_BACKUP_TIMESINCELASTLOGBACKUP
		# LOGNOW = Run a log backup immediately
		[Parameter(Mandatory = $true)]
		[ValidateSet('FULL', 'DIFF', 'LOG', 'SYSTEM', 'LOGNOW')]
		[string]$backupType,

		# The database instance, default to localhost
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

	$certificateBackupDirectory = $Env:MSSQL_PATH_BACKUP;
	$databaseBackupDirectory = $Env:MSSQL_PATH_BACKUP;
	$backupCertificate = $Env:MSSQL_BACKUP_CERT;

	# Default to 10min or 100Mb whatever comes first
	$logSizeSinceLastLogBackup = SbsGetEnvInt -Name "MSSQL_BACKUP_LOGSIZESINCELASTBACKUP" -DefaultValue 100;
	$timeSinceLastLogBackup = SbsGetEnvInt -Name "MSSQL_BACKUP_TIMESINCELASTLOGBACKUP" -DefaultValue 600;

	$modificationLevel = SbsGetEnvInt -Name "MSSQL_BACKUP_MODIFICATIONLEVEL" -DefaultValue 30;
	$changeBackupType = SbsGetEnvString -Name "MSSQL_BACKUP_CHANGEBACKUPTYPE" -DefaultValue "Y";

	# Mirroring DOES not work with IMMUTABLE STORAGE, so it is not good for Long Term Retention
	$mirrorUrlDiff = SbsGetEnvString -Name "MSSQL_PATH_BACKUPMIRRORURL_DIFF" -DefaultValue $null;
	$mirrorUrlFull = SbsGetEnvString -Name "MSSQL_PATH_BACKUPMIRRORURL_FULL" -DefaultValue $null;
	$mirrorUrlLog = SbsGetEnvString -Name "MSSQL_PATH_BACKUPMIRRORURL_LOG" -DefaultValue $null;

	$mirrorUrl = $null;

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

	$backupUrl = SbsParseSasUrl -Url $Env:MSSQL_PATH_BACKUPURL;
	if ($null -ne $backupUrl) {
		SbsWriteDebug "Loading environment MSSQL_PATH_BACKUPURL";
		SbsEnsureCredentialForSasUrl -SqlInstance $sqlInstance -Url $backupUrl.url;
	}

	$StopWatch = new-object system.diagnostics.stopwatch
	$StopWatch.Start();
		
	SbsWriteHost "Starting '$($backupType)' backup generation for '$($instanceFriendlyName)'"
	$systemDatabases = Get-DbaDatabase -SqlInstance $sqlInstance -ExcludeUser;

	# Recorremos todas las bases de datos
	# Check for null and determine count
	$excludeUser = $backupType -eq "SYSTEM";
	$excludeSystem = $backupType -ne "SYSTEM";
	$dbs = Get-DbaDatabase -SqlInstance $sqlInstance -Status @('Normal') -ExcludeUser:$excludeUser -ExcludeSystem:$excludeSystem ;

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
		SbsWriteWarning "Could not obtain databases to backup in instance: $($instanceFriendlyName)";
		return;
	}

	# Write to the event log
	SbsWriteHost "Found $dbCount databases for backup";

	$exceptions = @();

	foreach ($db in $dbs) {

		Try {
					
			$isSystemDb = $systemDatabases.Name -contains $db.Name;

			if (($backupType -ne "SYSTEM") -and ($isSystemDb -eq $true)) {
				continue;
			}

			$recoveryModel = (Get-DbaDbRecoveryModel -SqlInstance $sqlInstance -Database $db.Name).RecoveryModel;

			SbsWriteHost "Backup '$db' isSystemDatabase '$($isSystemDb)' with recovery model '$($recoveryModel)'";

			# Certificate rotates every year
			$certificate = $null;

			# Do not encrypt backups for system databases
			if (($isSystemDb -eq $false) -and ($backupCertificate -eq "AUTO")) {
				$certificate = "$($db.Name)_$((Get-Date).year)";
				if (($null -eq (Get-DbaDbCertificate -SqlInstance $sqlInstance -Certificate $certificate))) {
					SbsMssqlEnsureCert -Name $certificate -BackupLocation $certificateBackupDirectory;
				}
			}
			
			$solutionBackupType = $backupType;

			if ($backupType -eq "SYSTEM") {
				$solutionBackupType = "FULL";
			}
				
			# LOGNOW is used to FORCE a backup prior to container teardown. Not sure if hallengren solution
			# will make a diff if a LOG is requested when recovery mode is simple.
			if ($backupType -eq "LOGNOW") {
				switch ($recoveryModel) {
					"FULL" {  
						$solutionBackupType = "LOG";
					}
					Default {
						$solutionBackupType = "DIFF";
					}
				}
			}

			Write-Host "Backing up database $($db.Name) with recovery model $($recoveryModel) with solutionBackupType $($solutionBackupType)"

			switch ($solutionBackupType) {
				"FULL" {
					$cleanupTime = SbsGetEnvInt -Name "MSSQL_BACKUP_CLEANUPTIME_FULL" -DefaultValue 0;
					$mirrorUrl = SbsParseSasUrl -Url $mirrorUrlFull;
				}
				"DIFF" {
					$cleanupTime = SbsGetEnvInt -Name "MSSQL_BACKUP_CLEANUPTIME_DIFF" -DefaultValue 0;
					$mirrorUrl = SbsParseSasUrl -Url $mirrorUrlDiff;
				}
				"LOG" {
					$cleanupTime = SbsGetEnvInt -Name "MSSQL_BACKUP_CLEANUPTIME_LOG" -DefaultValue 0;
					$mirrorUrl = SbsParseSasUrl -Url $mirrorUrlLog;
				}
			}

			SbsWriteDebug "Solution Cleanup Time: $($cleanupTime)H";

			if ($null -ne $mirrorUrl) {
				SbsWriteDebug "Using mirror URL $($mirrorUrl.baseUrlWithPrefix)"
				SbsEnsureCredentialForSasUrl -SqlInstance $sqlInstance -Url $mirrorUrl.url;
			}

			if ($solutionBackupType -eq "LOG" -and ($recoveryModel -eq "SIMPLE")) {
				SbsWriteWarning "LOG backup requested for database $($db.Name) with SIMPLE recovery model.";
				continue;
			}

			# Because of the volatile nature of this setup, ServerName and InstanceName make no sense
			# we could have an APP name?
			# $directoryStructure = "{ServerName}{$InstanceName}{DirectorySeparator}{DatabaseName}{DirectorySeparator}{BackupType}_{Partial}_{CopyOnly}";
			# $directoryStructure = "{DatabaseName}{DirectorySeparator}{BackupType}_{Partial}_{CopyOnly}";
			$directoryStructure = "{DatabaseName}";

			# $fileName = "{ServerName}${InstanceName}_{DatabaseName}_{BackupType}_{Partial}_{CopyOnly}_{Year}{Month}{Day}_{Hour}{Minute}{Second}_{FileNumber}.{FileExtension}";
			$fileName = "{DatabaseName}_{Year}{Month}{Day}_{Hour}{Minute}{Second}_{BackupType}_{Partial}_{CopyOnly}_{FileNumber}.{FileExtension}";

			$parameters = @{}

			if (-not $null -eq $backupUrl) {
				SbsWriteDebug "Backing up to URL: $($backupUrl.baseUrlWithPrefix)"
				$parameters["@Url"] = $backupUrl.baseUrlWithPrefix;
				# Recommended MS settings for blob storage
				$parameters["@MaxTransferSize"] = 4194304;
				$parameters["@BlockSize"] = 65536;
			}
			else {
				# These are incompatible with the use of URL
				SbsWriteDebug "No backup url defined, backing up to database backup directory: $databaseBackupDirectory (if NULL, default configured location will be used)";
				$parameters["@Directory"] = $databaseBackupDirectory;
				$parameters["@CleanupTime"] = "$cleanupTime";
			}

			if (-not $null -eq $mirrorUrl) {
				$parameters["@MirrorURL"] = $mirrorUrl.baseUrlWithPrefix;
			}

			$parameters["@DirectoryStructure"] = $directoryStructure;
			$parameters["@fileName"] = $fileName;
			$parameters["@Databases"] = $db.Name;
				
			$parameters["@BackupType"] = $solutionBackupType;
			$parameters["@Verify"] = "N";
			$parameters["@Compress"] = "Y";

			$parameters["@CheckSum"] = "N";
			$parameters["@LogToTable"] = "Y";
				
			if (($isSystemDb -eq $false) -and (-not [String]::IsNullOrWhitespace($certificate))) {
				$parameters["@Encrypt"] = "Y";
				$parameters["@EncryptionAlgorithm"] = "AES_256";
				$parameters["@ServerCertificate"] = $certificate;
			}
				
			if (($backupType -eq "FULL") -and ($isSystemDb -eq $false)) {
				# SbsWriteDebug "Running Index Optimize Before Full Backup";
				# Index optimize before the full
				SbsWriteHost "Starting IndexOptimize before full backup";
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
				SbsWriteHost "Finished IndexOptimize before full backup";
			}
				
			# This is always OK for FULL, DIFF OR LOG backups (but on FULL it means nothing)
			$parameters["@ChangeBackupType"] = $changeBackupType;

			if ($changeBackupType -eq "Y" -and ($modificationLeve -gt 0)) {
				$parameters["@ModificationLevel"] = $modificationLevel;
			}

			# Not sure why i have to add this N explictly here as it is the default value...
			$parameters["@CopyOnly"] = "N";

			# In LOGNOW these parameters are not applied!
			if ($backupType -eq "LOG") {
				$parameters["@LogSizeSinceLastLogBackup"] = $logSizeSinceLastLogBackup;
				$parameters["@TimeSinceLastLogBackup"] = $timeSinceLastLogBackup;
			}

			SbsWriteDebug "Calling backup solution with arguments $(ConvertTo-Json $parameters -Depth 3)";
			Invoke-DbaQuery -SqlInstance $sqlInstance -QueryTimeout 1800 -Database "master" -Query "DatabaseBackup" -SqlParameter $parameters -CommandType StoredProcedure -EnableException;
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
	SbsWriteHost "$($backupType) backups finished in $($Minutes) min";
}