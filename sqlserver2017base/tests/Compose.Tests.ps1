Describe 'compose.yaml' {
    BeforeAll {
        . ./../bootstraptest.ps1
        New-Item -ItemType Directory -Path "$env:BUILD_TEMP\datavolume\data", "$env:BUILD_TEMP\datavolume\backup", "$env:BUILD_TEMP\datavolume\log" -Force
        Remove-Item -Path "$env:BUILD_TEMP\datavolume\data\*", "$env:BUILD_TEMP\datavolume\log\*", "$env:BUILD_TEMP\datavolume\backup\*" -Recurse -Force
        $Env:connectionString = "Server=172.18.8.8;User Id=sa;Password=sapwd;";
        $Env:containerName = "sqlserver2017base-mssql-1"
    }

    It 'Server starts' {
        docker compose -f sqlserver2017base/compose.yaml up -d;
        WaitForLog $Env:containerName "Initialization Completed" -extendedTimeout
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
        docker compose -f sqlserver2017base/compose.yaml down;
        Remove-Item -Path "$env:BUILD_TEMP\datavolume\data\*", "$env:BUILD_TEMP\datavolume\backup\*", "$env:BUILD_TEMP\datavolume\log\*" -Recurse -Force
    }
}

