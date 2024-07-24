function Set-SqlServerJob {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [Object]
		$SqlInstance,
        [Parameter(Mandatory = $true)]
        [string]$JobDefinition
    )
        
    # Connect to the SQL Server instance
    $server = Connect-DbaInstance -SqlInstance $SqlInstance

    $scheduleName = $null;

    # Convert the JSON string to a PowerShell object
    $jobInfo = $JobDefinition | ConvertFrom-Json -ErrorAction Stop;
    
    $schedulesInfo = $null;
    $jobName = $null;

    $newJobParams = @{}

    foreach ($param in $jobInfo.psobject.Properties) {
        if ($param.Name -eq "Schedules") {
            $schedulesInfo = $param.Value;
            continue;
        }
        if ($param.Name -eq "Job") {
            $jobName = $param.Value;
        }
        $value = $param.Value;
        $newJobParams[$param.Name] = $value
    }

    $newJobParams["Schedule"] = New-Object System.Collections.ArrayList;

    # Get the job
    $job = Get-DbaAgentJob -SqlInstance $server -Job $newJobParams["Job"];
    
    # Check if the job exists
    if ($null -eq $job) {
        SbsWriteWarning "Job $jobName not found on server $SqlInstance.";
        return;
    }
    
    SbsWriteDebug -Message "Found job with name $($jobName)"

    $scheduleIndex = 0;

    foreach ($scheduleInfo in $schedulesInfo) {

        # Initialize the parameters for New-ScheduledTaskTrigger
        $newTriggerParams = @{}

        # Map JSON properties to New-ScheduledTaskTrigger parameters
        foreach ($param in $scheduleInfo.psobject.Properties) {
            if ($param.Name -eq "Schedule") {
                $scheduleName = $param.Value;
                continue;
            }
            $value = $param.Value;
            $newTriggerParams[$param.Name] = $value
        }

        # Do not share schedules among JOBS
        $scheduleName = "$($jobName)_$scheduleIndex";
        $scheduleIndex++;

        # Get the existing schedule or create a new one
        # Query to get the job and schedule relationship
        $query = @"
            SELECT 
                j.name AS JobName,
                s.name AS ScheduleName,
                s.enabled,
                s.freq_type,
                s.freq_interval,
                s.freq_subday_type,
                s.freq_subday_interval,
                s.active_start_date,
                s.active_end_date
            FROM msdb.dbo.sysjobs AS j
            JOIN msdb.dbo.sysjobschedules AS js ON j.job_id = js.job_id
            JOIN msdb.dbo.sysschedules AS s ON js.schedule_id = s.schedule_id
            WHERE j.name = @jobName
"@

        # Execute the query
        $jobSchedules = Invoke-DbaQuery -SqlInstance $SqlInstance -Query $query -SqlParameter @{ jobName = $jobName } -EnableException

        # If the schedule is not bound to the JOB, create it now
        $currentSchedule = $jobSchedules | Where-Object { $_.ScheduleName -eq $scheduleName };

        if ($null -eq $currentSchedule) {
            SbsWriteDebug "Creating new schedule '$scheduleName' for job '$jobName'"

            # New-DbaAgentSchedule -SqlInstance $server -Schedule $scheduleName -Job $jobName -Force -EnableException;
            $createScheduleQuery = @"
            EXEC msdb.dbo.sp_add_schedule
                @schedule_name=@scheduleName,
                @enabled=0,
                @freq_type=4,
                @freq_interval=1,
                @freq_subday_type=1,
                @freq_subday_interval=0,
                @active_start_date=20230405,
                @active_start_time=0,
                @owner_login_name=N'sa';
"@;

                Invoke-DbaQuery -SqlInstance $SqlInstance -Query $createScheduleQuery -SqlParameter @{ scheduleName = $scheduleName } -EnableException

            $attachToJobQuery = @"
            EXEC msdb.dbo.sp_attach_schedule
                @job_name=@jobName,
                @schedule_name=@scheduleName
"@;

            SbsWriteDebug "Attaching schedule $scheduleName to job $jobName";
            Invoke-DbaQuery -SqlInstance $SqlInstance -Query $attachToJobQuery -SqlParameter @{ scheduleName = $scheduleName; jobName = $jobName } -EnableException
        }

        $newTriggerParams["SqlInstance"] = $server;
        $newTriggerParams["ScheduleName"] = $scheduleName;
        $newTriggerParams["EnableException"] = $true;
        $newTriggerParams["Job"] = $jobName;

        # Default to recurrence factor of 1
        if (-not $newTriggerParams.ContainsKey("FrequencyRecurrenceFactor")) {
            $newTriggerParams["FrequencyRecurrenceFactor"] = 1;
        }

        # Default to enabled
        if (-not $newTriggerParams.ContainsKey("Enabled")) {
            $newTriggerParams["Enabled"] = $true;
        }

        # Apply the updated schedule to the job.
        SbsWriteDebug "Updating schedule configuration '$scheduleName' for job '$jobName'"
        Set-DbaAgentSchedule @newTriggerParams;

        $newJobParams["Schedule"].Add($scheduleName);

        Write-Host "Job schedule for $jobName updated successfully on server $serverName."
    }

    $newJobParams["SqlInstance"] = $server;
    $newJobParams["Job"] = $jobName;

    SbsWriteDebug "Updating job '$jobName' configuration"
    Set-DbaAgentJob @newJobParams;
}

# Example Set-SqlServerJob "localhost" -JobDefinition '{"Job":"MsslBackup - FULL", "Schedules": [{"Schedule": "Full weekly", "FrequencyType": "Weekly", "FrequencyInterval": "Saturday", "StartTime": "230000"}], "Enabled":true}'