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
            if ($param.Value -eq "Timeout.InfiniteTimeSpan") {
                $value = [System.Threading.Timeout]::InfiniteTimeSpan;
            }
            else {
                [Timespan]$parsedTimespan = [System.Threading.Timeout]::InfiniteTimeSpan;
                if ([TimeSpan]::TryParseExact($param.Value, "hh\:mm\:ss", $null, [ref]$parsedTimespan)) {
                    $value = $parsedTimespan;
                } else {
                    SbsWriteError "Failed to parse task $($taskName) TimeSpan value: $($param.Value). Use the format 'hh:mm:ss' or 'Timeout.InfiniteTimeSpan'";
                    return;
                }
            }
        }
        elseif ($param.Name -eq "DaysOfWeek") {
            # Convert DayOfWeek from JSON string/array to [System.DayOfWeek] enum values
            $dayOfWeekValues = @()
            foreach ($day in $value) {
                $dayOfWeekValues += [System.DayOfWeek]::Parse([System.DayOfWeek], $day)
            }
            $value = $dayOfWeekValues
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
    Set-ScheduledTask -TaskName $taskName -Trigger $trigger | Out-Null;
    
    # Explicitly enable the task to ensure it's enabled when a trigger is configured
    Enable-ScheduledTask -TaskName $taskName | Out-Null;
}

# Example usage
# Replace "YourTaskName" with the actual name of your task
# SbsAddTriggerToTask -taskName "test" -jsonTrigger '{"Weekly" : true, "At": "2023-01-01T03:00:00", "DaysOfWeek": ["Saturday"], "WeeksInterval": 1}'; 
# SbsAddTriggerToTask -taskName "test" -jsonTrigger '{"Daily" : true, "At": "00:00:00", "RepetitionInterval": "00:15:00", "RepetitionDuration": "23:59:59"}'
# SbsAddTriggerToTask -taskName "test" -jsonTrigger '{"Daily" : true, "At": "2023-01-01T04:00:00", "DaysInterval": 1}'
