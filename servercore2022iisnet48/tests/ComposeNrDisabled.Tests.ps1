Describe 'compose-nr-disabled.yaml - IIS_RESTORE_SERVICE_ENV=false' {
    BeforeAll {
        . ./../bootstraptest.ps1
        docker compose -f servercore2022iisnet48/compose-nr-disabled.yaml up -d;
        WaitForLog "servercore2022iisnet48-web-1" "Initialization Completed" -extendedTimeout
    }

    It 'Responds on port 80 HTTP with 200 OK' {
        (Invoke-WebRequest 172.18.8.48 -UseBasicParsing).StatusCode | Should -Be "200";
    }

    It 'New Relic log folder should be empty when IIS_RESTORE_SERVICE_ENV=false' {
        # Make a few requests to ensure IIS has processed something
        1..3 | ForEach-Object {
            Invoke-WebRequest 172.18.8.48 -UseBasicParsing | Out-Null
            Start-Sleep -Milliseconds 500
        }
        
        # Give some time for any potential log files to be created
        Start-Sleep -Seconds 5
        
        # Check that the newrelic log folder is empty (no agent logs created)
        $logFiles = docker exec servercore2022iisnet48-web-1 powershell -Command "Get-ChildItem -Path 'C:\var\log\newrelic' -File -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name"
        
        # Filter for agent log files (newrelic_agent_*.log pattern)
        $agentLogs = $logFiles | Where-Object { $_ -match '^newrelic_agent_' }
        
        $agentLogs | Should -BeNullOrEmpty
    }

    AfterAll {
        docker compose -f servercore2022iisnet48/compose-nr-disabled.yaml down;
    }
}

