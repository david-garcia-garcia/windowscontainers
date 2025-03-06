Describe 'compose.yaml' {
    BeforeAll {
        . ./../bootstraptest.ps1
        $Env:imageName = "servercore2022-servercore-1";
    }

    It 'Container starts' {
        docker compose -f servercore2022/compose-command.yaml up -d;
        WaitForLog $Env:imageName "Initialization Completed" -extendedTimeout
        WaitForLog $Env:imageName "this is an ad-hoc command" -extendedTimeout
    }

    AfterAll {
        docker compose -f servercore2022/compose-command.yaml down;
    }
}

