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

	Import-Module dbatools;

	Set-DbatoolsConfig -FullName sql.connection.trustcert -Value $true -Register
	Set-DbatoolsConfig -FullName sql.connection.encrypt -Value $false -Register 

	$certificateBackupDirectory = $Env:MSSQL_PATH_BACKUP;
	$databaseBackupDirectory = $Env:MSSQL_PATH_BACKUP;
	$backupCertificate = $Env:MSSQL_BACKUP_CERT;

	$backupUrl = SbsParseSasUrl -Url $Env:MSSQL_PATH_BACKUPURL;

	# Default to 10min or 100Mb whatever comes first
	$logSizeSinceLastLogBackup = SbsGetEnvInt -Name "MSSQL_BACKUP_LOGSIZESINCELASTBACKUP" -DefaultValue 100;
	$timeSinceLastLogBackup = SbsGetEnvInt -Name "MSSQL_BACKUP_TIMESINCELASTLOGBACKUP" -DefaultValue 600;

	$cleanupTimeLog = SbsGetEnvInt -Name "MSSQL_BACKUP_CLEANUPTIME_LOG" -DefaultValue 48;
	$cleanupTimeDiff = SbsGetEnvInt -Name "MSSQL_BACKUP_CLEANUPTIME_DIFF" -DefaultValue 168;
	$cleanupTimeFull = SbsGetEnvInt -Name "MSSQL_BACKUP_CLEANUPTIME_FULL" -DefaultValue 168;

	$modificationLevel = SbsGetEnvInt -Name "MSSQL_BACKUP_MODIFICATIONLEVEL" -DefaultValue 30;
	$changeBackupType = SbsGetEnvString -Name "MSSQL_BACKUP_CHANGEBACKUPTYPE" -DefaultValue "Y";

	$instance = "localhost";
	Test-DbaConnection $instance;
	$sqlInstance = Connect-DbaInstance $instance;

	$ErrorActionPreference = "Stop";
	
	$MaxRetries = 2;
	$RetryIntervalInSeconds = 5;

	$StopWatch = new-object system.diagnostics.stopwatch
	$StopWatch.Start();
		
	SbsWriteHost "Starting $($backupType) backup generation $($instance)"
	$systemDatabases = Get-DbaDatabase -SqlInstance $sqlInstance -ExcludeUser;

	# Recorremos todas las bases de datos
	# Check for null and determine count
	$dbs = Get-DbaDatabase -SqlInstance $sqlInstance -Status @('Normal');

	# Check for null and determine count
	$dbCount = 0

	if ($null -ne $dbs) {
		$dbCount = $dbs.Count;
	}
	else {
		SbsWriteError "Could not obtain databases to backup in instance: $($instance)";
		return;
	}

	# Write to the event log
	SbsWriteHost "Found $dbCount databases for backup";

	foreach ($db in $dbs) {

		$retryCount = 0
		$success = $false

		while ((-not $success) -and ($retryCount -lt $MaxRetries)) {

			Try {
					
				$isSystemDb = $systemDatabases.Name -contains $db.Name;

				if (($backupType -ne "SYSTEM") -and ($isSystemDb -eq $true)) {
					break;
				}

				SbsWriteHost "Backup '$db' isSystemDatabase: $($isSystemDb)";

				# Certificate rotates every year
				$certificate = $null;

				# Do not encrypt backups for system databases
				if (($isSystemDb -eq $false) -and ($backupCertificate -eq "AUTO")) {
					$certificate = "$($db.Name)_$((Get-Date).year)";
					if (($null -eq (Get-DbaDbCertificate -SqlInstance $sqlInstance -Certificate $certificate))) {
						SbsMssqlEnsureCert -Name $certificate -BackupLocation $certificateBackupDirectory;
					}
				}
			
				# Llamamos al store procedure que genera los backups
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
					$recoveryModel = (Get-DbaDbRecoveryModel -SqlInstance $sqlInstance -Database $db.Name).RecoveryModel;
					switch ($recoveryModel) {
						"FULL" {  
							$solutionBackupType = "LOG";
						}
						Default {
							$solutionBackupType = "DIFF";
						}
					}
				}

				switch ($solutionBackupType) {
					"FULL" {
						$cleanupTime = $cleanupTimeFull;
					}
					"DIFF" {
						$cleanupTime = $cleanupTimeDiff;
					}
					"LOG" {
						$cleanupTime = $cleanupTimeLog;
					}
				}

				# Because of the volatile nature of this setup, ServerName and InstanceName make no sense
				# we could have an APP name?
				# $directoryStructure = "{ServerName}{$InstanceName}{DirectorySeparator}{DatabaseName}{DirectorySeparator}{BackupType}_{Partial}_{CopyOnly}";
				$directoryStructure = "{DatabaseName}{DirectorySeparator}{BackupType}_{Partial}_{CopyOnly}";

				# $fileName = "{ServerName}${InstanceName}_{DatabaseName}_{BackupType}_{Partial}_{CopyOnly}_{Year}{Month}{Day}_{Hour}{Minute}{Second}_{FileNumber}.{FileExtension}";
				$fileName = "{DatabaseName}_{BackupType}_{Partial}_{CopyOnly}_{Year}{Month}{Day}_{Hour}{Minute}{Second}_{FileNumber}.{FileExtension}";

				if ($backupUrl) {
					$cmd.Parameters.AddWithValue("@Url", $backupUrl.baseUrl) | Out-Null
				}

				$cmd.Parameters.AddWithValue("@DirectoryStructure", $directoryStructure ) | Out-Null
				$cmd.Parameters.AddWithValue("@fileName", $fileName ) | Out-Null
				$cmd.Parameters.AddWithValue("@Databases", $db.Name) | Out-Null
				$cmd.Parameters.AddWithValue("@Directory", $databaseBackupDirectory) | Out-Null
				$cmd.Parameters.AddWithValue("@BackupType", $solutionBackupType) | Out-Null
				$cmd.Parameters.AddWithValue("@Verify", "N") | Out-Null
				$cmd.Parameters.AddWithValue("@Compress", "Y") | Out-Null

				# Cleanup time not supported when using URL for backup
				if ($null -eq $backupUrl) {
					$cmd.Parameters.AddWithValue("@CleanupTime", "$cleanupTime") | Out-Null
				}

				$cmd.Parameters.AddWithValue("@CleanupTime", "$cleanupTime") | Out-Null

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
				
				if ($backupType -eq "LOG") {
					$cmd.Parameters.AddWithValue("@LogSizeSinceLastLogBackup", $logSizeSinceLastLogBackup) | Out-Null
					$cmd.Parameters.AddWithValue("@TimeSinceLastLogBackup", $timeSinceLastLogBackup) | Out-Null
				}

				$result = $cmd.ExecuteScalar();
				$SqlConn.Close();

				if ($null -eq $result) {
					SbsWriteHost "Backup completed succesfully.";
				}
				else {
					SbsWriteError "Error running backup: $($result)";
				}
				
				$success = $true;
			}
			Catch {
				$retryCount++
				SbsWriteHost "Retry $($retryCount): Error performing $($backupType) backup for the database $($db) and instance $($instance): $($_.Exception.Message)"
				if ($retryCount -lt $MaxRetries) {
					SbsWriteHost "Retrying in $RetryIntervalInSeconds seconds... ($retryCount of $MaxRetries)";
					Start-Sleep -Seconds $RetryIntervalInSeconds
				}
				else {
					SbsWriteHost "Max retries reached. Aborting.";
				}
			}
		}
	}
	
	$StopWatch.Stop()
	$Minutes = $StopWatch.Elapsed.TotalMinutes 
	SbsWriteHost "$($backupType) backups created successfully in $($Minutes) min"
}