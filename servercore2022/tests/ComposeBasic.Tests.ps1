Describe 'compose-basic.yaml' {
    BeforeAll {
        . ./../bootstraptest.ps1
        $Env:ImageName = "servercore2022-servercore-1"
    }
        
    It 'Container initializes' {
        docker compose -f servercore2022/compose-basic.yaml up -d;
        WaitForLog $Env:ImageName "Initialization Completed"
    }

    It 'Booted synchronously' {
        WaitForLog $Env:ImageName "init scripts synchronously"
    }

    It 'LogRotate is enabled by default' {
        docker exec $Env:ImageName powershell "(Get-ScheduledTask LogRotate).Triggers[0].Enabled" | Should -Be "True"
    }

    It 'Timezone is set' {
        docker exec $Env:ImageName powershell "(Get-TimeZone).Id" | Should -Match "Alaskan Standard Time";
    }

    It 'sshd service is stopped' {
        docker exec $Env:ImageName powershell "(Get-Service -Name 'sshd').Status" | Should -Be "Stopped"
    }

    It 'sshd service is disabled' {
        docker exec $Env:ImageName powershell "(Get-Service -Name 'sshd').StartType" | Should -Be "Disabled"
    }

    It 'Shutdown not called twice' {
        docker exec $Env:ImageName powershell "powershell -File c:\entrypoint\shutdown.ps1"
        WaitForLog $Env:ImageName "SHUTDOWN END" -timeoutSeconds 40
        docker compose -f servercore2022/compose-basic.yaml stop;
        WaitForLog $Env:ImageName "Integrated shutdown skipped"
    }

    AfterAll {
        docker compose -f servercore2022/compose-basic.yaml down;
    }
}

