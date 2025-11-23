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

    while ($sw.Elapsed -le $timeout) {
        Start-Sleep -Seconds 1
        $logs = Invoke-Command -Script {
            $ErrorActionPreference = "silentlycontinue"
            docker logs $containerName --tail 350 2>&1
        } -ErrorAction SilentlyContinue
        if ($logs -match $logContains) {
            return;
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