Describe 'compose.yaml' {
    BeforeAll {
        . ./../bootstraptest.ps1
        $Env:imageName = "servercore2022-servercore-1";
    }

    It 'Container starts' {
        docker compose -f servercore2022/compose.yaml up -d;
        WaitForLog $Env:imageName "Initialization Completed" -extendedTimeout
    }

    It 'LogRotate runs at 5AM Daily' {
        docker exec $Env:imageName powershell "(Get-ScheduledTask LogRotate).Triggers[0].DaysInterval" | Should -Be "1";
        docker exec $Env:imageName powershell "[DateTime]::Parse((Get-ScheduledTask LogRotate).Triggers[0].StartBoundary).ToLocalTime().ToString('s')" | Should -Be "2023-01-01T05:00:00";
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
        # Define the SSH server details
        $serverIp = "172.18.8.8"
        $username = "localadmin"
        $password = "P@ssw0rd"

        # Create a PSCredential object
        $securePassword = ConvertTo-SecureString $password -AsPlainText -Force
        $credential = New-Object System.Management.Automation.PSCredential($username, $securePassword)

        # Attempt to create a new SSH session with auto-accepted host key
        $sshSession = New-SSHSession -ComputerName $serverIp -Credential $credential -AcceptKey -Force
    
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
            $Session = New-SSHSession -ComputerName $Server -Credential $Credential -AcceptKey
            Write-Host "SSH session created successfully."
        }
        catch {
            Write-Host "Failed to create SSH session: $_"
        }
    }

    It 'WER crash dump is generated on stack overflow' {
        # Check if WER dump folder exists
        $dumpFolderExists = docker exec $Env:imageName powershell "Test-Path 'C:\CrashDumps'"
        $dumpFolderExists | Should -Be "True"
        
        # Count existing dump files before crash
        $initialDumpCount = docker exec $Env:imageName powershell "(Get-ChildItem 'C:\CrashDumps' -Filter '*.dmp' -ErrorAction SilentlyContinue | Measure-Object).Count"
        
        # Create a PowerShell script that will cause stack overflow through infinite recursion
        $crashScript = @'
function InfiniteRecursion {
    param($depth = 0)
    Write-Host "Recursion depth: $depth"
    InfiniteRecursion -depth ($depth + 1)
}
InfiniteRecursion
'@
        
        # Execute the crash script in a separate PowerShell process to avoid affecting the test
        # Use Start-Process with -Wait to ensure we capture the crash
        docker exec $Env:imageName powershell "
            `$crashScript = @'
$crashScript
'@
            `$crashScript | Out-File -FilePath 'C:\temp\crashtest.ps1' -Encoding UTF8
            try {
                Start-Process -FilePath 'powershell.exe' -ArgumentList '-File C:\temp\crashtest.ps1' -Wait -WindowStyle Hidden
            } catch {
                Write-Host 'Process crashed as expected'
            }
        "
        
        # Wait for WER to process the crash and create the dump (with timeout)
        $timeout = 15 # seconds
        $elapsed = 0
        $checkInterval = 1 # second
        $finalDumpCount = $initialDumpCount
        
        do {
            Start-Sleep -Seconds $checkInterval
            $elapsed += $checkInterval
            $finalDumpCount = docker exec $Env:imageName powershell "(Get-ChildItem 'C:\CrashDumps' -Filter '*.dmp' -ErrorAction SilentlyContinue | Measure-Object).Count"
            Write-Host "Checking for dump files... Current count: $finalDumpCount, Initial: $initialDumpCount, Elapsed: ${elapsed}s"
        } while (([int]$finalDumpCount -eq [int]$initialDumpCount) -and ($elapsed -lt $timeout))
        
        # Verify that at least one new dump file was created
        [int]$finalDumpCount | Should -BeGreaterThan ([int]$initialDumpCount)
        
        # Clean up the test script
        docker exec $Env:imageName powershell "Remove-Item 'C:\temp\crashtest.ps1' -ErrorAction SilentlyContinue"
    }

    AfterAll {
        docker compose -f servercore2022/compose.yaml down;
    }
}

