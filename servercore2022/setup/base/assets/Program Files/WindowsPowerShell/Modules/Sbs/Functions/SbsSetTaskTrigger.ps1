function SbsSetTaskTrigger {

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$taskName,
        [Parameter(Mandatory = $true)]
        [string]$jsonTrigger
    )

    # Convert the JSON string to a PowerShell object
    $triggerParams = $jsonTrigger | ConvertFrom-Json;

    # Initialize the parameters for New-ScheduledTaskTrigger
    $newTriggerParams = @{}

    # Map JSON properties to New-ScheduledTaskTrigger parameters
    foreach ($param in $triggerParams.psobject.Properties) {
        $value = $param.Value;

        # Handle TimeSpan conversion
        if ($param.Name -match "RandomDelay|RepetitionDuration|RepetitionInterval") {
            try {
                $value = [TimeSpan]::ParseExact($param.Value, "hh\:mm\:ss", $null)
            }
            catch {
                Write-Host "Invalid TimeSpan format for $($param.Name). Use 'HH:mm:ss'."
                return
            }
        }

        # Assign the parameter
        $newTriggerParams[$param.Name] = $value
    }

    # Create the trigger
    $trigger = New-ScheduledTaskTrigger @newTriggerParams

    # Get the existing task
    $task = Get-ScheduledTask | Where-Object { $_.TaskName -eq $taskName };
    if ($null -eq $task) {
        Write-Error "Task $taskName does not exist.";
        return;
    }

    # Use Set-ScheduledTask to update the task with the new trigger
    Set-ScheduledTask -TaskName $taskName -Trigger $trigger;
}

# Example usage
# Replace "YourTaskName" with the actual name of your task
# SbsAddTriggerToTask -taskName "test" -jsonTrigger '{"Weekly" : true, "At": "2023-01-01T03:00:00", "DaysOfWeek": ["Saturday"], "WeeksInterval": 1}'; 
# SbsAddTriggerToTask -taskName "test" -jsonTrigger '{"Daily" : true, "At": "00:00:00", "RepetitionInterval": "00:15:00", "RepetitionDuration": "23:59:59"}'
# SbsAddTriggerToTask -taskName "test" -jsonTrigger '{"Daily" : true, "At": "2023-01-01T04:00:00", "DaysInterval": 1}'
