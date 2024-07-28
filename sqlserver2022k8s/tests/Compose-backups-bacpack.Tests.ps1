Describe 'compose-backups.yaml' {
    BeforeAll {
        . ./../bootstraptest.ps1
        # Set environment variable for connection string
        $Env:connectionString = "Server=172.18.8.8;User Id=sa;Password=sapwd;";
        $Env:instanceName = "sqlserver2022k8s-mssql-1";
        New-Item -ItemType Directory -Path "$env:BUILD_TEMP\datavolume\data", "$env:BUILD_TEMP\datavolume\log", "$env:BUILD_TEMP\datavolume\backup", "$env:BUILD_TEMP\datavolume\bacpac\*" -Force
        Remove-Item -Path "$env:BUILD_TEMP\datavolume\data\*", "$env:BUILD_TEMP\datavolume\log\*", "$env:BUILD_TEMP\datavolume\backup\*", "$env:BUILD_TEMP\datavolume\bacpac\*" -Recurse -Force
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

    It 'SbsEnsureCredentialForSasUrl Works' {
        docker exec $Env:instanceName powershell "Import-Module Sbs; SbsEnsureCredentialForSasUrl -Url 'https://myaccount.blob.core.windows.net/pictures/profile.jpg?sv=2012-02-12&st=2009-02-09&se=2009-02-10&sr=c&sp=r&si=YWJjZGVmZw%3d%3d&sig=dD80ihBh5jfNpymO5Hg1IdiJIEvHcJpCMiCMnN%2fRnbI%3d' -SqlInstance 'localhost'"
        WaitForLog $Env:instanceName "Credential 'https://myaccount.blob.core.windows.net/pictures' upserted."
        Get-DbaCredential -SqlInstance $Env:connectionString -Credential "https://myaccount.blob.core.windows.net/pictures" | Should -Not -BeNullOrEmpty
    }

    It 'Can create a table in mytestdatabase' {
        $query = @"
CREATE TABLE TestTable (
    ID INT IDENTITY(1,1) NOT NULL,
    TestData NVARCHAR(255),
    CONSTRAINT PK_TestTable PRIMARY KEY CLUSTERED (ID)
)
"@
        Invoke-DbaQuery -SqlInstance $Env:connectionString -Database "mytestdatabase" -Query $query
        (Invoke-DbaQuery -SqlInstance $Env:connectionString -Database "mytestdatabase" -Query "SELECT OBJECT_ID('dbo.TestTable')").Column1 | Should -Not -BeNullOrEmpty
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
        $normalizedPath = "$env:BUILD_TEMP\datavolume\backup" -Replace "/", "\"
        $containerPath = $lastBackup.FullName.ToLower() -Replace [Regex]::Escape($normalizedPath), "d:\backup"

        # Restore from bacpac using SbsRestoreFull
        docker exec $Env:instanceName powershell "Import-Module Sbs;Import-Module dbatools;SbsRestoreFull -SqlInstance localhost -DatabaseName renamedDatabase2 -Path '$($containerPath)'"
        Get-DbaDatabase -SqlInstance $Env:connectionString -Database renamedDatabase2 | Should -Not -BeNullOrEmpty;
        WaitForLog $Env:instanceName "Restored database from" -extendedTimeout
        # Test that the database has the table we created before
        (Invoke-DbaQuery -SqlInstance $Env:connectionString -Database renamedDatabase2 -Query "SELECT OBJECT_ID('dbo.TestTable')").Column1 | Should -Not -BeNullOrEmpty
    }

    AfterAll {
        docker compose -f sqlserver2022k8s/compose-backups.yaml down;
        Remove-Item -Path "$env:BUILD_TEMP\datavolume\data\*", "$env:BUILD_TEMP\datavolume\log\*", "$env:BUILD_TEMP\datavolume\backup\*", "$env:BUILD_TEMP\datavolume\bacpac\*" -Recurse -Force
    }
}

