Describe 'compose-basic.yaml' {
    BeforeAll {
        . ./../bootstraptest.ps1
        $Env:ImageName = "servercore2022-servercore-1"
    }
        
    It 'Container initializes' {
        docker compose -f servercore2022/compose-basic.yaml up -d;
        WaitForLog $Env:ImageName "Initialization Completed"  -extendedTimeout
    }

    It 'Booted synchronously' {
        WaitForLog $Env:ImageName "init scripts synchronously"
    }

    It 'Recursively executes scripts from mounted subdirectory' {
        WaitForLog $Env:ImageName "TEST_RECURSIVE_INIT_SCRIPT_EXECUTED"
    }

    It 'LogRotate is enabled by default' {
        docker exec $Env:ImageName powershell "(Get-ScheduledTask LogRotate).Triggers[0].Enabled" | Should -Be "True"
    }

    It 'Timezone is set' {
        docker exec $Env:ImageName powershell "(Get-TimeZone).Id" | Should -Match "Alaskan Standard Time";
    }

    It 'sshd service is stopped' {
        docker exec $Env:ImageName powershell "(Get-Service -Name 'sshd').Status" | Should -Be "Stopped"
    }

    It 'sshd service is disabled' {
        docker exec $Env:ImageName powershell "(Get-Service -Name 'sshd').StartType" | Should -Be "Disabled"
    }

    It 'WER crash dump is generated on stack overflow' {
        # Check if WER dump folder exists
        $dumpFolderExists = docker exec $Env:imageName powershell "Test-Path 'C:\test\CrashDumps'"
        $dumpFolderExists | Should -Be "True"
        
        # Count existing dump files before crash
        $initialDumpCount = docker exec $Env:imageName powershell "(Get-ChildItem 'C:\test\CrashDumps' -Filter '*.dmp' -ErrorAction SilentlyContinue | Measure-Object).Count"
        
        # Copy crashtest.exe to container and execute with -so argument
        # https://github.com/spreadex/win-docker-crash-dump/blob/main/Dockerfile
        docker cp "servercore2022/tests/crashtest.exe" "${Env:imageName}:C:\crashtest.exe"
        docker exec $Env:imageName powershell "Start-Process 'C:\crashtest.exe' -ArgumentList '-so'"
        # Wait for WER to process the crash and create the dump (with timeout)
        $timeout = 30 # seconds
        $startTime = Get-Date
        $finalDumpCount = $initialDumpCount
        
        do {
            Start-Sleep -Seconds 1
            $elapsed = [int]((Get-Date) - $startTime).TotalSeconds
            $finalDumpCount = docker exec $Env:imageName powershell "(Get-ChildItem 'C:\test\CrashDumps' -Filter '*.dmp' -ErrorAction SilentlyContinue | Measure-Object).Count"
            Write-Host "Checking for dump files... Current count: $finalDumpCount, Initial: $initialDumpCount, Elapsed: ${elapsed}s"
        } while (([int]$finalDumpCount -eq [int]$initialDumpCount) -and ($elapsed -lt $timeout))
        
        # Verify that at least one new dump file was created
        [int]$finalDumpCount | Should -BeGreaterThan ([int]$initialDumpCount)
        Start-Sleep -Seconds 5
    }

    It 'Shutdown not called twice' {
        Start-Sleep -Seconds 5
        docker exec $Env:ImageName powershell "powershell -File c:\entrypoint\shutdown.ps1"
        WaitForLog $Env:ImageName "SHUTDOWN END" -extendedTimeout
        docker compose -f servercore2022/compose-basic.yaml stop;

        # This does NOT work when using LOGMONITOR
        # WaitForLog $Env:ImageName "Integrated shutdown skipped"
        # https://github.com/microsoft/windows-container-tools/issues/169
    }

    It 'LogMonitor monitors c:\logmonitorlogs\*.log files' {
        # Write a test log message to a file in the monitored directory
        $testMessage = "LOGMONITOR_TEST_$(Get-Date -Format 'yyyyMMddHHmmss')"
        docker exec $Env:ImageName powershell "Set-Content -Path 'C:\logmonitorlogs\test.log' -Value '$testMessage'"
        
        # Wait for LogMonitor to pick up the log file and output it to container logs
        WaitForLog $Env:ImageName $testMessage -extendedTimeout
        
        # Cleanup
        docker exec $Env:ImageName powershell "Remove-Item 'C:\logmonitorlogs\test.log' -ErrorAction SilentlyContinue"
    }

    AfterAll {
        docker compose -f servercore2022/compose-basic.yaml down;
    }
}

