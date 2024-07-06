Describe 'compose-basic.yaml' {
    BeforeAll {
        docker compose -f servercore2022/compose-basic.yaml up -d;
        WaitForLog "servercore2022-servercore-1" "Initialization Completed"
    }
        
    It 'Booted synchronously' {
        WaitForLog "servercore2022-servercore-1" "init scripts synchronously"
    }

    It 'LogRotate is enabled by default' {
        docker exec servercore2022-servercore-1 powershell "(Get-ScheduledTask LogRotate).Triggers[0].Enabled" | Should -Be "True"
    }

    It 'Timezone is default' {
        docker exec servercore2022-servercore-1 powershell "(Get-TimeZone).Id" | Should -Be "Romance Standard Time";
    }

    It 'sshd service is stopped' {
        docker exec servercore2022-servercore-1 powershell "(Get-Service -Name 'sshd').Status" | Should -Be "Stopped"
    }

    It 'sshd service is disabled' {
        docker exec servercore2022-servercore-1 powershell "(Get-Service -Name 'sshd').StartType" | Should -Be "Disabled"
    }

    It 'Shutdown not called twice' {
        docker exec servercore2022-servercore-1 powershell "powershell -File c:\entrypoint\shutdown.ps1"
        WaitForLog "servercore2022-servercore-1" "SHUTDOWN END"
        docker compose -f servercore2022/compose-basic.yaml stop;
        WaitForLog "servercore2022-servercore-1" "Integrated shutdown skipped"
    }

    AfterAll {
        docker compose -f servercore2022/compose-basic.yaml down;
    }
}

