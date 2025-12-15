Describe 'compose-cmdmode-no-command.yaml' {
    BeforeAll {
        . ./../bootstraptest.ps1
        $Env:ImageName = "servercore2022-servercore-1"
    }

    It 'Container initializes' {
        docker compose -f servercore2022/compose-cmdmode-no-command.yaml up -d;
        WaitForLog $Env:ImageName "Initialization completed" -extendedTimeout
    }

    It 'CmdMode is enabled' {
        WaitForLog $Env:ImageName "CmdMode enabled: Shutdown listeners disabled to reduce memory footprint"
    }

    It 'CmdMode skips main service loop' {
        WaitForLog $Env:ImageName "CmdMode enabled: Main service loop skipped. Process will be held by CMD entrypoint"
    }

    It 'Container exits when no command is provided' {
        # In CmdMode, container should exit after initialization if no command is provided
        # Wait for initialization to complete and container to exit
        Start-Sleep -Seconds 10
        
        # Check that container has exited (status should show "Exited")
        $containerStatus = docker ps -a --filter "name=$Env:ImageName" --format "{{.Status}}"
        $containerStatus | Should -Match "Exited"
        
        # Verify exit code is 0 (successful)
        $exitCode = docker inspect $Env:ImageName --format='{{.State.ExitCode}}'
        $exitCode | Should -Be "0"
    }

    AfterAll {
        docker compose -f servercore2022/compose-cmdmode-no-command.yaml down;
    }
}
