Describe 'compose-backups.yaml' {
    BeforeAll {
        . ./../bootstraptest.ps1
        # Set environment variable for connection string
        $Env:connectionString = "Server=172.18.8.8;User Id=sa;Password=sapwd;";
        $Env:instanceName = "sqlserver2022k8s-mssql-1";
        New-Item -ItemType Directory -Path "$env:BUILD_TEMP\datavolume\data", "$env:BUILD_TEMP\datavolume\log", "$env:BUILD_TEMP\datavolume\backup", "$env:BUILD_TEMP\datavolume\bacpac\*" -Force
        Remove-Item -Path "$env:BUILD_TEMP\datavolume\data\*", "$env:BUILD_TEMP\datavolume\log\*", "$env:BUILD_TEMP\datavolume\backup\*", "$env:BUILD_TEMP\datavolume\bacpac\*" -Recurse -Force
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

    It 'Make bacpac from database' {
        # SqlPackage should work from within the image itself
        New-Item -ItemType "Directory" -Path "$env:BUILD_TEMP\\datavolume\\bacpac\\" -Force
        docker exec $Env:instanceName powershell "SqlPackage /Action:Export /SourceConnectionString:'Server=localhost;Initial Catalog=mytestdatabase;TrustServerCertificate=True;Trusted_Connection=True;' /TargetFile:'d:\\bacpac\\export.bacpac'"
        Test-Path "$env:BUILD_TEMP\\datavolume\\bacpac\\export.bacpac" | Should -Be $true;
    }
    
    It 'Restore bacpac with SbsRestoreFull' {
        # Restore from bacpac using SbsRestoreFull
        docker exec $Env:instanceName powershell "Import-Module Sbs;Import-Module dbatools;SbsRestoreFull -SqlInstance localhost -DatabaseName restoreBackpack -Path 'd:\\bacpac\\export.bacpac'"
        Get-DbaDatabase -SqlInstance $Env:connectionString -Database restoreBackpack | Should -Not -BeNullOrEmpty;

        # Test that the database has the table we created before
        (Invoke-DbaQuery -SqlInstance $Env:connectionString -Database restoreBackpack -Query "SELECT OBJECT_ID('dbo.TestTable')").Column1 | Should -Not -BeNullOrEmpty
    }

    It 'Restore archived bacpac with SbsRestoreFull' {
        # Restore from bacpac using SbsRestoreFull
        Compress-Archive -Path "$env:BUILD_TEMP\\datavolume\\bacpac\\*" -DestinationPath "$env:BUILD_TEMP\\datavolume\\bacpac\\bacpac.zip"
        docker exec $Env:instanceName powershell "Import-Module Sbs;Import-Module dbatools;SbsRestoreFull -SqlInstance localhost -DatabaseName restoreArchivedBackpack -Path 'd:\\bacpac\\bacpac.zip'"
        Get-DbaDatabase -SqlInstance $Env:connectionString -Database restoreArchivedBackpack | Should -Not -BeNullOrEmpty;

        # Test that the database has the table we created before
        (Invoke-DbaQuery -SqlInstance $Env:connectionString -Database restoreArchivedBackpack -Query "SELECT OBJECT_ID('dbo.TestTable')").Column1 | Should -Not -BeNullOrEmpty
    }

    It 'SbsMssqlRunBackups FULL and restore SbsRestoreFull from .bak' {
        # SqlPackage should work from within the image itself
        docker exec $Env:instanceName powershell "Import-Module Sbs;SbsMssqlRunBackups -backupType FULL -sqlInstance localhost";
        
        $lastBackup = Get-ChildItem -Path "$env:BUILD_TEMP\datavolume\backup" -Recurse -Filter "*.bak" | 
              Sort-Object LastWriteTime -Descending | 
              Select-Object -First 1

        $lastBackup | Should -Not -BeNullOrEmpty

        # Database has been deleted
        Remove-DbaDatabase -SqlInstance $Env:connectionString -Database mytestdatabase -EnableException -Confirm:$false
        Get-DbaDatabase -SqlInstance $Env:connectionString -Database mytestdatabase | Should -Be $null;

        $containerPath = $lastBackup.FullName.ToLower() -Replace [Regex]::Escape("$env:BUILD_TEMP\datavolume\backup"), "d:\backup"

        # Restore from bacpac using SbsRestoreFull
        docker exec $Env:instanceName powershell "Import-Module Sbs;Import-Module dbatools;SbsRestoreFull -SqlInstance localhost -DatabaseName renamedDatabase2 -Path '$($containerPath)'"
        Get-DbaDatabase -SqlInstance $Env:connectionString -Database renamedDatabase2 | Should -Not -BeNullOrEmpty;

        # Test that the database has the table we created before
        (Invoke-DbaQuery -SqlInstance $Env:connectionString -Database renamedDatabase2 -Query "SELECT OBJECT_ID('dbo.TestTable')").Column1 | Should -Not -BeNullOrEmpty
    }

    AfterAll {
        OutputLog "sqlserver2022k8s-mssql-1"
        docker compose -f sqlserver2022k8s/compose-backups.yaml down;
        Remove-Item -Path "$env:BUILD_TEMP\datavolume\data\*", "$env:BUILD_TEMP\datavolume\log\*", "$env:BUILD_TEMP\datavolume\backup\*", "$env:BUILD_TEMP\datavolume\bacpac\*" -Recurse -Force
    }
}

