Describe 'compose-jobs.yaml' {
    BeforeAll {
        . ./../bootstraptest.ps1
        # Set environment variable for connection string
        $Env:connectionString = "Server=172.18.8.8;User Id=sa;Password=sapwd;Database=mytestdatabase;";
        $Env:instanceName = "sqlserver2022k8s-mssql-1";
        New-Item -ItemType Directory -Path "$env:BUILD_TEMP\datavolume\data", "$env:BUILD_TEMP\datavolume\log", "$env:BUILD_TEMP\datavolume\backup" -Force
        Remove-Item -Path "$env:BUILD_TEMP\datavolume\data\*", "$env:BUILD_TEMP\datavolume\log\*", "$env:BUILD_TEMP\datavolume\backup\*" -Recurse -Force
    }

    It 'SQL Server starts' {
        docker compose -f sqlserver2022k8s/compose-jobs.yaml up -d
        WaitForLog $Env:instanceName "Initialization Completed" -extendedTimeout
    }

    It 'Can connect to the SQL Server' {
        Connect-DbaInstance $Env:connectionString | Should -Not -BeNullOrEmpty;
    }

    It 'SQL Server agent is enabled' {
        docker exec $Env:instanceName powershell '(Get-Service "SQLSERVERAGENT").status' | Should -Be "Running"
    }

    It 'Database exists' {
        (Get-DbaDatabase -SqlInstance $Env:connectionString -Database mytestdatabase).Name | Should -Be "mytestdatabase"
    }

    It 'Full backup job scheduled' {
        $job = (Get-DbaAgentJob -SqlInstance $Env:connectionString -Job "MssqlBackup - FULL");
        $job.HasSchedule | Should -Be $true;
        $job.Enabled | Should -Be $true;
    }

    It 'Diff backup job scheduled' {
        $job = (Get-DbaAgentJob -SqlInstance $Env:connectionString -Job "MssqlBackup - DIFF");
        $job.HasSchedule | Should -Be $true;
        $job.Enabled | Should -Be $true;
    }

    It 'Log backup job scheduled' {
        $job = (Get-DbaAgentJob -SqlInstance $Env:connectionString -Job "MssqlBackup - LOG");
        $job.HasSchedule | Should -Be $true;
        $job.Enabled | Should -Be $true;
    }

    It 'Index Optimize job scheduled' {
        $job = (Get-DbaAgentJob -SqlInstance $Env:connectionString -Job "MSSQL Index Optimize");
        $job.HasSchedule | Should -Be $true;
        $job.Enabled | Should -Be $true;
    }

    It 'Index Optimize works' {
        Start-DbaAgentJob -SqlInstance $Env:connectionString -Job "MSSQL Index Optimize" -Wait -EnableException
        WaitForLog $Env:instanceName "Starting IndexOptimize for 'jobstestserver'"
        WaitForLog $Env:instanceName "Finished IndexOptimize for mytestdatabase"
        WaitForLog $Env:instanceName "IndexOptimize finished"
    }

    It 'Release memory job scheduled' {
        $job = (Get-DbaAgentJob -SqlInstance $Env:connectionString -Job "Mssql - Reset memory");
        $job.HasSchedule | Should -Be $true;
        $job.Enabled | Should -Be $true;
    }

    It 'Release memory works' {
        Start-DbaAgentJob -SqlInstance $Env:connectionString -Job "Mssql - Reset memory" -Wait -EnableException
        WaitForLog $Env:instanceName "Temporary Reduced Max Memory: 275 MB"
        WaitForLog $Env:instanceName "Initial Memory Usage" -extendedTimeout
        WaitForLog $Env:instanceName "Final Memory Usage"
    }

    AfterAll {
        docker compose -f sqlserver2022k8s/compose-jobs.yaml down;
        Remove-Item -Path "$env:BUILD_TEMP\datavolume\data\*", "$env:BUILD_TEMP\datavolume\log\*", "$env:BUILD_TEMP\datavolume\backup\*" -Recurse -Force
    }
}

