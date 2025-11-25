Describe 'compose.yaml' {
    BeforeAll {
        . ./../bootstraptest.ps1
        $Env:imageName = "servercore2022-servercore-1";
        
        # Centralized SSH connection details
        $script:sshServerIp = "172.18.8.8"
        $script:sshUsername = "localadmin"
        $script:sshPassword = "P@ssw0rd"
    }

    BeforeEach {
        # Reset SSH service state and localadmin password to expected values before each test
        # This ensures tests don't depend on each other's state
        # Only run if container exists (skip for "Container starts" test)
        $containerExists = docker ps -a --filter "name=$Env:imageName" --format "{{.Names}}" 2>&1
        if ($containerExists -and $containerExists -notmatch "No such container") {
            docker exec $Env:imageName powershell @"
                Set-Service -Name sshd -StartupType Automatic -ErrorAction SilentlyContinue;
                Start-Service -Name sshd -ErrorAction SilentlyContinue;
                Enable-LocalUser -Name '$script:sshUsername' -ErrorAction SilentlyContinue;
                net user $script:sshUsername $script:sshPassword
"@ | Out-Null
        }
    }

    It 'Container starts' {
        docker compose -f servercore2022/compose.yaml up -d;
        WaitForLog $Env:imageName "Initialization Completed" -extendedTimeout
    }

    It 'LogRotate runs at 5AM Daily' {
        docker exec $Env:imageName powershell "(Get-ScheduledTask LogRotate).Triggers[0].DaysInterval" | Should -Be "1";
        docker exec $Env:imageName powershell "[DateTime]::Parse((Get-ScheduledTask LogRotate).Triggers[0].StartBoundary).ToLocalTime().ToString('s')" | Should -Be "2023-01-01T05:00:00";
    }

    It 'LogRotate task is enabled when SBS_CRON_LogRotate is set' {
        $taskState = docker exec $Env:imageName powershell "(Get-ScheduledTask LogRotate).State";
        $taskState | Should -Be "Ready";
        $taskEnabled = docker exec $Env:imageName powershell "(Get-ScheduledTask LogRotate).Settings.Enabled";
        $taskEnabled | Should -Be "True";
    }

    It 'Env variable is protected' {
        $sbsTestProtect = docker exec $Env:imageName powershell '$Env:SBS_TESTPROTECT';
        $sbsTestProtectProtected = docker exec $Env:imageName powershell '$Env:SBS_TESTPROTECT_PROTECTED';
        $sbsTestProtect | Should -Not -Be $sbsTestProtectProtected;
        $sbsTestProtectProtected | Should -Be -Empty;
    }

    It 'Timezone is set' {
        docker exec $Env:imageName powershell "(Get-TimeZone).Id" | Should -Be "Pacific Standard Time";
    }

    It 'sshd service is started' {
        docker exec $Env:imageName powershell "(Get-Service -Name 'sshd').Status" | Should -Be "Running"
    }

    It 'sshd service has automatic startup' {
        docker exec $Env:imageName powershell "(Get-Service -Name 'sshd').StartType" | Should -Be "Automatic"
    }

    It 'DPAPI encode/decode works' {
        docker exec $Env:imageName powershell '$Env:SBS_TESTPROTECT_PROTECT' | Should -Be "supersecretekey"
        $encoded = docker exec $Env:imageName powershell '$Env:SBS_TESTPROTECT'
        $encoded | Should -Not -Be "supersecretekey"
        $decoded = docker exec $Env:imageName powershell 'Import-Module Sbs; return SbsDpapiDecode -EncodedValue $Env:SBS_TESTPROTECT';
        $decoded | Should -Be "supersecretekey"
    }

    It 'SSH Connection works' {
        Import-Module Posh-SSH
        # Create a PSCredential object
        $securePassword = ConvertTo-SecureString $script:sshPassword -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential($script:sshUsername, $securePassword)

        # Attempt to create a new SSH session with auto-accepted host key
        $sshSession = New-SSHSession -ComputerName $script:sshServerIp -Credential $credential -AcceptKey -Force
    
        # Assert that the session was created successfully
        $sshSession | Should -Not -BeNullOrEmpty

        # Close the session if it was created
        if ($sshSession) {
            Remove-SSHSession -SessionId $sshSession.SessionId
        }
        
        # Verify that SSH successful login logs appear in container logs
        Start-Sleep -Seconds 2  # Give LogMonitor time to process events
        $containerLogs = docker logs $Env:imageName --tail 500 2>&1
        $successfulLoginLogs = $containerLogs | Select-String -Pattern "Accepted password|Accepted publickey|Accepted keyboard-interactive|successful logon" -CaseSensitive:$false
        $successfulLoginLogs | Should -Not -BeNullOrEmpty -Because "SSH successful login logs should appear in container logs via LogMonitor"
    }

    It 'SFTP Connection works' {
        # Verify sshd_config file exists
        $sshdConfigExists = docker exec $Env:imageName powershell "Test-Path 'C:\ProgramData\ssh\sshd_config'"
        $sshdConfigExists | Should -Be "True"

        Import-Module Posh-SSH
        # Create a PSCredential object
        $securePassword = ConvertTo-SecureString $script:sshPassword -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential($script:sshUsername, $securePassword)

        # Create an SFTP session
        $sftpSession = New-SFTPSession -ComputerName $script:sshServerIp -Credential $credential -AcceptKey -Force
    
        # Assert that the session was created successfully
        $sftpSession | Should -Not -BeNullOrEmpty

        # Test SFTP functionality by listing a directory
        $files = Get-SFTPChildItem -SFTPSession $sftpSession -Path '/'
        $files | Should -Not -BeNullOrEmpty

        # Test file upload/download
        $testContent = "SFTP Test Content"
        $localTestFile = Join-Path $env:TEMP "sftp_test.txt"
        $remoteDirectory = "/C:"
        $remoteFileName = "sftp_test.txt"
        $remoteTestFileSFTP = "$remoteDirectory/$remoteFileName"
        $remoteTestFileLocal = "C:/$remoteFileName"
        
        # Create local test file
        Set-Content -Path $localTestFile -Value $testContent
        
        # Upload file via SFTP (Destination is the remote directory, Path is the local file)
        Set-SFTPItem -Session $sftpSession.SessionId -Destination $remoteDirectory -Path $localTestFile -Force
        
        # Verify file exists in container (Test-Path uses Windows path format without leading slash)
        $fileExists = docker exec $Env:imageName powershell "Test-Path '$remoteTestFileLocal'"
        $fileExists | Should -Be "True"
        
        # Verify file content in container
        $remoteContentArray = docker exec $Env:imageName powershell "Get-Content '$remoteTestFileLocal' -Raw"
        $remoteContent = if ($remoteContentArray -is [Array]) { $remoteContentArray -join "`n" } else { $remoteContentArray }
        $remoteContent.Trim() | Should -Be $testContent
        
        # Clean up remote file
        Remove-SFTPItem -SFTPSession $sftpSession -Path $remoteTestFileSFTP
        
        # Clean up local file
        Remove-Item -Path $localTestFile -ErrorAction SilentlyContinue

        # Close the SFTP session
        if ($sftpSession) {
            Remove-SFTPSession -SessionId $sftpSession.SessionId
        }
        
        # Verify that SSH/SFTP connection logs appear in container logs
        Start-Sleep -Seconds 2  # Give LogMonitor time to process events
        $containerLogs = docker logs $Env:imageName --tail 500 2>&1
        $connectionLogs = $containerLogs | Select-String -Pattern "Accepted password|Accepted publickey|Connection from|SFTP|sftp-server" -CaseSensitive:$false
        $connectionLogs | Should -Not -BeNullOrEmpty -Because "SSH/SFTP connection logs should appear in container logs via LogMonitor"
    }

    It 'Env warm reload' {
        $jsonString = @{
            "SBS_TESTVALUE" = "value1"
            "SBS_OVERRIDE"  = "originalValue"
        } | ConvertTo-Json

        # Create directory and set environment
        docker exec $Env:imageName powershell "New-Item -ItemType Directory -Force -Path 'C:\environment.d'; Set-Content -Path 'C:\environment.d\env0.json' -Value '$jsonString'"

        WaitForLog $Env:imageName "Configuration change count 1"

        $jsonString2 = @{
            "SBS_TESTVALUE2" = "value2"
            "SBS_OVERRIDE"   = "overridenValue"
        } | ConvertTo-Json

        # Create directory and set environment
        docker exec $Env:imageName powershell "New-Item -ItemType Directory -Force -Path 'C:\environment.d'; Set-Content -Path 'C:\environment.d\env1.json' -Value '$jsonString2'"

        # Refresh should happen automatically, wait for it
        WaitForLog $Env:imageName "Configuration change count 2"

        docker exec $Env:imageName powershell '$Env:SBS_TESTVALUE' | Should -Be "value1"
        docker exec $Env:imageName powershell '$Env:SBS_TESTVALUE2' | Should -Be "value2"
        docker exec $Env:imageName powershell '$Env:SBS_OVERRIDE' | Should -Be "overridenValue"

        # Add a secret
        docker exec $Env:imageName powershell "New-Item -ItemType Directory -Force -Path 'C:\secrets.d\mysecret'; Set-Content -Path 'C:\secrets.d\mysecret\SBS_MYSECRETNAME' -NoNewline -Value 'mysecretvalue1'"
        WaitForLog $Env:imageName "Configuration change count 3"

        docker exec $Env:imageName powershell '$Env:SBS_MYSECRETNAME' | Should -Be "mysecretvalue1"
    }

    It 'Can SSH to container' {
        docker exec $Env:imageName powershell "Set-Service -Name sshd -StartupType Manual; Start-Service -Name sshd; net user localadmin ""@MyP@assw0rd"";"
        # Define the SSH parameters
        $Server = "172.18.8.8"
        $UserName = "localadmin"
        $Password = "@MyP@assw0rd" | ConvertTo-SecureString -AsPlainText -Force
        $Credential = New-Object System.Management.Automation.PSCredential ($UserName, $Password)
        Import-Module Posh-SSH
        # Create SSH session
        try {
            $Session = New-SSHSession -ComputerName $Server -Credential $Credential -AcceptKey -Force
            Write-Host "SSH session created successfully."
            
            # Close the session if it was created
            if ($Session) {
                Remove-SSHSession -SessionId $Session.SessionId
            }
        }
        catch {
            Write-Host "Failed to create SSH session: $_"
            throw
        }
    }

    It 'SSH successful login logs appear in container logs via LogMonitor' {
        Import-Module Posh-SSH
        # Get initial log count to verify new logs are generated
        $initialLogs = docker logs $Env:imageName --tail 1000 2>&1
        $initialSuccessfulLoginCount = ($initialLogs | Select-String -Pattern "Accepted password|Accepted publickey|Accepted keyboard-interactive|successful logon" -CaseSensitive:$false).Count

        # Create a PSCredential object
        $securePassword = ConvertTo-SecureString $script:sshPassword -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential($script:sshUsername, $securePassword)

        # Create an SSH session to generate logs
        try {
            $sshSession = New-SSHSession -ComputerName $script:sshServerIp -Credential $credential -AcceptKey -Force -ErrorAction Stop
    
            # Assert that the session was created successfully
            $sshSession | Should -Not -BeNullOrEmpty
        }
        catch {
            Write-Host "Failed to create SSH session: $_"
            throw
        }

        # Close the session
        if ($sshSession) {
            Remove-SSHSession -SessionId $sshSession.SessionId
        }
        
        # Wait for LogMonitor to process events
        Start-Sleep -Seconds 3
        
        # Verify that successful login logs appear in container logs
        $containerLogs = docker logs $Env:imageName --tail 1000 2>&1
        $successfulLoginLogs = $containerLogs | Select-String -Pattern "Accepted password|Accepted publickey|Accepted keyboard-interactive|successful logon" -CaseSensitive:$false
        
        # Verify successful login logs were found
        $successfulLoginLogs | Should -Not -BeNullOrEmpty -Because "SSH successful login logs (Accepted password/publickey) should appear in container logs via LogMonitor"
        
        # Verify that new successful login logs were generated
        $finalSuccessfulLoginCount = ($containerLogs | Select-String -Pattern "Accepted password|Accepted publickey|Accepted keyboard-interactive|successful logon" -CaseSensitive:$false).Count
        $finalSuccessfulLoginCount | Should -BeGreaterThan $initialSuccessfulLoginCount -Because "New SSH successful login logs should have been generated"
    }

    It 'SSH failed login logs appear in container logs via LogMonitor' {
        Import-Module Posh-SSH
        # Get initial log count to verify new logs are generated
        $initialLogs = docker logs $Env:imageName --tail 1000 2>&1
        $initialFailedLoginCount = ($initialLogs | Select-String -Pattern "Failed password|Invalid user|Authentication failed|failed logon" -CaseSensitive:$false).Count

        # Create a PSCredential object with wrong password to generate failed login logs
        $wrongPassword = ConvertTo-SecureString "WrongPassword123!" -AsPlainText -Force
        $wrongCredential = New-Object System.Management.Automation.PSCredential($script:sshUsername, $wrongPassword)

        # Attempt to create an SSH session with wrong password (this should fail)
        try {
            $sshSession = New-SSHSession -ComputerName $script:sshServerIp -Credential $wrongCredential -AcceptKey -Force -ErrorAction Stop
            # If we get here, the connection succeeded (unexpected), close it
            if ($sshSession) {
                Remove-SSHSession -SessionId $sshSession.SessionId
            }
        }
        catch {
            # Expected failure - this will generate failed login logs
            Write-Host "Expected SSH connection failure with wrong password: $_"
        }
        
        # Wait for LogMonitor to process events
        Start-Sleep -Seconds 3
        
        # Verify that failed login logs appear in container logs
        $containerLogs = docker logs $Env:imageName --tail 1000 2>&1
        $failedLoginLogs = $containerLogs | Select-String -Pattern "Failed password|Invalid user|Authentication failed|failed logon" -CaseSensitive:$false
        
        # Verify failed login logs were found
        $failedLoginLogs | Should -Not -BeNullOrEmpty -Because "SSH failed login logs (Failed password/Authentication failed) should appear in container logs via LogMonitor"
        
        # Verify that new failed login logs were generated
        $finalFailedLoginCount = ($containerLogs | Select-String -Pattern "Failed password|Invalid user|Authentication failed|failed logon" -CaseSensitive:$false).Count
        $finalFailedLoginCount | Should -BeGreaterThan $initialFailedLoginCount -Because "New SSH failed login logs should have been generated"
    }

    AfterAll {
        docker compose -f servercore2022/compose.yaml down;
    }
}

