Describe 'compose.yaml' {
    BeforeAll {
        . ./../bootstraptest.ps1
        New-Item -ItemType Directory -Path "$env:BUILD_TEMP\datavolume\data", "$env:BUILD_TEMP\datavolume\backup" -Force
        $Env:connectionString = "Server=172.18.8.8;User Id=sa;Password=sapwd;";
        docker compose -f sqlserver2022k8s/compose.yaml up -d;
        WaitForLog "sqlserver2022k8s-mssql-1" "Initialization Completed" -TimeoutSeconds 30
    }

    It 'Can connect to the SQL Server' {
        Connect-DbaInstance $Env:connectionString | Should -Not -BeNullOrEmpty;
    }

    It 'Can connect with monitoring user' {
        Connect-DbaInstance "Server=172.18.8.8;User Id=monitoring;Password=MyP@assword;" | Should -Not -BeNullOrEmpty;
    }

    It 'Can connect with full app user and create a table' {

        $instance = Connect-DbaInstance "Server=172.18.8.8;User Id=dbuser_full;Password=MyP@assword;";
        $instance | Should -Not -BeNullOrEmpty;

        $query = @"
CREATE TABLE dbo.TestTable (
    ID INT IDENTITY(1,1) NOT NULL,
    TestData NVARCHAR(255),
    CONSTRAINT PK_TestTable PRIMARY KEY CLUSTERED (ID)
)
"@
        Invoke-DbaQuery -SqlInstance $instance -Database mydatabase -Query $query -EnableException
        (Invoke-DbaQuery -SqlInstance $instance -Database mydatabase -Query "SELECT OBJECT_ID('dbo.TestTable')").Column1 | Should -Not -BeNullOrEmpty
    }

    It 'Can connect with readonly user' {
        Connect-DbaInstance "Server=172.18.8.8;User Id=dbuser_readonly;Password=MyP@assword;" | Should -Not -BeNullOrEmpty;
    }

    AfterAll {
        OutputLog "sqlserver2022k8s-mssql-1"
        docker compose -f sqlserver2022k8s/compose.yaml down;
        Remove-Item -Path "$env:BUILD_TEMP\datavolume\data\*", "$env:BUILD_TEMP\datavolume\backup\*" -Recurse -Force
    }
}

