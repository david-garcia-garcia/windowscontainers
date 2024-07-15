. ./imagenames.ps1

function WaitForLog {
    param (
        [string]$containerName,
        [string]$logContains,
        [int]$timeoutSeconds = 25
    )

    $timeout = New-TimeSpan -Seconds $timeoutSeconds
    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    while ($sw.Elapsed -lt $timeout) {
        Start-Sleep -Seconds 2
        $logs = docker logs $containerName --tail 150 2>&1
        if ($logs -match $logContains) {
            return;
        }
    }

    Write-Error "Timeout reached without detecting '$($logContains)' in logs. $($logs)"
}