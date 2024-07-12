Describe 'compose.yaml' {
    BeforeAll {
        New-Item -ItemType Directory -Path "c:\datavolume\data", "c:\datavolume\backup", "c:\datavolume\control" -Force
        $Env:connectionString = "Server=172.18.8.8;User Id=sa;Password=sapwd;";
        docker compose -f sqlserver2022k8s/compose.yaml up -d;
        WaitForLog "sqlserver2022k8s-mssql-1" "Initialization Completed" -TimeoutSeconds 30
    }

    It 'Can connect to the SQL Server' {
        Connect-DbaInstance $Env:connectionString | Should -Not -BeNullOrEmpty;
    }

    It 'Can connect with application user' {
        Connect-DbaInstance "Server=172.18.8.8;User Id=monitoring;Password=MyP@assword;" | Should -Not -BeNullOrEmpty;
    }

    AfterAll {
        docker compose -f sqlserver2022k8s/compose.yaml down;
        Remove-Item -Path "c:\datavolume\data\*", "c:\datavolume\backup\*", "c:\datavolume\control\*" -Recurse -Force
    }
}

