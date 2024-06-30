Describe 'compose-backups.yaml' {
    BeforeAll {
        # Set environment variable for connection string
        $Env:connectionString = "Server=172.18.8.8;User Id=sa;Password=sapwd;Database=mytestdatabase;";
        $Env:instanceName = "sqlserver2022k8s-mssql-1";
        New-Item -ItemType Directory -Path "c:\datavolume\data", "c:\datavolume\log", "c:\datavolume\backup" -Force
        Remove-Item -Path "c:\datavolume\data\*", "c:\datavolume\log\*", "c:\datavolume\backup\*" -Recurse -Force
        docker compose -f sqlserver2022k8s/compose-backups.yaml up -d
        WaitForLog "sqlserver2022k8s-mssql-1" "Initialization Completed" -TimeoutSeconds 30
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

    It 'Make bacpac from image and restore with SbsRestoreFull' {
        # SqlPackage should work from within the image itself
        docker exec $Env:instanceName powershell "SqlPackage /Action:Export /SourceConnectionString:'Server=localhost;Initial Catalog=mytestdatabase;TrustServerCertificate=True;Trusted_Connection=True;' /TargetFile:'d:\\export.bacpac'"
        Test-Path "c:\\datavolume\\export.bacpac" | Should -Be $true;

        # Restore from bacpac using SbsRestoreFull
        docker exec $Env:instanceName powershell "Import-Module Sbs;Import-Module dbatools;SbsRestoreFull -SqlInstance localhost -DatabaseName renamedDatabase -Path 'd:\\export.bacpac'"
        Get-DbaDatabase -SqlInstance $Env:connectionString -Database renamedDatabase | Should -Not -BeNullOrEmpty;

        # Test that the database has the table we created before
        (Invoke-DbaQuery -SqlInstance $Env:connectionString -Database renamedDatabase -Query "SELECT OBJECT_ID('dbo.TestTable')").Column1 | Should -Not -BeNullOrEmpty
    }

    It 'SbsMssqlRunBackups FULL and restore SbsRestoreFull from .bak' {
        # SqlPackage should work from within the image itself
        docker exec $Env:instanceName powershell "Import-Module Sbs;SbsMssqlRunBackups -backupType FULL -sqlInstance localhost";
        
        $lastBackup = Get-ChildItem -Path "c:\datavolume\backup" -Recurse -Filter "*.bak" | 
              Sort-Object LastWriteTime -Descending | 
              Select-Object -First 1

        $lastBackup | Shoule -Not -BeNullOrEmpty

        # Database has been deleted
        Remove-DbaDatabase -SqlInstance $Env:connectionString -Database mytestdatabase -EnableException;
        Get-DbaDatabase -SqlInstance $Env:connectionString -Database mytestdatabase | Should -Be $null;

        # Restore from bacpac using SbsRestoreFull
        docker exec $Env:instanceName powershell "Import-Module Sbs;Import-Module dbatools;SbsRestoreFull -SqlInstance localhost -DatabaseName renamedDatabase2 -Path \"$($lastBackup)\""
        Get-DbaDatabase -SqlInstance $Env:connectionString -Database renamedDatabase2 | Should -Not -BeNullOrEmpty;

        # Test that the database has the table we created before
        (Invoke-DbaQuery -SqlInstance $Env:connectionString -Database renamedDatabase2 -Query "SELECT OBJECT_ID('dbo.TestTable')").Column1 | Should -Not -BeNullOrEmpty
    }

    AfterAll {
        docker compose -f sqlserver2022k8s/compose-backups.yaml down;
        Remove-Item -Path "c:\datavolume\data\*", "c:\datavolume\log\*", "c:\datavolume\backup\*" -Recurse -Force
    }
}

