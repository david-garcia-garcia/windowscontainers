Describe 'compose.yaml' {
    BeforeAll {
        . ./../bootstraptest.ps1
        New-Item -ItemType Directory -Path "$env:BUILD_TEMP\datavolume\data", "$env:BUILD_TEMP\datavolume\backup", "$env:BUILD_TEMP\temp" -Force
        Remove-Item -Path "$env:BUILD_TEMP\datavolume\data\*", "$env:BUILD_TEMP\datavolume\log\*", "$env:BUILD_TEMP\datavolume\backup\*" -Recurse -Force
        $Env:connectionString = "Server=172.18.8.8;User Id=sa;Password=sapwd;";
        $Env:containerName = "sqlserver2022base-mssql-1"
        docker compose -f sqlserver2022base/compose.yaml up -d;
        WaitForLog $Env:containerName "Initialization Completed" -TimeoutSeconds 30
    }

    It 'Can connect to the SQL Server' {
        Connect-DbaInstance $Env:connectionString | Should -Not -BeNullOrEmpty;
    }

    It 'Servername has been changed' {
        $instance = Connect-DbaInstance $Env:connectionString;
        $instance | Should -Not -BeNullOrEmpty;
        $serverName = Invoke-DbaQuery -SqlInstance $instance -Query "SELECT @@servername AS ServerName";
        $serverName.ServerName | Should -Be "MYSERVERNAME";
    }

    AfterAll {
        docker compose -f sqlserver2022base/compose.yaml down;
        Remove-Item -Path "$env:BUILD_TEMP\datavolume\data\*", "$env:BUILD_TEMP\datavolume\backup\*" -Recurse -Force
    }
}

