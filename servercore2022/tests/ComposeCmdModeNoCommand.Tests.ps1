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
        # Wait for the container to exit
        WaitForContainerStatus $Env:ImageName "Exited" -extendedTimeout
        
        # Verify exit code is 0 (successful)
        $exitCode = docker inspect $Env:ImageName --format='{{.State.ExitCode}}'
        $exitCode | Should -Be "0"
    }

    AfterAll {
        docker compose -f servercore2022/compose-cmdmode-no-command.yaml down;
    }
}
