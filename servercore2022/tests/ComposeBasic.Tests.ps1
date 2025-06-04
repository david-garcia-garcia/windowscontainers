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
        docker exec $Env:imageName powershell "
            try { 
                Start-Process 'C:\crashtest.exe' -ArgumentList '-so' -Wait -NoNewWindow
            } catch { 
                Write-Host 'Process crashed as expected' 
            }
        "
        # Wait for WER to process the crash and create the dump (with timeout)
        $timeout = 15 # seconds
        $elapsed = 0
        $checkInterval = 1 # second
        $finalDumpCount = $initialDumpCount
        
        do {
            Start-Sleep -Seconds $checkInterval
            $elapsed += $checkInterval
            $finalDumpCount = docker exec $Env:imageName powershell "(Get-ChildItem 'C:\test\CrashDumps' -Filter '*.dmp' -ErrorAction SilentlyContinue | Measure-Object).Count"
            Write-Host "Checking for dump files... Current count: $finalDumpCount, Initial: $initialDumpCount, Elapsed: ${elapsed}s"
        } while (([int]$finalDumpCount -eq [int]$initialDumpCount) -and ($elapsed -lt $timeout))
        
        # Verify that at least one new dump file was created
        [int]$finalDumpCount | Should -BeGreaterThan ([int]$initialDumpCount)
    }

    It 'Shutdown not called twice' {
        docker exec $Env:ImageName powershell "powershell -File c:\entrypoint\shutdown.ps1"
        WaitForLog $Env:ImageName "SHUTDOWN END" -extendedTimeout
        docker compose -f servercore2022/compose-basic.yaml stop;

        # This does NOT work when using LOGMONITOR
        # WaitForLog $Env:ImageName "Integrated shutdown skipped"
        # https://github.com/microsoft/windows-container-tools/issues/169
    }

    AfterAll {
        docker compose -f servercore2022/compose-basic.yaml down;
    }
}

