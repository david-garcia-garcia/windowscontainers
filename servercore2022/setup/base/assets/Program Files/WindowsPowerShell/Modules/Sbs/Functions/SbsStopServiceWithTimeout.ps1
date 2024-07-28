function SbsStopServiceWithTimeout {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServiceName,

        [Parameter(Mandatory = $false)]
        [int]$TimeoutInSeconds = 15
    )

    $service = Get-Service | Where-Object { $_.Name -eq $ServiceName }
    
    if ($null -eq $service) {
        SbsWriteError "Service '$ServiceName' not found."
        return;
    }

    # Attempt to stop the service with -Force to include dependent services
    SbsWriteHost "Stopping service '$ServiceName' and its dependent services..."
    Stop-Service -Name $ServiceName -Force -NoWait

    # Initialize the Stopwatch
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    do {
        Start-Sleep -Seconds 1;
        $service.Refresh();
        if ($stopwatch.Elapsed.TotalSeconds -ge $TimeoutInSeconds) {
            Write-Warning "Timeout reached. Service '$ServiceName' or one of its dependents could not be stopped in $TimeoutInSeconds seconds."
            return;
        }
    } while ($service.Status -ne 'Stopped')

    Write-Host "Service '$ServiceName' and all dependent services have been stopped successfully."
}