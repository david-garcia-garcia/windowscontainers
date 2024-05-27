function Set-SqlServerJobSchedule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [Object]
		$SqlInstance,
        [Parameter(Mandatory = $false)]
        [string]$Job,
        [Parameter(Mandatory = $true)]
        [string]$JsonTrigger
    )

    $scheduleName = $null;

    # Convert the JSON string to a PowerShell object
    $triggerParams = $jsonTrigger | ConvertFrom-Json

    # Initialize the parameters for New-ScheduledTaskTrigger
    $newTriggerParams = @{}

    # Map JSON properties to New-ScheduledTaskTrigger parameters
    foreach ($param in $triggerParams.psobject.Properties) {
        if ($param.Name -eq "Job") {
            $jobName = $param.Value;
            continue;
        }
        if ($param.Name -eq "Schedule") {
            $scheduleName = $param.Value;
            continue;
        }
        $value = $param.Value;
        $newTriggerParams[$param.Name] = $value
    }

    # Connect to the SQL Server instance
    $server = Connect-DbaInstance -SqlInstance $SqlInstance

    # Get the job
    $job = Get-DbaAgentJob -SqlInstance $server -Job $jobName

    # Check if the job exists
    if ($null -eq $job) {
        Write-Error "Job $jobName not found on server $serverName.";
        return;
    }

    # Do not share schedules among JOBS
    $scheduleName = "$($jobName)_$scheduleName";

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
    $jobSchedules = Invoke-DbaQuery -SqlInstance $SqlInstance -Query $query -SqlParameter @{ jobName = $jobName }

    # If the schedule is not bound to the JOB, create it now
    $currentSchedule = $jobSchedules | Where-Object { $_.ScheduleName -eq $scheduleName };

    if ($null -eq $currentSchedule) {
        New-DbaAgentSchedule -SqlInstance $server -Schedule $scheduleName -Job $jobName -Force -EnableException;
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
    Set-DbaAgentSchedule @newTriggerParams;

    Write-Host "Job schedule for $jobName updated successfully on server $serverName."
}

# Example usage
# Replace "YourSqlServerName" and "YourJobName" with actual values
# Set-SqlServerJobSchedule -SqlInstance "localhost" -jobName "MsslBackup - FULL" -jsonTrigger '{"FrequencyType": "Daily", "FrequencyInterval": 1 }'
