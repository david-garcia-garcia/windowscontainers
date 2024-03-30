Describe 'compose-backups.yaml' {
    BeforeAll {
        # Set environment variable for connection string
        $Env:connectionString = "Server=172.18.8.8;User Id=sa;Password=sapwd;Database=mytestdatabase;";
        $Env:instanceName = "sqlserver2022k8s-mssql-1";
        New-Item -ItemType Directory -Path "c:\datavolume\data", "c:\datavolume\log", "c:\datavolume\backup" -Force
        Remove-Item -Path "c:\datavolume\data\*", "c:\datavolume\log\*", "c:\datavolume\backup\*" -Recurse -Force
        docker compose -f sqlserver2022k8s/compose-backups.yaml up -d
        WaitForLog "sqlserver2022k8s-mssql-1" "Initialization Completed" -TimeoutSeconds 15
    }

    It 'Can connect to the SQL Server' {
        Connect-DbaInstance $Env:connectionString | Should -Not -BeNullOrEmpty;
    }

    It 'Max Server Memory is what was configured' {
        (Test-DbaMaxMemory $Env:connectionString).MaxValue | Should -Be "300"
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

    It 'Tear down makes backups' {
        # Decommission the docker
        docker compose -f sqlserver2022k8s/compose-backups.yaml stop
        WaitForLog $Env:instanceName "Performing shutdown backups" -TimeoutSeconds 15;
        WaitForLog $Env:instanceName "Entry point SHUTDOWN END" -TimeoutSeconds 15;
        docker compose -f sqlserver2022k8s/compose-backups.yaml down
    }

    It 'Has exactly one .bak file in c:/datavolume/backups (recursive)' {
        # Because there is no backup history, we start with exactly one full backup file
        $backupFiles = Get-ChildItem -Path "c:\datavolume\backup" -Recurse -Filter "*.bak"
        $backupFiles.Count | Should -Be 1
    }

    It 'Backups are recovered' {
        # Start the container again
        docker compose -f sqlserver2022k8s/compose-backups.yaml up -d
        WaitForLog $Env:instanceName "Initialization Completed" -TimeoutSeconds 25;

        (Invoke-DbaQuery -SqlInstance $Env:connectionString -Database mytestdatabase -Query "SELECT OBJECT_ID('dbo.TestTable')").Column1 | Should -Not -BeNullOrEmpty
            
        # Insert a record into TestTablef
        $insertQuery = @"
    INSERT INTO dbo.TestTable (TestData)
    VALUES ('New Record')
"@
        Invoke-DbaQuery -SqlInstance $Env:connectionString -Database mytestdatabase -Query $insertQuery
        (Invoke-DbaQuery -SqlInstance $Env:connectionString -Database mytestdatabase -Query "SELECT TestData FROM dbo.TestTable WHERE ID = 1").TestData | Should -Be "New Record"
    }

    It 'Tear down makes backups' {
        # This shutdown adds 1 trn file
        docker compose -f sqlserver2022k8s/compose-backups.yaml stop
        WaitForLog $Env:instanceName "Performing shutdown backups" -TimeoutSeconds 15;
        WaitForLog $Env:instanceName "Entry point SHUTDOWN END" -TimeoutSeconds 15;
        docker compose -f sqlserver2022k8s/compose-backups.yaml down

        # This cycle adds an additional trn file
        docker compose -f sqlserver2022k8s/compose-backups.yaml up -d
        WaitForLog "sqlserver2022k8s-mssql-1" "Initialization Completed" -TimeoutSeconds 25;

        $insertQuery = @"
        INSERT INTO dbo.TestTable (TestData)
        VALUES ('New Record 2')
"@

        Invoke-DbaQuery -SqlInstance $Env:connectionString -Database mytestdatabase -Query $insertQuery

        (Invoke-DbaQuery -SqlInstance $Env:connectionString -Database mytestdatabase -Query "SELECT TestData FROM dbo.TestTable WHERE ID = 1").TestData | Should -Be "New Record"
        (Invoke-DbaQuery -SqlInstance $Env:connectionString -Database mytestdatabase -Query "SELECT TestData FROM dbo.TestTable WHERE ID = 2").TestData | Should -Be "New Record 2"

        docker compose -f sqlserver2022k8s/compose-backups.yaml stop
        WaitForLog $Env:instanceName "Performing shutdown backups" -TimeoutSeconds 15;
        WaitForLog $Env:instanceName "Entry point SHUTDOWN END" -TimeoutSeconds 15;
        docker compose -f sqlserver2022k8s/compose-backups.yaml down
    }

    It 'Has exactly two .trn files in c:/datavolume/backups (recursive)' {
        # The second shutdown, there should be one .bak and one .trn file
        $backupFiles = Get-ChildItem -Path "c:\datavolume\backup" -Recurse -Filter "*.trn"
        $backupFiles.Count | Should -Be 2
    }

    It 'Information is recovered after several cycles of backups and restores' {
        docker compose -f sqlserver2022k8s/compose-backups.yaml up -d
        WaitForLog $Env:instanceName "Initialization Completed" -TimeoutSeconds 25;
        (Invoke-DbaQuery -SqlInstance $Env:connectionString -Database mytestdatabase -Query "SELECT TestData FROM dbo.TestTable WHERE ID = 1").TestData | Should -Be "New Record"
        (Invoke-DbaQuery -SqlInstance $Env:connectionString -Database mytestdatabase -Query "SELECT TestData FROM dbo.TestTable WHERE ID = 2").TestData | Should -Be "New Record 2"
        docker compose -f sqlserver2022k8s/compose-backups.yaml down
    }

    It 'Can make a diff backup' {
        docker compose -f sqlserver2022k8s/compose-backups.yaml up -d
        WaitForLog $Env:instanceName "Initialization Completed" -TimeoutSeconds 25;
        docker exec $Env:instanceName powershell "SbsMssqlRunBackups DIFF";
        WaitForLog $Env:instanceName "Backup completed" -TimeoutSeconds 25;
        $backupFiles = Get-ChildItem -Path "c:\datavolume\backup\mytestdatabase\DIFF" -Recurse -Filter "*.bak"
        $backupFiles.Count | Should -Be 1
    }

    AfterAll {
        docker compose -f sqlserver2022k8s/compose-backups.yaml down;
        Remove-Item -Path "c:\datavolume\data\*", "c:\datavolume\log\*", "c:\datavolume\backup\*" -Recurse -Force
    }
}

