function SbsDeployDbBackupInfo {
    param (
        [Parameter(Mandatory = $true)]
        [string]$sqlInstance
    )

    $sqlDropProcedure = @"
IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[GetDatabaseBackupInfo]') AND type in (N'P', N'PC'))
DROP PROCEDURE dbo.GetDatabaseBackupInfo
"@;
	
    $sqlUpsertProcedure = @"
CREATE PROCEDURE dbo.GetDatabaseBackupInfo
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @DatabaseInfo TABLE
    (
        db_Database NVARCHAR(128),
        backupByDb_sinceFull NVARCHAR(50),
        backupByDb_sinceDiff NVARCHAR(50),
        backupByDb_sinceLog NVARCHAR(50),
        backupByDb_modPages NVARCHAR(50),
        backupByDb_modified NVARCHAR(50),
        hours_since_last_backup NVARCHAR(50),
        recovery_model NVARCHAR(50),
        last_full_backup_size_MB NVARCHAR(50),
        last_diff_backup_size_MB NVARCHAR(50),
        total_db_size_MB NVARCHAR(50)
    );

    DECLARE @DatabaseName NVARCHAR(128),
            @DynamicSQL NVARCHAR(MAX),
            @sinceFull NVARCHAR(50),
            @sinceDiff NVARCHAR(50),
            @sinceLog NVARCHAR(50),
            @modPages NVARCHAR(50),
            @modified NVARCHAR(50),
            @hours_since_last_backup NVARCHAR(50),
            @recovery_model NVARCHAR(50),
            @last_full_backup_size_MB NVARCHAR(50),
            @last_diff_backup_size_MB NVARCHAR(50),
            @total_db_size_MB NVARCHAR(50);

    DECLARE DatabaseCursor CURSOR FOR
    SELECT name FROM sys.databases
    WHERE state = 0;

    OPEN DatabaseCursor;

    FETCH NEXT FROM DatabaseCursor INTO @DatabaseName;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @DynamicSQL = N'
            DECLARE @modified_extent_page_count BIGINT,
                    @allocated_extent_page_count BIGINT;

            SELECT 
                @modified_extent_page_count = SUM(modified_extent_page_count),
                @allocated_extent_page_count = SUM(allocated_extent_page_count)
            FROM ' + QUOTENAME(@DatabaseName) + N'.sys.dm_db_file_space_usage;

SELECT 
    @sinceFull = CAST(DATEDIFF(minute, MAX(CASE WHEN [type] = ''D'' THEN backup_finish_date END), GETDATE()) / 60 AS INT),
    @sinceDiff = CAST(DATEDIFF(minute, MAX(CASE WHEN [type] = ''I'' THEN backup_finish_date END), GETDATE()) / 60 AS INT),
    @sinceLog = CAST(DATEDIFF(minute, MAX(CASE WHEN [type] = ''L'' THEN backup_finish_date END), GETDATE()) / 60 AS INT),
    @modPages = CAST(@modified_extent_page_count AS NVARCHAR),
    @modified = FORMAT(100.0 * @modified_extent_page_count / @allocated_extent_page_count, ''N2''),
    @hours_since_last_backup = CAST(DATEDIFF(hour, MAX(backup_finish_date), GETDATE()) AS INT),
    @recovery_model = (SELECT recovery_model_desc FROM sys.databases WHERE name = ' + QUOTENAME(@DatabaseName, N'''') + N'),
    @last_full_backup_size_MB = CAST((SELECT TOP 1 CAST(backup_size / 1024.0 / 1024 AS INT) FROM msdb.dbo.backupset WHERE database_name = ' + QUOTENAME(@DatabaseName, N'''') + N' AND type = ''D'' ORDER BY backup_finish_date DESC) AS VARCHAR(MAX)),
    @last_diff_backup_size_MB = CAST((SELECT TOP 1 CAST(backup_size / 1024.0 / 1024 AS INT) FROM msdb.dbo.backupset WHERE database_name = ' + QUOTENAME(@DatabaseName, N'''') + N' AND type = ''I'' ORDER BY backup_finish_date DESC) AS VARCHAR(MAX)),
    @total_db_size_MB = CAST((SELECT CAST(SUM(size * 8.0 / 1024) AS INT) FROM sys.master_files WHERE database_id = DB_ID(' + QUOTENAME(@DatabaseName, N'''') + N') AND type = 0) AS VARCHAR(MAX))
