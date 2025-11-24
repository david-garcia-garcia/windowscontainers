$global:ErrorActionPreference = if ($null -ne $Env:SBS_ENTRYPOINTERRORACTION ) { $Env:SBS_ENTRYPOINTERRORACTION } else { 'Stop' }

# Gather all environment variables that match the pattern SBS_CRON_TRIGGER_
$triggerEnvVars = Get-ChildItem env: | Where-Object { $_.Name -match '^SBS_CRON_(.*)$' }

# Get the environment variable value. If it's not null or empty, split it into an array; otherwise, create an empty array.
$SBS_CRONRUNONBOOT_Array = @();
if (-not [string]::IsNullOrWhiteSpace([System.Environment]::GetEnvironmentVariable("SBS_CRONRUNONBOOT"))) {
    $SBS_CRONRUNONBOOT_Array = [System.Environment]::GetEnvironmentVariable("SBS_CRONRUNONBOOT").Split(',');
}

# Loop through each found environment variable
foreach ($var in $triggerEnvVars) {

    # Use regex to extract the task name from the environment variable name
    if ($var.Name -match '^SBS_CRON_(.*)$') {
        $taskName = $matches[1]
    }
    else {
        # If for some reason the regex doesn't match (shouldn't happen due to the where filter), skip this iteration
        continue;
    }

    # Extract the JSON trigger configuration from the environment variable value
    $jsonTrigger = $var.Value;

    # Check if the task exists before applying the trigger
    if (Get-ScheduledTask | Where-Object { $_.TaskName -eq $taskName }) {
        SbsSetTaskTrigger -taskName $taskName -jsonTrigger $jsonTrigger;
        SbsWriteHost "Applied trigger to task: $taskName with config: $jsonTrigger";
    }
    else {
        SbsWriteWarning "Task $taskName does not exist.";
        continue;
    }

    # If the task name is in the $SBS_CRONRUNONBOOT_Array, start it immediately
    if ($taskName -in $SBS_CRONRUNONBOOT_Array) {
        # Ensure the task is enabled before starting it
        $task = Get-ScheduledTask | Where-Object { $_.TaskName -eq $taskName };
        if ($task.Settings.Enabled -eq $false) {
            Enable-ScheduledTask -TaskName $taskName | Out-Null;
            SbsWriteHost "Enabled task $taskName as it is configured in SBS_CRONRUNONBOOT";
        }
        SbsWriteHost "Starting task immediately as per SBS_CRONRUNONBOOT configuration: $($taskName)";
        Start-ScheduledTask -TaskName $taskName;
    }
}