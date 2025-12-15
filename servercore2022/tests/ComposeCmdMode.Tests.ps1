Describe 'compose-cmdmode.yaml' {
    BeforeAll {
        . ./../bootstraptest.ps1
        $Env:ImageName = "servercore2022-servercore-1"
    }
        
    It 'Container initializes with CmdMode entrypoint' {
        docker compose -f servercore2022/compose-cmdmode.yaml up -d;
        WaitForLog $Env:ImageName "Initialization completed" -extendedTimeout
    }

    It 'CmdMode is enabled' {
        WaitForLog $Env:ImageName "CmdMode enabled: Shutdown listeners disabled to reduce memory footprint"
    }

    It 'CmdMode skips main service loop' {
        WaitForLog $Env:ImageName "CmdMode enabled: Main service loop skipped. Process will be held by CMD entrypoint"
    }

    It 'Initialization runs synchronously in CmdMode' {
        WaitForLog $Env:ImageName "init scripts synchronously"
    }

    It 'Container is ready (ready file exists)' {
        $readyFileExists = docker exec $Env:ImageName cmd /c "if exist C:\ready (echo true) else (echo false)"
        $readyFileExists | Should -Match "true"
    }

    It 'Timezone is set' {
        docker exec $Env:ImageName powershell "(Get-TimeZone).Id" | Should -Match "Pacific Standard Time"
    }

    It 'Initialization scripts executed successfully' {
        # Verify that init scripts ran by checking for a service that should be configured
        $sshService = docker exec $Env:ImageName powershell "(Get-Service -Name 'sshd' -ErrorAction SilentlyContinue).Name"
        $sshService | Should -Match "sshd"
    }

    It 'LogRotate is enabled' {
        docker exec $Env:ImageName powershell "(Get-ScheduledTask LogRotate).Triggers[0].Enabled" | Should -Be "True"
    }

    It 'Container stays running when command is provided' {
        # In CmdMode, container should stay running when a command is provided
        # (Unlike normal mode which runs forever, CmdMode requires a command to keep running)
        # Verify container is running (not exited)
        $containerStatus = docker ps --filter "name=$Env:ImageName" --format "{{.Status}}"
        $containerStatus | Should -Not -BeNullOrEmpty
        $containerStatus | Should -Not -Match "Exited"
        
        # Verify the default command (ping) is actually running
        $pingProcess = docker exec $Env:ImageName powershell "(Get-Process -Name ping -ErrorAction SilentlyContinue).Name"
        $pingProcess | Should -Match "ping"
    }

    It 'Container exits when no command is provided' {
        # In CmdMode, container should exit after initialization if no command is provided
        # This is different from normal mode which runs forever
        # Test by running a container without a command
        $testContainerName = "cmdmode-test-no-cmd"
        docker run -d --name $testContainerName --entrypoint "c:\Program Files\LogMonitor\LogMonitor.exe" ${Env:IMG_SERVERCORE2022} /CONFIG c:\logmonitor\config.json C:\entrypoint\entrypoint.cmd
        
        # Wait for initialization to complete
        Start-Sleep -Seconds 15
        
        # Check that container has exited (status should show "Exited")
        $containerStatus = docker ps -a --filter "name=$testContainerName" --format "{{.Status}}"
        $containerStatus | Should -Match "Exited"
        
        # Cleanup
        docker rm $testContainerName -f
    }

    It 'Container can execute different commands via CMD entrypoint' {
        # Test that we can execute commands in the container via CMD
        # This verifies the CMD entrypoint allows command execution
        docker exec $Env:ImageName cmd /c "echo CMD_MODE_TEST_SUCCESS > C:\cmdtest.txt"
        
        # Verify the file was created and contains the expected text
        $fileContent = docker exec $Env:ImageName powershell "Get-Content C:\cmdtest.txt -ErrorAction SilentlyContinue"
        $fileContent | Should -Match "CMD_MODE_TEST_SUCCESS"
        
        # Cleanup
        docker exec $Env:ImageName powershell "Remove-Item C:\cmdtest.txt -ErrorAction SilentlyContinue"
    }

    AfterAll {
        docker compose -f servercore2022/compose-cmdmode.yaml down;
    }
}
