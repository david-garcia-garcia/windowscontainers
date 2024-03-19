BeforeAll {
    docker compose -f servercore2022/compose-basic.yaml up -d;
}
    
Describe 'Get-Planet' {
    It 'LogRotate is enabled by default' {
        docker exec servercore2022-servercore-1 powershell "(Get-ScheduledTask LogRotate).Triggers[0].Enabled" | Should -Be "True"
    }
}

AfterAll {
    docker compose -f servercore2022/compose-basic.yaml down;
}