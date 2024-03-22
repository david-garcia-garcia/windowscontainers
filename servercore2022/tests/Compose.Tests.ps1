Describe 'compose.yaml' {
    BeforeAll {
        docker compose -f servercore2022/compose.yaml up -d;
        WaitForLog "servercore2022-servercore-1" "Initialization Completed"
    }

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

    It 'Env warm reload' {
        $jsonString = @{
            "SBS_TESTVALUE" = "value1"
        } | ConvertTo-Json

        # Create directory and set configmap
        docker exec servercore2022-servercore-1 powershell "New-Item -ItemType Directory -Force -Path 'C:\configmap'; Set-Content -Path 'C:\configmap\env.json' -Value '$jsonString'"

        # Force refresh
        docker exec servercore2022-servercore-1 powershell "Import-Module Sbs; SbsPrepareEnv;"

        docker exec servercore2022-servercore-1 powershell '$Env:SBS_TESTVALUE' | Should -Be "value1"
    }

    AfterAll {
        docker compose -f servercore2022/compose.yaml down;
    }
}

