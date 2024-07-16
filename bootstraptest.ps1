. ./imagenames.ps1

function OutputLog {
    param (
        [string]$containerName
    )

    $logs = Invoke-Command -Script {
        $ErrorActionPreference = "silentlycontinue"
        docker logs $containerName --tail 150 2>&1
    } -ErrorAction SilentlyContinue
    Write-Output "---------------- LOGSTART"
    Write-Output ($logs -join "`r`n")
    Write-Output "---------------- LOGEND"
}

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
        $logs = Invoke-Command -Script {
            $ErrorActionPreference = "silentlycontinue"
            docker logs $containerName --tail 150 2>&1
        } -ErrorAction SilentlyContinue
        if ($logs -match $logContains) {
            return;
        }
    }
    Write-Output "---------------- LOGSTART"
    Write-Output ($logs -join "`r`n")
    Write-Output "---------------- LOGEND"
    Write-Error "Timeout reached without detecting '$($logContains)' in logs."
}

function ThrowIfError() {
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Last exit code was NOT 0.";
    }
}