Describe 'compose-error.yaml' {
    BeforeAll {
        . ./../bootstraptest.ps1
        docker compose -f servercore2022/compose-error.yaml up -d;
    }
        
    It 'Error during async bootstrap correctly states file and line' {
        WaitForLog "servercore2022-servercore-1" "0000_TestError.ps1: line 4"
    }

    AfterAll {
        docker compose -f servercore2022/compose-error.yaml down;
    }
}

