function SbsMssqlRunBackups {

	param(
		# FULL = FULL backup
		# DIFF = DIFF backup, will be promoted to FULL according to MSSQL_BACKUP_CHANGEBACKUPTYPE+MSSQL_BACKUP_MODIFICATIONLEVEL
		# LOG = LOG backup, only taken if MSSQL_BACKUP_LOGSIZESINCELASTBACKUP/MSSQL_BACKUP_TIMESINCELASTLOGBACKUP
		# LOGNOW = Run a log backup immediately
		[Parameter(Mandatory = $true)]
		[ValidateSet('FULL', 'DIFF', 'LOG', 'SYSTEM', 'LOGNOW')]
		[string]$backupType,

		# The database instance (dbatools), a connection string or a server name.
		[Object]
		$sqlInstance = $null
	)

	#########################################################
	# Avoid at all costs using BDATOOLS here, because
	# it uses TOO much CPU, and this script is called
	# i.e. for transaction log backups very frequently
	#########################################################

	$backupType = $backupType.ToUpper();
	
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
		$sqlInstance = SbsEnsureConnectionString -SqlInstanceOrConnectionString "localhost";
		SbsWriteDebug "Defaulting to LOCALHOST as database.";
	}

	$connectionString = SbsEnsureConnectionString -SqlInstanceOrConnectionString $sqlInstance;

	# Get server name
	$r = (SbsMssqlRunQuery -Instance $connectionString -CommandText "SELECT @@SERVERNAME AS name");
	$serverName = $r.name
	if ($null -eq $serverName) {
		SbsWriteError "Could not obtain @@SERVERNAME. Verify the connection to the database.";
		return;
	}

	SbsWriteDebug "Server name: $($serverName)";

	$backupUrl = SbsParseSasUrl -Url $Env:MSSQL_PATH_BACKUPURL;
	if ($null -ne $backupUrl) {
		SbsWriteDebug "Loading environment MSSQL_PATH_BACKUPURL";
		SbsEnsureCredentialForSasUrl -SqlInstance $sqlInstance -Url $backupUrl.url;
	}

	$StopWatch = new-object system.diagnostics.stopwatch
	$StopWatch.Start();
		
	SbsWriteHost "Starting '$($backupType)' backup generation for '$($serverName)'"
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
		SbsWriteWarning "Could not obtain databases to backup in instance: $($serverName)";
		return;
	}

	# Write to the event log
	SbsWriteHost "Found $dbCount databases for backup";

	$exceptions = @();

	foreach ($db in $databases) {

		Try {
					
			$r = SbsMssqlRunQuery -Instance $connectionString -CommandText "SELECT recovery_model_desc FROM sys.databases WHERE name = @name" -Parameters @{ name = $db.name }
			$recoveryModel = $r.recovery_model_desc

			SbsWriteHost "Backup '$db' with recovery model '$($recoveryModel)'";

			# Certificate rotates every year
			$certificate = $null;
			# This needs more love: do not use DBATOOLS + certificate backup should support cloud storage
			# Do not encrypt backups for system databases
			#if (($isSystemDb -eq $false) -and ($backupCertificate -eq "AUTO")) {
			#	$certificate = "$($db.Name)_$((Get-Date).year)";
		    #		if (($null -eq (Get-DbaDbCertificate -SqlInstance $sqlInstance -Certificate $certificate))) {
		    #			SbsMssqlEnsureCert -Name $certificate -BackupLocation $certificateBackupDirectory;
			#	}
			#}
			
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
			
			# Cleanup is not supported if the token 2024-05-28 09:39:16 {BackupType} is not part of the directory.
			$directoryStructure = "{DatabaseName}{DirectorySeparator}{BackupType}_{Partial}_{CopyOnly}";

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

				# The value for the parameter @CleanupTime is not supported. Cleanup is not supported if the token 
				# {BackupType} is not part of the directory.
				# The documentation is available at 
				# https://ola.hallengren.com/sql-server-backup.html.
				if ($directoryStructure -match "\{BackupType\}") {
					$parameters["@CleanupTime"] = "$cleanupTime";
				}
				else {
					# Better a warning, than no backups at all :(
					SbsWriteWarning "Hallengren solution @CleanupTime cannot be used if {BackupType} is not part of the directory structure.";
				}
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
			SbsMssqlRunQuery -Instance $connectionString -CommandType "StoredProcedure" -CommandText "dbo.Databasebackup" -CommandTimeout 1800 -Parameters $parameters;
		} 
		Catch {
			$exceptions += $_.Exception
			SbsWriteWarning "Error performing $($backupType) backup for the database $($db) and instance $($serverName): $($_.Exception.Message)"
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