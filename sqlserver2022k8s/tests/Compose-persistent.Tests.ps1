Describe 'compose-persistent.yaml' {
    BeforeAll {
        . ./../bootstraptest.ps1
        # Set environment variable for connection string
        $Env:connectionString = "Server=172.18.8.8;User Id=sa;Password=sapwd;";
        $Env:instanceName = "sqlserver2022k8s-mssql-1";
        New-Item -ItemType Directory -Path "$env:BUILD_TEMP\datavolume\data", "$env:BUILD_TEMP\datavolume\log", "$env:BUILD_TEMP\datavolume\backup", "$env:BUILD_TEMP\datavolume\system", "$env:BUILD_TEMP\datavolume\temp" -Force
        Remove-Item -Path "$env:BUILD_TEMP\datavolume\data\*", "$env:BUILD_TEMP\datavolume\log\*", "$env:BUILD_TEMP\datavolume\backup\*", "$env:BUILD_TEMP\datavolume\system\*", "$env:BUILD_TEMP\datavolume\temp\*" -Recurse -Force
        docker compose -f sqlserver2022k8s/compose-persistent.yaml up -d
        WaitForLog "sqlserver2022k8s-mssql-1" "Initialization Completed" -TimeoutSeconds 20
    }

    It 'Can connect to the SQL Server' {
        Connect-DbaInstance $Env:connectionString | Should -Not -BeNullOrEmpty;
    }

    It 'Ensure exists' {
        (Get-DbaDatabase -SqlInstance $Env:connectionString -Database mytestdatabase).Name | Should -BeNullOrEmpty
        New-DbaDatabase -SqlInstance $Env:connectionString -Name mytestdatabase
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

    It 'Can tear down' {
        docker compose -f sqlserver2022k8s/compose-persistent.yaml down;
    }

    It 'Can start' {
        docker compose -f sqlserver2022k8s/compose-persistent.yaml up -d;
        WaitForLog $Env:instanceName "Initialization Completed" -TimeoutSeconds 25;
    }

    It 'State is preserved' {
        (Invoke-DbaQuery -SqlInstance $Env:connectionString -Database mytestdatabase -Query "SELECT OBJECT_ID('dbo.TestTable')").Column1 | Should -Not -BeNullOrEmpty
            
        $insertQuery = @"
    INSERT INTO dbo.TestTable (TestData)
    VALUES ('New Record')
"@
        Invoke-DbaQuery -SqlInstance $Env:connectionString -Database mytestdatabase -Query $insertQuery
        (Invoke-DbaQuery -SqlInstance $Env:connectionString -Database mytestdatabase -Query "SELECT TestData FROM dbo.TestTable WHERE ID = 1").TestData | Should -Be "New Record"
    }

    It 'Tear down works' {
        # This shutdown adds 1 trn file
        docker compose -f sqlserver2022k8s/compose-persistent.yaml stop
        WaitForLog $Env:instanceName "Entry point SHUTDOWN END" -TimeoutSeconds 15;
        docker compose -f sqlserver2022k8s/compose-persistent.yaml down

        # This cycle adds an additional trn file
        docker compose -f sqlserver2022k8s/compose-persistent.yaml up -d
        WaitForLog "sqlserver2022k8s-mssql-1" "Initialization Completed" -TimeoutSeconds 25;

        $insertQuery = @"
        INSERT INTO dbo.TestTable (TestData)
        VALUES ('New Record 2')
"@

        Invoke-DbaQuery -SqlInstance $Env:connectionString -Database mytestdatabase -Query $insertQuery

        (Invoke-DbaQuery -SqlInstance $Env:connectionString -Database mytestdatabase -Query "SELECT TestData FROM dbo.TestTable WHERE ID = 1").TestData | Should -Be "New Record"
        (Invoke-DbaQuery -SqlInstance $Env:connectionString -Database mytestdatabase -Query "SELECT TestData FROM dbo.TestTable WHERE ID = 2").TestData | Should -Be "New Record 2"

        docker compose -f sqlserver2022k8s/compose-persistent.yaml stop
        WaitForLog $Env:instanceName "Entry point SHUTDOWN END" -TimeoutSeconds 15;
        docker compose -f sqlserver2022k8s/compose-persistent.yaml down
    }

    It 'Information is recovered after several cycles of backups and restores' {
        docker compose -f sqlserver2022k8s/compose-persistent.yaml up -d
        WaitForLog $Env:instanceName "Initialization Completed" -TimeoutSeconds 25;
        (Invoke-DbaQuery -SqlInstance $Env:connectionString -Database mytestdatabase -Query "SELECT TestData FROM dbo.TestTable WHERE ID = 1").TestData | Should -Be "New Record"
        (Invoke-DbaQuery -SqlInstance $Env:connectionString -Database mytestdatabase -Query "SELECT TestData FROM dbo.TestTable WHERE ID = 2").TestData | Should -Be "New Record 2"
        docker compose -f sqlserver2022k8s/compose-persistent.yaml down
    }

    AfterAll {
        docker compose -f sqlserver2022k8s/compose-persistent.yaml down;
        Remove-Item -Path "$env:BUILD_TEMP\datavolume\data\*", "$env:BUILD_TEMP\datavolume\log\*", "$env:BUILD_TEMP\datavolume\backup\*", "$env:BUILD_TEMP\datavolume\system\*" -Recurse -Force
    }
}

