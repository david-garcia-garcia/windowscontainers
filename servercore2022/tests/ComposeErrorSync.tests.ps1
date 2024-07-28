Describe 'compose-error-sync.yaml' {
    BeforeAll {
        . ./../bootstraptest.ps1
        
    }
        
    #It 'Exception is handled' {
    #    try {
    #        throw [System.IO.FileNotFoundException] "Test exception."
    #    }
    #    catch {
    #        SbsWriteException $_;
    #    }
    #}

    It 'Error during async bootstrap correctly states file and line' {
        docker compose -f servercore2022/compose-error-sync.yaml up -d;
        WaitForLog "servercore2022-servercore-1" "0000_TestError.ps1: line 4"
    }

    AfterAll {
        docker compose -f servercore2022/compose-error-sync.yaml down;
    }
}
