BeforeAll {
    docker compose -f servercore2022/compose-basic.yaml up -d;
    WaitForLog "servercore2022-servercore-1" "Initialization Completed"
}
    
Describe 'compose-basic.yaml' {

    It 'LogRotate is enabled by default' {
        docker exec servercore2022-servercore-1 powershell "(Get-ScheduledTask LogRotate).Triggers[0].Enabled" | Should -Be "True"
    }

    It 'Timezone is default' {
        docker exec servercore2022-servercore-1 powershell "(Get-TimeZone).Id" | Should -Be "Romance Standard Time";
    }

    It 'new-relic service is stopped' {
        docker exec servercore2022-servercore-1 powershell "(Get-Service -Name 'newrelic-infra').Status" | Should -Be "Stopped"
    }

    It 'new-relic service is disabled' {
        docker exec servercore2022-servercore-1 powershell "(Get-Service -Name 'newrelic-infra').StartType" | Should -Be "Disabled"
    }
}

AfterAll {
    docker compose -f servercore2022/compose-basic.yaml down;
}