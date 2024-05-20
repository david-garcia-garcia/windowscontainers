function SbsMssqlRunBackups {

	param(
		[Parameter(Mandatory = $true)]
		# FULL = FULL backup
		# DIFF = DIFF backup, will be promoted to FULL according to MSSQL_BACKUP_CHANGEBACKUPTYPE+MSSQL_BACKUP_MODIFICATIONLEVEL
		# LOG = LOG backup, only taken if MSSQL_BACKUP_LOGSIZESINCELASTBACKUP/MSSQL_BACKUP_TIMESINCELASTLOGBACKUP
		# LOGNOW = Run a log backup immediately
		[ValidateSet('FULL', 'DIFF', 'LOG', 'SYSTEM', 'LOGNOW')]
		[string]$backupType
	)

	$backupType = $backupType.ToUpper();

	Import-Module dbatools;

	Set-DbatoolsConfig -FullName sql.connection.trustcert -Value $true -Register
	Set-DbatoolsConfig -FullName sql.connection.encrypt -Value $false -Register 

	$certificateBackupDirectory = $Env:MSSQL_PATH_BACKUP;
	$databaseBackupDirectory = $Env:MSSQL_PATH_BACKUP;
	$backupCertificate = $Env:MSSQL_BACKUP_CERT;

	# Default to 10min or 100Mb whatever comes first
	$logSizeSinceLastLogBackup = SbsGetEnvInt -Name "MSSQL_BACKUP_LOGSIZESINCELASTBACKUP" -DefaultValue 100;
	$timeSinceLastLogBackup = SbsGetEnvInt -Name "MSSQL_BACKUP_TIMESINCELASTLOGBACKUP" -DefaultValue 600;

	# ZERO Defaults means keep enough to restore to the most recent consistent backup
	$cleanupTimeLog = SbsGetEnvInt -Name "MSSQL_BACKUP_CLEANUPTIME_LOG" -DefaultValue 0;
	$cleanupTimeDiff = SbsGetEnvInt -Name "MSSQL_BACKUP_CLEANUPTIME_DIFF" -DefaultValue 0;
	$cleanupTimeFull = SbsGetEnvInt -Name "MSSQL_BACKUP_CLEANUPTIME_FULL" -DefaultValue 0;

	$modificationLevel = SbsGetEnvInt -Name "MSSQL_BACKUP_MODIFICATIONLEVEL" -DefaultValue 30;
	$changeBackupType = SbsGetEnvString -Name "MSSQL_BACKUP_CHANGEBACKUPTYPE" -DefaultValue "Y";

	# Mirroring DOES not work with IMMUTABLE STORAGE, so it is not good for Long Term Retention
	$mirrorUrlDiff = SbsGetEnvString -Name "MSSQL_PATH_BACKUPMIRRORURL_DIFF" -DefaultValue $null;
	$mirrorUrlFull = SbsGetEnvString -Name "MSSQL_PATH_BACKUPMIRRORURL_FULL" -DefaultValue $null;
	$mirrorUrlLog = SbsGetEnvString -Name "MSSQL_PATH_BACKUPMIRRORURL_LOG" -DefaultValue $null;

	$mirrorUrl = $null;

	$instance = "localhost";
	Test-DbaConnection $instance;
	$sqlInstance = Connect-DbaInstance $instance;

	$backupUrl = SbsParseSasUrl -Url $Env:MSSQL_PATH_BACKUPURL;
	if ($null -ne $backupUrl) {
		SbsEnsureCredentialForSasUrl -SqlInstance $sqlInstance -Url $backupUrl.url;
	}

	$StopWatch = new-object system.diagnostics.stopwatch
	$StopWatch.Start();
		
	SbsWriteHost "Starting $($backupType) backup generation $($instance)"
	$systemDatabases = Get-DbaDatabase -SqlInstance $sqlInstance -ExcludeUser;

	# Recorremos todas las bases de datos
	# Check for null and determine count
	$excludeUser = $backupType -eq "SYSTEM";
	$excludeSystem = $backupType -ne "SYSTEM";
	$dbs = Get-DbaDatabase -SqlInstance $sqlInstance -Status @('Normal') -ExcludeUser:$excludeUser -ExcludeSystem:$excludeSystem ;

	if (-not [String]::IsNullOrWhitespace($Env:MSSQL_DATABASE)) {
		$dbs = $dbs | Where-Object { $_.Name -eq $Env:MSSQL_DATABASE };
		if ($dbs.Count -eq 0) {
			SbsWriteHost "Database $($Env:MSSQL_DATABASE) not found in instance: $($instance)";
			return;
		}
	}

	# Check for null and determine count
	$dbCount = 0;

	if ($null -ne $dbs) {
		$dbCount = $dbs.Count;
	} else {
		SbsWriteWarning "Could not obtain databases to backup in instance: $($instance)";
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
			
			# Llamamos al stored procedure que genera los backups
			$SqlConn = New-Object System.Data.SqlClient.SqlConnection("Server=$instance;Database=master;Integrated Security=True;TrustServerCertificate=True;");
			$SqlConn.Open();

			$cmd = $SqlConn.CreateCommand();
			$cmd.CommandType = 'StoredProcedure';
			$cmd.CommandText = 'dbo.DatabaseBackup';
					
			$cmd.CommandTimeout = 1200;

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
					$cleanupTime = $cleanupTimeFull;
					$mirrorUrl = SbsParseSasUrl -Url $mirrorUrlFull;
				}
				"DIFF" {
					$cleanupTime = $cleanupTimeDiff;
					$mirrorUrl = SbsParseSasUrl -Url $mirrorUrlDiff;
				}
				"LOG" {
					$cleanupTime = $cleanupTimeLog;
					$mirrorUrl = SbsParseSasUrl -Url $mirrorUrlLog;
				}
			}

			if ($null -ne $mirrorUrl) {
				Write-Host "Using mirror URL $($mirrorUrl.baseUrlWithPrefix)"
				SbsEnsureCredentialForSasUrl -SqlInstance $sqlInstance -Url $mirrorUrl.url;
			}

			if ($solutionBackupType -eq "LOG" -and ($recoveryModel -eq "SIMPLE")) {
				SbsWriteWarning "LOG backup requested for database $($db.Name) with SIMPLE recovery model.";
				continue;
			}

			# Because of the volatile nature of this setup, ServerName and InstanceName make no sense
			# we could have an APP name?
			# $directoryStructure = "{ServerName}{$InstanceName}{DirectorySeparator}{DatabaseName}{DirectorySeparator}{BackupType}_{Partial}_{CopyOnly}";
			$directoryStructure = "{DatabaseName}{DirectorySeparator}{BackupType}_{Partial}_{CopyOnly}";

			# $fileName = "{ServerName}${InstanceName}_{DatabaseName}_{BackupType}_{Partial}_{CopyOnly}_{Year}{Month}{Day}_{Hour}{Minute}{Second}_{FileNumber}.{FileExtension}";
			$fileName = "{DatabaseName}_{BackupType}_{Partial}_{CopyOnly}_{Year}{Month}{Day}_{Hour}{Minute}{Second}_{FileNumber}.{FileExtension}";

			if (-not $null -eq $backupUrl) {
				Write-Host "Backing up to URL: $($backupUrl.baseUrlWithPrefix)"
				$cmd.Parameters.AddWithValue("@Url", $backupUrl.baseUrlWithPrefix) | Out-Null
				$cmd.Parameters.AddWithValue("@MaxTransferSize", 4194304) | Out-Null
				$cmd.Parameters.AddWithValue("@BlockSize", 65536) | Out-Null
			}
			else {
				# These are incompatible with the use of URL
				$cmd.Parameters.AddWithValue("@Directory", $databaseBackupDirectory) | Out-Null
				$cmd.Parameters.AddWithValue("@CleanupTime", "$cleanupTime") | Out-Null
			}

			if (-not $null -eq $mirrorUrl) {
				$cmd.Parameters.AddWithValue("@MirrorURL", $mirrorUrl.baseUrlWithPrefix) | Out-Null
			}

			$cmd.Parameters.AddWithValue("@DirectoryStructure", $directoryStructure ) | Out-Null
			$cmd.Parameters.AddWithValue("@fileName", $fileName ) | Out-Null
			$cmd.Parameters.AddWithValue("@Databases", $db.Name) | Out-Null
				
			$cmd.Parameters.AddWithValue("@BackupType", $solutionBackupType) | Out-Null
			$cmd.Parameters.AddWithValue("@Verify", "N") | Out-Null
			$cmd.Parameters.AddWithValue("@Compress", "Y") | Out-Null

			$cmd.Parameters.AddWithValue("@CheckSum", "N") | Out-Null
			$cmd.Parameters.AddWithValue("@LogToTable", "Y") | Out-Null
				
			if (($isSystemDb -eq $false) -and (-not [String]::IsNullOrWhitespace($certificate))) {
				$cmd.Parameters.AddWithValue("@Encrypt", "Y") | Out-Null
				$cmd.Parameters.AddWithValue("@EncryptionAlgorithm", "AES_256") | Out-Null
				$cmd.Parameters.AddWithValue("@ServerCertificate", $certificate) | Out-Null
			}
				
			if (($backupType -eq "FULL") -and ($isSystemDb -eq $false)) {
				# Index optimize before the full
				$indexCmd = $SqlConn.CreateCommand()
				$indexCmd.CommandType = 'StoredProcedure'
				$indexCmd.CommandText = 'dbo.IndexOptimize'
				$indexCmd.CommandTimeout = 1200
				$indexCmd.Parameters.AddWithValue("@Databases", $db.Name) | Out-Null
				$indexCmd.Parameters.AddWithValue("@FragmentationLevel1", 30) | Out-Null
				$indexCmd.Parameters.AddWithValue("@FragmentationLevel2", 50) | Out-Null
				$indexCmd.Parameters.AddWithValue("@FragmentationLow", $null) | Out-Null
				$indexCmd.Parameters.AddWithValue("@FragmentationMedium", 'INDEX_REORGANIZE') | Out-Null
				$indexCmd.Parameters.AddWithValue("@FragmentationHigh", 'INDEX_REBUILD_ONLINE,INDEX_REBUILD_OFFLINE') | Out-Null
				$indexCmd.Parameters.AddWithValue("@MinNumberOfPages", 1000) | Out-Null
				$indexCmd.Parameters.AddWithValue("@TimeLimit", 600) | Out-Null
				$indexCmd.Parameters.AddWithValue("@LogToTable", 'Y') | Out-Null
				$indexCmd.ExecuteScalar();
			}
				
			# This is always OK for FULL, DIFF OR LOG backups (but on FULL it means nothing)
			$cmd.Parameters.AddWithValue("@ChangeBackupType", $changeBackupType) | Out-Null

			if ($changeBackupType -eq "Y" -and ($modificationLeve -gt 0)) {
				$cmd.Parameters.AddWithValue("@ModificationLevel", $modificationLevel) | Out-Null
			}

			# Not sure why i have to add this N explictly here as it is the default value...
			$cmd.Parameters.AddWithValue("@CopyOnly", "N") | Out-Null
	
			if ($backupType -eq "LOG") {
				$cmd.Parameters.AddWithValue("@LogSizeSinceLastLogBackup", $logSizeSinceLastLogBackup) | Out-Null
				$cmd.Parameters.AddWithValue("@TimeSinceLastLogBackup", $timeSinceLastLogBackup) | Out-Null
			}

			$result = $cmd.ExecuteScalar();
			$SqlConn.Close();

			$backupCompleted = $false;

			if ($null -eq $result) {
				SbsWriteHost "Backup completed succesfully.";
				$backupCompleted = $true;
			}
			else {
				SbsWriteError "Error running backup: $($result)";
			}

			if ($backupCompleted) {
		        SbsMssqlAzCopyLastBackupOfType -SqlInstance $sqlInstance -Database $db.Name -OriginalBackupUrl $backupUrl;
			}

			# No cleanup for LOGNOW, because it is a forced closeup backup, we need this to be as fast as possible.
			if ($backupType -ne "LOGNOW") {
				if ((-not $null -eq $backupUrl) -and ($null -ne $cleanupTime)) {
					SbsMssqlCleanupBackups -SqlInstance $sqlInstance -Url $backupUrl.url -Type $solutionBackupType -DatabaseName  $db.Name -CleanupTime $cleanupTime;
				}
			}
		}
		Catch {
			$exceptions += $_.Exception
			SbsWriteWarning "Error performing $($backupType) backup for the database $($db) and instance $($instance): $($_.Exception.Message)"
			SbsWriteWarning "Exception Stack Trace: $($_.Exception.StackTrace)"
		}
	}
	
	if ($exceptions.Count -gt 1) {
		throw (New-Object System.AggregateException -ArgumentList $exceptions)
	}
	elseif ($exceptions.Count -gt 0) {
		{
			throw $exceptions[0];
		}

		$StopWatch.Stop()
		$Minutes = $StopWatch.Elapsed.TotalMinutes;
		SbsWriteHost "$($backupType) backups finished in $($Minutes) min"
	}
}