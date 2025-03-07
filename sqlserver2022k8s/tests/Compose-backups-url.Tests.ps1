Describe 'compose-backupsurl.yaml' {
    BeforeAll {
        . ./../bootstraptest.ps1
        # Set environment variable for connection string
        $Env:connectionString = "Server=172.18.8.8;User Id=sa;Password=sapwd;Database=mytestdatabase;";
        $Env:instanceName = "sqlserver2022k8s-mssql-1";
        New-Item -ItemType Directory -Path "$env:BUILD_TEMP\datavolume\data", "$env:BUILD_TEMP\datavolume\log", "$env:BUILD_TEMP\datavolume\backup" -Force
        Remove-Item -Path "$env:BUILD_TEMP\datavolume\data\*", "$env:BUILD_TEMP\datavolume\log\*", "$env:BUILD_TEMP\datavolume\backup\*" -Recurse -Force
        $parsedUrl = SbsParseSasUrl -Url $Env:TESTS_SAS_URL
        if ($parsedUrl -eq $null) {
            throw "Invalid SAS URL: $Env:TESTS_SAS_URL"
        }
        azcopy remove ($parsedUrl.baseUrlWithPrefix + "/*" + $parsedUrl.query) --recursive
    }

    It 'SQL Server starts' {
        docker compose -f sqlserver2022k8s/compose-backupsurl.yaml up -d
        WaitForLog $Env:instanceName "Initialization Completed" -extendedTimeout
        WaitForLog $Env:instanceName "Credential 'https://.*' upserted"
        WaitForLog $Env:instanceName "Checking for backups in https://.*"
        # The remote storage has been emptied, so it won't be able to restore anything, which is expected.
        WaitForLog $Env:instanceName "Database mytestdatabase could not be restored. Either backup media is missing or something failed. Check the logs."
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

        docker compose -f sqlserver2022k8s/compose-backupsurl.yaml stop
        docker compose -f sqlserver2022k8s/compose-backupsurl.yaml down
    }

    It "Has exactly one .bak file in (recursive)" {
        # List the .bak files from the remote storage using azcopy
        $backupFilesList = & azcopy list $Env:TESTS_SAS_URL --output-type=json | ConvertFrom-Json
        $bakFiles = $backupFilesList.Where({ $_.MessageContent -like "*bak*" })
        $bakFiles.Count | Should -Be 1
    }

    It 'Backups are recovered' {
        # Start the container again
        docker compose -f sqlserver2022k8s/compose-backupsurl.yaml up -d
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
        docker compose -f sqlserver2022k8s/compose-backupsurl.yaml stop
        docker compose -f sqlserver2022k8s/compose-backupsurl.yaml down

        # This cycle adds an additional trn file
        docker compose -f sqlserver2022k8s/compose-backupsurl.yaml up -d
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

        docker compose -f sqlserver2022k8s/compose-backupsurl.yaml down
    }

    It "Has exactly two .trn files (recursive)" {
        # List the .bak files from the remote storage using azcopy
        $backupFilesList = & azcopy list $Env:TESTS_SAS_URL --output-type=json | ConvertFrom-Json
        $bakFiles = $backupFilesList.Where({ $_.MessageContent -like "*trn*" })
        $bakFiles.Count | Should -Be 2
    }

    It 'Information is recovered after several cycles of backups and restores' {
        docker compose -f sqlserver2022k8s/compose-backupsurl.yaml up -d
        WaitForLog $Env:instanceName "Initialization Completed" -extendedTimeout
        (Invoke-DbaQuery -SqlInstance $Env:connectionString -Database mytestdatabase -Query "SELECT TestData FROM dbo.TestTable WHERE ID = 1").TestData | Should -Be "New Record"
        (Invoke-DbaQuery -SqlInstance $Env:connectionString -Database mytestdatabase -Query "SELECT TestData FROM dbo.TestTable WHERE ID = 2").TestData | Should -Be "New Record 2"
        docker compose -f sqlserver2022k8s/compose-backupsurl.yaml down
    }

    It 'Can make a diff backup' {
        docker compose -f sqlserver2022k8s/compose-backupsurl.yaml up -d
        WaitForLog $Env:instanceName "Initialization Completed" -extendedTimeout
        docker exec $Env:instanceName powershell "SbsMssqlRunBackups DIFF";
        WaitForLog $Env:instanceName "backups finished" -extendedTimeout
        $backupFilesList = & azcopy list $Env:TESTS_SAS_URL --output-type=json | ConvertFrom-Json
        $bakFiles = $backupFilesList.Where({ $_.MessageContent -like "*bak*" })
        # We have the original full + one additional (diff)
        $bakFiles.Count | Should -Be 2
    }

    AfterAll {
        docker compose -f sqlserver2022k8s/compose-backups.yaml down;
        Remove-Item -Path "$env:BUILD_TEMP\datavolume\data\*", "$env:BUILD_TEMP\datavolume\log\*", "$env:BUILD_TEMP\datavolume\backup\*" -Recurse -Force
    }
}

