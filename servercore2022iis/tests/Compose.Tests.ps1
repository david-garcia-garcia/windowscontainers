Describe 'compose.yaml' {
    BeforeAll {
        . ./../bootstraptest.ps1
        docker compose -f servercore2022iis/compose.yaml up -d;
        WaitForLog "servercore2022iis-web-1" "Initialization Completed"  -extendedTimeout
    }
    It 'Responds on port 80 HTTP' {
        (Invoke-WebRequest 172.18.8.8 -UseBasicParsing).RawContent | Should -Match "iisstart\.png";
    }

    It 'Responds on port 80 HTTP with 200 OK' {
        (Invoke-WebRequest 172.18.8.8 -UseBasicParsing).StatusCode | Should -Be "200";
    }

    AfterAll {
        docker compose -f servercore2022iis/compose.yaml down;
    }
}

