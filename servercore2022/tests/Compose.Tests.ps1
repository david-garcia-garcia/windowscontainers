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

    It 'DPAPI encode/decode works' {
        docker exec servercore2022-servercore-1 powershell '$Env:SBS_TESTPROTECT_PROTECT' | Should -Be "supersecretekey"
        $encoded = docker exec servercore2022-servercore-1 powershell '$Env:SBS_TESTPROTECT'
        $encoded | Should -Not -Be "supersecretekey"
        $decoded = docker exec servercore2022-servercore-1 powershell 'Import-Module Sbs; return SbsDpapiDecode -EncodedValue $Env:SBS_TESTPROTECT';
        $decoded | Should -Be "supersecretekey"
    }

    It 'SSH Connection works' {
        Import-Module Posh-SSH
        # Define the SSH server details
        $serverIp = "172.18.8.8"
        $username = "localadmin"
        $password = "P@ssw0rd"

        # Create a PSCredential object
        $securePassword = ConvertTo-SecureString $password -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential($username, $securePassword)

        # Attempt to create a new SSH session with auto-accepted host key
        $sshSession = New-SSHSession -ComputerName $serverIp -Credential $credential -AcceptKey -ErrorAction SilentlyContinue
    
        # Assert that the session was created successfully
        $sshSession | Should -Not -BeNullOrEmpty

        # Close the session if it was created
        if ($sshSession) {
            Remove-SSHSession -SessionId $sshSession.SessionId
        }
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

    #It 'Can SSH to container' {
    #    docker exec servercore2022-servercore-1 powershell "Set-Service -Name sshd -StartupType Manual; Start-Service -Name sshd; net user localadmin ""@MyP@assw0rd"";"
    #    # Define the SSH parameters
    #    $Server = "172.18.8.8"
    #    $UserName = "localadmin"
    #    $Password = "@MyP@assw0rd" | ConvertTo-SecureString -AsPlainText -Force
    #    $Credential = New-Object System.Management.Automation.PSCredential ($UserName, $Password)
    #    Import-Module Posh-SSH
    #    # Create SSH session
    #    try {
    #        $Session = New-SSHSession -ComputerName $Server -Credential $Credential -AcceptKey
    #        Write-Host "SSH session created successfully."
    #    } catch {
    #        Write-Host "Failed to create SSH session: $_"
    #    }
    #}

    AfterAll {
        docker compose -f servercore2022/compose.yaml down;
    }
}

