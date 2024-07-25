Describe 'compose-backups.yaml' {
    BeforeAll {
        . ./../bootstraptest.ps1
        # Set environment variable for connection string
        $Env:connectionString = "Server=172.18.8.8;User Id=sa;Password=sapwd;Database=mytestdatabase;";
        $Env:instanceName = "sqlserver2022k8s-mssql-1";
        New-Item -ItemType Directory -Path "$env:BUILD_TEMP\datavolume\data", "$env:BUILD_TEMP\datavolume\log", "$env:BUILD_TEMP\datavolume\backup" -Force
        Remove-Item -Path "$env:BUILD_TEMP\datavolume\data\*", "$env:BUILD_TEMP\datavolume\log\*", "$env:BUILD_TEMP\datavolume\backup\*" -Recurse -Force
    }

    It 'SQL Server starts' {
        docker compose -f sqlserver2022k8s/compose-backups.yaml up -d
        WaitForLog $Env:instanceName "Initialization Completed" -extendedTimeout
    }

    It 'Can connect to the SQL Server' {
        Connect-DbaInstance $Env:connectionString | Should -Not -BeNullOrEmpty;
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
        docker exec $Env:instanceName "powershell" "c:\entrypoint\shutdown.ps1";
        WaitForLog $Env:instanceName "Performing shutdown backups" -extendedTimeout
        WaitForLog $Env:instanceName "Entry point SHUTDOWN END" -extendedTimeout

        docker compose -f sqlserver2022k8s/compose-backups.yaml stop
        docker compose -f sqlserver2022k8s/compose-backups.yaml down
    }

    It "Has exactly one .bak file in $env:BUILD_TEMP/datavolume/backups (recursive)" {
        # Because there is no backup history, we start with exactly one full backup file
        $backupFiles = Get-ChildItem -Path "$env:BUILD_TEMP\datavolume\backup" -Recurse -Filter "*.bak"
        $backupFiles.Count | Should -Be 1
    }

    It 'Backups are recovered' {
        # Start the container again
        docker compose -f sqlserver2022k8s/compose-backups.yaml up -d
        WaitForLog $Env:instanceName "Initialization Completed" -extendedTimeout

        (Invoke-DbaQuery -SqlInstance $Env:connectionString -Database mytestdatabase -Query "SELECT OBJECT_ID('dbo.TestTable')").Column1 | Should -Not -BeNullOrEmpty
            
        # Insert a record into TestTablef
        $insertQuery = @"
    INSERT INTO dbo.TestTable (TestData)
    VALUES ('New Record')
"@
        Invoke-DbaQuery -SqlInstance $Env:connectionString -Database mytestdatabase -Query $insertQuery
        (Invoke-DbaQuery -SqlInstance $Env:connectionString -Database mytestdatabase -Query "SELECT TestData FROM dbo.TestTable WHERE ID = 1").TestData | Should -Be "New Record"
    }

    It 'Tear down makes backups II' {
        # This shutdown adds 1 trn file
        docker exec $Env:instanceName "powershell" "c:\entrypoint\shutdown.ps1";
        WaitForLog $Env:instanceName "Performing shutdown backups" -extendedTimeout
        WaitForLog $Env:instanceName "Entry point SHUTDOWN END" -extendedTimeout
        docker compose -f sqlserver2022k8s/compose-backups.yaml stop
        docker compose -f sqlserver2022k8s/compose-backups.yaml down

        # This cycle adds an additional trn file
        docker compose -f sqlserver2022k8s/compose-backups.yaml up -d
        WaitForLog "sqlserver2022k8s-mssql-1" "Initialization Completed" -extendedTimeout

        $insertQuery = @"
        INSERT INTO dbo.TestTable (TestData)
        VALUES ('New Record 2')
"@

        Invoke-DbaQuery -SqlInstance $Env:connectionString -Database mytestdatabase -Query $insertQuery

        (Invoke-DbaQuery -SqlInstance $Env:connectionString -Database mytestdatabase -Query "SELECT TestData FROM dbo.TestTable WHERE ID = 1").TestData | Should -Be "New Record"
        (Invoke-DbaQuery -SqlInstance $Env:connectionString -Database mytestdatabase -Query "SELECT TestData FROM dbo.TestTable WHERE ID = 2").TestData | Should -Be "New Record 2"

        docker exec $Env:instanceName "powershell" "c:\entrypoint\shutdown.ps1";
        WaitForLog $Env:instanceName "Performing shutdown backups" -extendedTimeout
        WaitForLog $Env:instanceName "Entry point SHUTDOWN END" -extendedTimeout

        docker compose -f sqlserver2022k8s/compose-backups.yaml down
    }

    It "Has exactly two .trn files in $env:TEMP/datavolume/backups (recursive)" {
        # The second shutdown, there should be one .bak and one .trn file
        $backupFiles = Get-ChildItem -Path "$env:BUILD_TEMP\datavolume\backup" -Recurse -Filter "*.trn"
        $backupFiles.Count | Should -Be 2
    }

    It 'Information is recovered after several cycles of backups and restores' {
        docker compose -f sqlserver2022k8s/compose-backups.yaml up -d
        WaitForLog $Env:instanceName "Initialization Completed" -extendedTimeout
        (Invoke-DbaQuery -SqlInstance $Env:connectionString -Database mytestdatabase -Query "SELECT TestData FROM dbo.TestTable WHERE ID = 1").TestData | Should -Be "New Record"
        (Invoke-DbaQuery -SqlInstance $Env:connectionString -Database mytestdatabase -Query "SELECT TestData FROM dbo.TestTable WHERE ID = 2").TestData | Should -Be "New Record 2"
        docker compose -f sqlserver2022k8s/compose-backups.yaml down
    }

    It 'Can make a diff backup' {
        docker compose -f sqlserver2022k8s/compose-backups.yaml up -d
        WaitForLog $Env:instanceName "Initialization Completed" -extendedTimeout
        docker exec $Env:instanceName powershell "SbsMssqlRunBackups DIFF";
        WaitForLog $Env:instanceName "backups finished" -extendedTimeout
        $backupFiles = Get-ChildItem -Path "$env:BUILD_TEMP\datavolume\backup\mytestdatabase\DIFF" -Recurse -Filter "*.bak"
        $backupFiles.Count | Should -Be 1
    }

    AfterAll {
        docker compose -f sqlserver2022k8s/compose-backups.yaml down;
        Remove-Item -Path "$env:BUILD_TEMP\datavolume\data\*", "$env:BUILD_TEMP\datavolume\log\*", "$env:BUILD_TEMP\datavolume\backup\*" -Recurse -Force
    }
}

