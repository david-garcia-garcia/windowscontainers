Describe 'compose.yaml' {
    BeforeAll {
        . ./../bootstraptest.ps1
        docker compose -f servercore2022iis/compose-certs.yaml up -d;
        WaitForLog "servercore2022iis-web-1" "Initialization Completed"
    }

    It 'HTTP Response OK with a hostname from SBS_IISBINDINGS' {
        (Invoke-WebRequest -Uri "http://172.18.8.8" -Headers @{"Host" = "anothername.com" }).RawContent | Should -Match "iisstart\.png";
    }

    It 'HTTP Response 404 with a hostname not explicitly registered' {
        Start-Sleep -Seconds 3;
        (Invoke-WebRequest -Uri "http://172.18.8.8" -Headers @{"Host" = "nohostname.com" } -SkipHttpErrorCheck).StatusCode | Should -Be "404";
    }

    It 'HTTPS SSL Certificate/s was provisioned OK and automatically bound to the site.' {
        Invoke-WebRequest -Uri "https://172.18.8.8" -Headers @{"Host" = "mywebsiste.com" } -SkipCertificateCheck;
        Invoke-WebRequest -Uri "https://172.18.8.8" -Headers @{"Host" = "www.mysiste.net" } -SkipCertificateCheck;
    }

    AfterAll {
        docker compose -f servercore2022iis/compose-certs.yaml down;
    }
}

