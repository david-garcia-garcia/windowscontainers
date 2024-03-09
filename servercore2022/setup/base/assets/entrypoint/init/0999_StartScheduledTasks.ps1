$global:ErrorActionPreference = if ($null -ne $Env:SBS_ENTRYPOINTERRORACTION ) { $Env:SBS_ENTRYPOINTERRORACTION } else { 'Stop' }

# Get the environment variable value. If it's not null or empty, split it into an array; otherwise, create an empty array.
$SBS_CRONRUNONBOOT_Array = @();
if (-not [string]::IsNullOrWhiteSpace([System.Environment]::GetEnvironmentVariable("SBS_CRONRUNONBOOT"))) {
    $SBS_CRONRUNONBOOT_Array = [System.Environment]::GetEnvironmentVariable("SBS_CRONRUNONBOOT").Split(',');
}

Get-ChildItem "C:\cron\definitions" -Filter *.xml | ForEach-Object {
    SbsWriteHost "Checking and registering scheduled task: $($_.BaseName)"
    
    # Check if the scheduled task already exists
    $existingTask = Get-ScheduledTask -TaskName $_.BaseName -ErrorAction SilentlyContinue
    
    if ($existingTask) {
        SbsWriteHost "Task already exists. Stopping and unregistering existing task: $($_.BaseName)"
        # Stop the existing task
        Stop-ScheduledTask -TaskName $_.BaseName -ErrorAction SilentlyContinue;
        # Wait a moment to ensure the task has stopped
        # Check the status of the task to ensure it has stopped
        do {
            Start-Sleep -Seconds 1;
            $taskStatus = (Get-ScheduledTask -TaskName $_.BaseName).State;
            SbsWriteHost "Waiting for task to stop. Current status: $taskStatus";
        } while ($taskStatus -eq 'Running');
        # Unregister the existing task
        Unregister-ScheduledTask -TaskName $_.BaseName -Confirm:$false;
    }
    
    # Register the new scheduled task
    SbsWriteHost "Registering new scheduled task: $($_.BaseName)";
    Register-ScheduledTask -Xml (Get-Content $_.FullName -Raw) -TaskName $_.BaseName;

    # If the task name is in the $SBS_CRONRUNONBOOT_Array, start it immediately
    if ($_.BaseName -in $SBS_CRONRUNONBOOT_Array) {
        SbsWriteHost "Starting task immediately as per SBS_CRONRUNONBOOT configuration: $($_.BaseName)";
        Start-ScheduledTask -TaskName $_.BaseName;
    }
}
