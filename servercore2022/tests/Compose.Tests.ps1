BeforeAll {
    docker compose -f servercore2022/compose.yaml up -d;
    WaitForLog "servercore2022-servercore-1" "Initialization Completed"
}
    
Describe 'compose.yaml' {
    It 'LogRotate runs at 5AM Daily' {
        docker exec servercore2022-servercore-1 powershell "(Get-ScheduledTask LogRotate).Triggers[0].DaysInterval" | Should -Be "1";
        docker exec servercore2022-servercore-1 powershell "[DateTime]::Parse((Get-ScheduledTask LogRotate).Triggers[0].StartBoundary).ToLocalTime().ToString('s')" | Should -Be "2023-01-01T05:00:00";
    }

    It 'Env variable is protected' {
        $sbsTestProtect = docker exec servercore2022-servercore-1 powershell '$Env:SBS_TESTPROTECT';
        $sbsTestProtectProtected = docker exec servercore2022-servercore-1 powershell '$Env:SBS_TESTPROTECT_PROTECTED';
        $sbsTestProtect | Should -Not -Be $sbsTestProtectProtected;
        $sbsTestProtectProtected | Should -Be -Empty;
    }

    It 'Timezone is set' {
        docker exec servercore2022-servercore-1 powershell "(Get-TimeZone).Id" | Should -Be "Pacific Standard Time";
    }

    It 'new-relic service is started' {
        docker exec servercore2022-servercore-1 powershell "(Get-Service -Name 'newrelic-infra').Status" | Should -Be "Running"
    }

    It 'new-relic service has automatic startup' {
        docker exec servercore2022-servercore-1 powershell "(Get-Service -Name 'newrelic-infra').StartType" | Should -Be "Automatic"
    }
}

AfterAll {
    docker compose -f servercore2022/compose.yaml down;
}