function SbsRunBackups {

	param(
		[Parameter(Mandatory = $true)]
		[ValidateSet('FULL', 'DIFF', 'LOG', 'SYSTEM')]
		[string]$backupType
	)

	Import-Module dbatools;

	# TODO: CONFIGURE THESE BETTER
	$certificateBackupDirectory = $Env:MSSQL_PATH_BACKUP;
	$databaseBackupDirectory = $Env:MSSQL_PATH_BACKUP;
	$instance = "localhost";

	Try {

		$ErrorActionPreference = "Stop";
	
		$MaxRetries = 2;
		$RetryIntervalInSeconds = 5;

		$StopWatch = new-object system.diagnostics.stopwatch
		$StopWatch.Start();
		
		SbsWriteHost "Starting $($backupType) backup generation $($instance)"
		$systemDatabases = Get-DbaDatabase -SqlInstance $instance -ExcludeUser;

		# Recorremos todas las bases de datos
		# Check for null and determine count
		$dbs = Get-DbaDatabase -SqlInstance $instance -Status @('Normal');

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
					if (($isSystemDb -eq $false)) {
						$certificate = "$($db.Name)_$((Get-Date).year)";
						if (($null -eq (Get-DbaDbCertificate -SqlInstance $instance -Certificate $certificate))) {
							SbsEnsureCert -Name $certificate -BackupLocation $certificateBackupDirectory;
						}
					}
			
					# Llamamos al store procedure que genera los backups
					$SqlConn = New-Object System.Data.SqlClient.SqlConnection("Server = $instance; Database = master; Integrated Security = True;")
					$SqlConn.Open()

					$cmd = $SqlConn.CreateCommand()
					$cmd.CommandType = 'StoredProcedure'
					$cmd.CommandText = 'dbo.DatabaseBackup'
					
					$cmd.CommandTimeout = 1200

					$solutionBackupType = $backupType;
					if ($backupType -eq "SYSTEM") {
						$solutionBackupType = "FULL";
					}

					$cmd.Parameters.AddWithValue("@Databases", $db.Name) | Out-Null
					$cmd.Parameters.AddWithValue("@Directory", $databaseBackupDirectory) | Out-Null
					$cmd.Parameters.AddWithValue("@BackupType", $solutionBackupType) | Out-Null
					$cmd.Parameters.AddWithValue("@Verify", "N") | Out-Null
					$cmd.Parameters.AddWithValue("@Compress", "Y") | Out-Null
					$cmd.Parameters.AddWithValue("@CleanupTime", "24") | Out-Null
					$cmd.Parameters.AddWithValue("@CheckSum", "N") | Out-Null
					$cmd.Parameters.AddWithValue("@LogToTable", "Y") | Out-Null
				
					if ($isSystemDb -eq $false) {
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
						$indexCmd.Parameters.AddWithValue("@TimeLimit", 3600) | Out-Null
						$indexCmd.Parameters.AddWithValue("@LogToTable", 'Y') | Out-Null
						$indexCmd.ExecuteScalar();
					}
				
					if ($backupType -eq "DIFF") {
						$cmd.Parameters.AddWithValue("@ModificationLevel", "30") | Out-Null
						$cmd.Parameters.AddWithValue("@ChangeBackupType", "Y") | Out-Null
					}
				
					if ($backupType -eq "LOG") {
						# Hardcoded to 200MB or 15min whatever comes first
						$cmd.Parameters.AddWithValue("@LogSizeSinceLastLogBackup", "200") | Out-Null
						$cmd.Parameters.AddWithValue("@TimeSinceLastLogBackup", "900") | Out-Null
					}

					$result = $cmd.ExecuteScalar();
					$SqlConn.Close()

					if ($null -eq $result) {
						SbsWriteHost "Backup completed succesfully."
					}
					else {
						SbsWriteError "Error running backup: $($result)"
					}
				
					$success = $true
				
					# Eliminamos fulls y diferenciales antiguos
					#$instancia = $instance.Replace('\', '$')
					#$BackupFolderPath = Get-ChildItem $json.Directory -recurse | Where-Object { $_.PSIsContainer -eq $true -and $_.Name -eq $db -and (CheckParentFolders $_ $instancia) } | % { $_.FullName }
					#If (([string]::IsNullOrEmpty($BackupFolderPath)) -or ($backupType -eq "LOG")) { continue }
					#Remove-RedundantBackups -Instance $instance -BackupFolderPath $BackupFolderPath
				}
				Catch {
					$retryCount++
					SbsWriteHost "Retry $($retryCount): Error performing $($backupType) backup for the database $($db) and instance $($instance): " + $_.Exception.Message
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
	
		# Ejecutamos script adicional al acabar la ejecución 
		#$pathPostScript = "$PSScriptRoot\$($postScript).ps1"
		#if (Test-Path $pathPostScript -PathType Leaf) {
		#	& $pathPostScript
		#}
	
		$StopWatch.Stop()
		$Minutes = $StopWatch.Elapsed.TotalMinutes
		SbsWriteHost "$($backupType) backups created successfully in $($Minutes) min"
	}
	Catch {
		SbsWriteError "Error performing $($backupType) backup for the instance $($instance): " + $_.Exception.Message
	}
}