FROM msdb.dbo.backupset
WHERE database_name = ' + QUOTENAME(@DatabaseName, N'''') + N';
        ';

        EXEC sp_executesql @DynamicSQL, N'@sinceFull NVARCHAR(50) OUTPUT, @sinceDiff NVARCHAR(50) OUTPUT, @sinceLog NVARCHAR(50) OUTPUT, @modPages NVARCHAR(50) OUTPUT, @modified NVARCHAR(50) OUTPUT, @hours_since_last_backup NVARCHAR(50) OUTPUT, @recovery_model NVARCHAR(50) OUTPUT, @last_full_backup_size_MB NVARCHAR(50) OUTPUT, @last_diff_backup_size_MB NVARCHAR(50) OUTPUT, @total_db_size_MB NVARCHAR(50) OUTPUT', @sinceFull OUTPUT, @sinceDiff OUTPUT, @modPages OUTPUT, @modified OUTPUT, @hours_since_last_backup OUTPUT, @recovery_model OUTPUT, @last_full_backup_size_MB OUTPUT, @last_diff_backup_size_MB OUTPUT, @total_db_size_MB OUTPUT;

        INSERT INTO @DatabaseInfo (db_Database, backupByDb_sinceFull, backupByDb_sinceDiff, backupByDb_sinceLog, backupByDb_modPages, backupByDb_modified, hours_since_last_backup, recovery_model, last_full_backup_size_MB, last_diff_backup_size_MB, total_db_size_MB)
        VALUES (@DatabaseName, @sinceFull, @sinceDiff, @sinceLog, @modPages, @modified, @hours_since_last_backup, @recovery_model, @last_full_backup_size_MB, @last_diff_backup_size_MB, @total_db_size_MB);

        FETCH NEXT FROM DatabaseCursor INTO @DatabaseName;
    END

    CLOSE DatabaseCursor;
    DEALLOCATE DatabaseCursor;

    SELECT * FROM @DatabaseInfo;
END
"@

    $sqlCreateTable = @"
IF EXISTS (SELECT * FROM sys.tables WHERE name = 'SbsDatabaseBackupInfo')
DROP TABLE SbsDatabaseBackupInfo;

CREATE TABLE SbsDatabaseBackupInfo
(
        db_Database NVARCHAR(128),
        backupByDb_sinceFull NVARCHAR(50),
        backupByDb_sinceDiff NVARCHAR(50),
        backupByDb_sinceLog NVARCHAR(50),
        backupByDb_modPages NVARCHAR(50),
        backupByDb_modified NVARCHAR(50),
        hours_since_last_backup NVARCHAR(50),
        recovery_model NVARCHAR(50),
        last_full_backup_size_MB NVARCHAR(50),
        last_diff_backup_size_MB NVARCHAR(50),
        total_db_size_MB NVARCHAR(50)
);
"@

    $sqlCreateJob = @"
USE msdb;
GO

IF EXISTS (SELECT * FROM msdb.dbo.sysjobs WHERE name = 'RefreshSbsDatabaseBackupInfo')
EXEC msdb.dbo.sp_delete_job @job_name=N'RefreshSbsDatabaseBackupInfo';
GO

EXEC msdb.dbo.sp_add_job
    @job_name=N'RefreshSbsDatabaseBackupInfo',
    @enabled=1,
    @description=N'Refresh the contents of the SbsDatabaseBackupInfo table every 5 minute',
    @owner_login_name=N'sa';
GO

EXEC msdb.dbo.sp_add_jobstep
    @job_name=N'RefreshSbsDatabaseBackupInfo',
    @step_name=N'RefreshTableContents',
    @subsystem=N'TSQL',
    @command=N'
DELETE FROM SbsDatabaseBackupInfo;
INSERT INTO SbsDatabaseBackupInfo
EXEC dbo.GetDatabaseBackupInfo;
';
GO

IF NOT EXISTS (SELECT 1 FROM msdb.dbo.sysschedules WHERE name = N'RefreshEvery5Minute')
BEGIN
    EXEC msdb.dbo.sp_add_schedule
        @schedule_name=N'RefreshEvery5Minute',
        @freq_type=4,
        @freq_interval=1,
        @freq_subday_type=4,
        @freq_subday_interval=5,
        @active_start_date=20230405,
        @active_start_time=0;
END
GO

EXEC msdb.dbo.sp_attach_schedule
    @job_name=N'RefreshSbsDatabaseBackupInfo',
    @schedule_name=N'RefreshEvery5Minute';
GO

EXEC msdb.dbo.sp_add_jobserver
    @job_name=N'RefreshSbsDatabaseBackupInfo',
    @server_name = N'(local)';
GO
"@

    # List of your SQL commands
    $sqlCommands = @($sqlDropProcedure, $sqlUpsertProcedure, $sqlCreateTable, $sqlCreateJob)

    foreach ($sqlCommand in $sqlCommands) {
        # Clean up the command to remove new lines and carriage returns
        $sqlCommand = $sqlCommand -replace '\r', '' -replace '\n', ' '
        # Split the command on "GO" statements to handle them as separate batches
        $sqlBatches = $sqlCommand -split '(?i)go'
        foreach ($sqlBatch in $sqlBatches) {
            if ([string]::IsNullOrWhiteSpace($sqlBatch)) { continue }
            # Use Invoke-DbaQuery to execute each SQL batch. This cmdlet manages the connection for you.
            try {
                Invoke-DbaQuery -SqlInstance $sqlInstance -Database $databaseName -Query $sqlBatch -ErrorAction Stop
            }
            catch {
                Write-Error "Error executing SQL command: $sqlBatch"
                Write-Error $_.Exception.Message
            }
        }
    }
}