. ./imagenames.ps1

function OutputLog {
    param (
        [string]$containerName
    )

    $logs = Invoke-Command -Script {
        $ErrorActionPreference = "silentlycontinue"
        docker logs $containerName --tail 250 2>&1
    } -ErrorAction SilentlyContinue
    Write-Host "---------------- LOGSTART"
    Write-Host ($logs -join "`r`n")
    Write-Host "---------------- LOGEND"
}

function WaitForLog {
    param (
        [string]$containerName,
        [string]$logContains,
        [switch]$extendedTimeout
    )

    $timeoutSeconds = 20;

    if ($extendedTimeout) {
        $timeoutSeconds = 90;
    }

    $timeout = New-TimeSpan -Seconds $timeoutSeconds
    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    # First, wait for container to exist and be available
    $containerAvailable = $false
    $containerCheckTimeout = New-TimeSpan -Seconds 10
    $containerCheckSw = [System.Diagnostics.Stopwatch]::StartNew()
    
    while ($containerCheckSw.Elapsed -le $containerCheckTimeout) {
        $containerStatus = Invoke-Command -Script {
            $ErrorActionPreference = "silentlycontinue"
            docker ps -a --filter "name=$containerName" --format "{{.Status}}" 2>&1
        } -ErrorAction SilentlyContinue
        
        if ($containerStatus -and $containerStatus -notmatch "No such container") {
            $containerAvailable = $true
            break
        }
        Start-Sleep -Milliseconds 500
    }
    
    if (-not $containerAvailable) {
        Write-Host "---------------- LOGSTART"
        Write-Host "Container '$containerName' is not available. Container may have crashed or exited."
        Write-Host "---------------- LOGEND"
        Write-Error "Container '$containerName' is not available after $($containerCheckSw.Elapsed.TotalSeconds)s. Container may have crashed or exited."
    }

    while ($sw.Elapsed -le $timeout) {
        Start-Sleep -Seconds 1
        
        # Check if container still exists before reading logs
        $containerExists = Invoke-Command -Script {
            $ErrorActionPreference = "silentlycontinue"
            docker ps -a --filter "name=$containerName" --format "{{.Names}}" 2>&1
        } -ErrorAction SilentlyContinue
        
        if (-not $containerExists -or $containerExists -match "No such container") {
            Write-Host "---------------- LOGSTART"
            Write-Host "Container '$containerName' no longer exists. Container may have crashed or exited."
            Write-Host "Attempting to retrieve final logs..."
            Write-Host "---------------- LOGEND"
            # Try to get logs one more time even if container doesn't exist (docker logs might still work for stopped containers)
        }
        
        $logs = Invoke-Command -Script {
            $ErrorActionPreference = "silentlycontinue"
            docker logs $containerName --tail 350 2>&1
        } -ErrorAction SilentlyContinue
        
        if ($logs -match $logContains) {
            return;
        }
        
        # If logs contain error about container not existing, fail early
        if ($logs -match "No such container") {
            Write-Host "---------------- LOGSTART"
            Write-Host "Container '$containerName' does not exist. Container may have crashed or exited."
            Write-Host ($logs -join "`r`n")
            Write-Host "---------------- LOGEND"
            Write-Error "Container '$containerName' does not exist. Cannot read logs. Container may have crashed or exited."
        }
    }
    Write-Host "---------------- LOGSTART"
    Write-Host ($logs -join "`r`n")
    Write-Host "---------------- LOGEND"
    Write-Error "Timeout reached without detecting '$($logContains)' in logs after $($sw.Elapsed.TotalSeconds)s"
}

function ThrowIfError([int]$ExpectedExitCode = 0) {
    # STATUS_CONTROL_C_EXIT (0xC000013A / 3221225786)
    # This exit code indicates an interactive application received Ctrl+C and was aborted.
    # In Windows, cmd.exe detects Ctrl+C in batch scripts by checking if a child process
    # returns STATUS_CONTROL_C_EXIT. If we treat this as an error, it can inadvertently
    # stop batch scripts. Therefore, we explicitly ignore this exit code.
    # See: https://devblogs.microsoft.com/oldnewthing/20230303-00/?p=107899
    $STATUS_CONTROL_C_EXIT = 3221225786  # 0xC000013A
    
    if ($LASTEXITCODE -eq $STATUS_CONTROL_C_EXIT) {
        Write-Warning "Process was terminated with STATUS_CONTROL_C_EXIT (Ctrl+C). Treating as non-error."
        return
    }
    
    if ($LASTEXITCODE -ne $ExpectedExitCode) {
        Write-Error "Last exit code $($LASTEXITCODE) did not match expected code $ExpectedExitCode";
    }
}

function HoldBuild() {
    # This method should create a file, and hold in a loop with a sleep 
    # until the file is deleted
    # $Env:BUILD_TEMP this is the directory where the file should be crated
    # Define the full path for the file
    $filePath = Join-Path -Path $Env:BUILD_TEMP -ChildPath "holdbuild.txt"

    # Create the file
    New-Item -ItemType File -Path $filePath -Force

    Write-Host "Created file: $filePath"

    # Hold in a loop until the file is deleted
    while (Test-Path $filePath) {
        Start-Sleep -Seconds 10
        Write-Host "Build held until file is deleted: $filePath "
    }

    Write-Host "File deleted: $filePath"
}