Describe 'compose-backups.yaml' {
    BeforeAll {
        # Set environment variable for connection string
        $Env:connectionString = "Server=172.18.8.8;User Id=sa;Password=sapwd;";
        New-Item -ItemType Directory -Path "c:\datavolume\data", "c:\datavolume\log" -Force
        Remove-Item -Path "c:\datavolume\data\*", "c:\datavolume\log\*" -Recurse -Force
        docker compose -f sqlserver2022k8s/compose-backups.yaml up -d
        WaitForLog "sqlserver2022k8s-mssql-1" "Initialization Completed" -TimeoutSeconds 15
    }

    It 'Can connect to the SQL Server' {
        Connect-DbaInstance $Env:connectionString | Should -Not -BeNullOrEmpty;
    }

    It 'Max Server Memory is what configured' {
        (Test-DbaMaxMemory $Env:connectionString).MaxValue | Should -Be "2048"
    }

    It 'Database exists' {
        (Get-DbaDatabase -SqlInstance $Env:connectionString -Database mytestdatabase).Name | Should -Be "mytestdatabase"
    }

    It 'Can create a table in mytestdatabase' {
        $query = @"
CREATE TABLE dbo.TestTable (
    ID INT IDENTITY(1,1) NOT NULL,
    TestData NVARCHAR(255),
    CONSTRAINT PK_TestTable PRIMARY KEY CLUSTERED (ID)
)
"@
        Invoke-DbaQuery -SqlInstance $Env:connectionString -Database mytestdatabase -Query $query
        (Invoke-DbaQuery -SqlInstance $Env:connectionString -Database mytestdatabase -Query "SELECT OBJECT_ID('dbo.TestTable')").Column1 | Should -Not -BeNullOrEmpty
    }

    It 'Recomoposing the container restores the database' {
        # Decommission the docker
        docker compose -f sqlserver2022k8s/compose-backups.yaml down

        # Delete contents in c:\datavolume\data and c:\datavolume\log
        Remove-Item -Path "c:\datavolume\data\*", "c:\datavolume\log\*" -Recurse -Force

        # Start the container again
        docker compose -f sqlserver2022k8s/compose-backups.yaml up -d

        # Wait for SQL Server to initialize again
        WaitForLog "sqlserver2022k8s-mssql-1" "Initialization Completed" -TimeoutSeconds 15


            (Invoke-DbaQuery -SqlInstance $Env:connectionString -Database mytestdatabase -Query "SELECT OBJECT_ID('dbo.TestTable')").Column1 | Should -Not -BeNullOrEmpty

    }

    AfterAll {
        docker compose -f sqlserver2022k8s/compose-backups.yaml down;
        Remove-Item -Path "c:\datavolume\data\*", "c:\datavolume\log\*" -Recurse -Force
    }
}

