$global:ErrorActionPreference = if ($null -ne $Env:SBS_ENTRYPOINTERRORACTION ) { $Env:SBS_ENTRYPOINTERRORACTION } else { 'Stop' }

# Gather all environment variables that match the pattern SBS_CRON_TRIGGER_
$triggerEnvVars = Get-ChildItem env: | Where-Object { $_.Name -match '^SBS_CRON_(.*)$' }

# Loop through each found environment variable
foreach ($var in $triggerEnvVars) {

    # Use regex to extract the task name from the environment variable name
    if ($var.Name -match '^SBS_CRON_(.*)$') {
        $taskName = $matches[1]
    } else {
        # If for some reason the regex doesn't match (shouldn't happen due to the where filter), skip this iteration
        continue;
    }

    # Extract the JSON trigger configuration from the environment variable value
    $jsonTrigger = $var.Value;

    Write-Output $jsonTrigger;

    # Execute the function to apply the trigger to the task
    SbsSetTaskTrigger -taskName $taskName -jsonTrigger $jsonTrigger;

    # Output for confirmation or debugging
    SbsWriteHost "Applied trigger to task: $taskName with config: $jsonTrigger";
}