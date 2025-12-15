Describe 'compose-cmdmode-command.yaml' {
    BeforeAll {
        . ./../bootstraptest.ps1
        $Env:ImageName = "servercore2022-servercore-1"
    }

    It 'Container initializes and executes command' {
        docker compose -f servercore2022/compose-cmdmode-command.yaml up -d;
        WaitForLog $Env:ImageName "Initialization completed" -extendedTimeout
    }

    It 'CmdMode is enabled' {
        WaitForLog $Env:ImageName "CmdMode enabled: Shutdown listeners disabled to reduce memory footprint"
    }

    It 'Command executed successfully and container exits' {
        # Wait for the command to execute and container to exit
        Start-Sleep -Seconds 10
        
        # Check that container has exited (status should show "Exited")
        $containerStatus = docker ps -a --filter "name=$Env:ImageName" --format "{{.Status}}"
        $containerStatus | Should -Match "Exited"
        
        # Verify exit code is 0 (command executed successfully)
        $exitCode = docker inspect $Env:ImageName --format='{{.State.ExitCode}}'
        $exitCode | Should -Be "0"
    }

    AfterAll {
        docker compose -f servercore2022/compose-cmdmode-command.yaml down;
    }
}
