Describe 'compose-cmdmode-command.yaml' {
    BeforeAll {
        . ./../bootstraptest.ps1
        $Env:ImageName = "servercore2022-servercore-1"
    }

    It 'Container initializes and executes command' {
        docker compose -f servercore2022/compose-cmdmode-command.yaml up -d;
        WaitForLog $Env:ImageName "Initialization completed" -extendedTimeout
        # Verify the command output appears in logs (the echo command should output "CMD_MODE_COMMAND_TEST_SUCCESS")
        WaitForLog $Env:ImageName "CMD_MODE_COMMAND_TEST_SUCCESS" -extendedTimeout
    }

    It 'CmdMode is enabled' {
        WaitForLog $Env:ImageName "CmdMode enabled: Shutdown listeners disabled to reduce memory footprint"
    }

    It 'Command executed successfully and container exits' {
        # Wait for the container to exit after command execution
        WaitForContainerStatus $Env:ImageName "Exited" -extendedTimeout
        
        # Verify exit code is 0 (command executed successfully)
        $exitCode = docker inspect $Env:ImageName --format='{{.State.ExitCode}}'
        $exitCode | Should -Be "0"
    }

    AfterAll {
        docker compose -f servercore2022/compose-cmdmode-command.yaml down;
    }
}
