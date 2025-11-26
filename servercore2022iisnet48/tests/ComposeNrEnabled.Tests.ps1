Describe 'compose-nr-enabled.yaml - IIS_RESTORE_SERVICE_ENV=true' {
    BeforeAll {
        . ./../bootstraptest.ps1
        docker compose -f servercore2022iisnet48/compose-nr-enabled.yaml up -d;
        WaitForLog "servercore2022iisnet48-web-1" "Initialization Completed" -extendedTimeout
    }

    It 'Responds on port 80 HTTP with 200 OK' {
        (Invoke-WebRequest 172.18.8.48 -UseBasicParsing).StatusCode | Should -Be "200";
    }

    It 'New Relic agent log file should be created when IIS_RESTORE_SERVICE_ENV=true' {
        # Make a few requests to trigger the New Relic agent
        1..5 | ForEach-Object {
            Invoke-WebRequest 172.18.8.48 -UseBasicParsing | Out-Null
            Start-Sleep -Milliseconds 500
        }
        
        # Give time for the New Relic agent to create log files
        Start-Sleep -Seconds 10
        
        # Check for New Relic agent log files matching pattern: newrelic_agent__LM_W3SVC_*_ROOT.log
        $logFiles = docker exec servercore2022iisnet48-web-1 powershell -Command "Get-ChildItem -Path 'C:\var\log\newrelic' -File -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name"
        
        # Filter for agent log files with the expected pattern (the number after W3SVC_ can vary)
        $agentLogs = $logFiles | Where-Object { $_ -match '^newrelic_agent__LM_W3SVC_\d+_ROOT\.log$' }
        
        $agentLogs | Should -Not -BeNullOrEmpty
        Write-Host "Found New Relic agent log file(s): $($agentLogs -join ', ')"
    }

    AfterAll {
        docker compose -f servercore2022iisnet48/compose-nr-enabled.yaml down;
    }
}

