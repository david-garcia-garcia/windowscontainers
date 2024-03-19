
    
Describe 'compose.yaml' {
    BeforeAll {
        docker compose -f servercore2022iis/compose.yaml up -d;
        WaitForLog "servercore2022iis-web-1" "Initialization Completed"
    }
    It 'Responds on port 80 HTTP' {
        (Invoke-WebRequest 172.18.8.8).RawContent | Should -Match "iisstart\.png";
    }

    It 'Responds on port 80 HTTP with 200 OK' {
        (Invoke-WebRequest 172.18.8.8).StatusCode | Should -Be "200";
    }

    AfterAll {
        docker compose -f servercore2022iis/compose.yaml down;
    }
}

