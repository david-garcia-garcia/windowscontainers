function SbsMssqlResetMemory {

    param(
        [Parameter(Mandatory = $true)]
        [int]$reduceTo
    )
    
    Import-Module dbatools;
    Set-DbatoolsConfig -FullName sql.connection.trustcert -Value $true -Register
	Set-DbatoolsConfig -FullName sql.connection.encrypt -Value $false -Register

    # Function to get memory usage
    function Get-MemoryUsage {
        param ($SqlInstance)
        $query = @"
SELECT 
    total_physical_memory_kb / 1024.0 AS TotalPhysicalMemoryMB,
    available_physical_memory_kb / 1024.0 AS AvailablePhysicalMemoryMB,
    total_page_file_kb / 1024.0 AS TotalPageFileMB,
    available_page_file_kb / 1024.0 AS AvailablePageFileMB,
    system_memory_state_desc
FROM sys.dm_os_sys_memory
"@
        return Invoke-DbaQuery -SqlInstance $SqlInstance -Query $query;
    }

    SbsWriteHost "MSSQL Memory reset start requested temporary constraint to $($reduceTo)Mb";

    $sqlInstance = "localhost";
    $sqlServer = Connect-DbaInstance -SqlInstance $sqlInstance;

    $initialMemoryUsage = Get-MemoryUsage -SqlInstance $sqlServer

    # Get the current max server memory setting
    $currentMaxMemory = (Get-DbaMaxMemory -SqlInstance $sqlServer).MaxValue;

    if ($reduceTo -gt $currentMaxMemory) {
        SbsWriteWarning "Memory reduction requested $($reduceTo) is greater than currently max memory of $($currentMaxMemory). No operation will be performed.";
        return;
    }

    Set-DbaMaxMemory -SqlInstance $sqlServer -Max $reduceTo;

    # Output original and temporary max memory settings for verification
    SbsWriteHost "Original Max Memory: $currentMaxMemory MB"
    SbsWriteHost "Temporary Reduced Max Memory: $reduceTo MB"

    Write-Host "Waiting...";
    Start-Sleep -Seconds 30;
    $finalMemoryUsage = Get-MemoryUsage -SqlInstance $sqlServer;

    # Restore the original max server memory setting
    Set-DbaMaxMemory -SqlInstance $sqlServer -Max $currentMaxMemory;

    # Output memory usage before and after the change
    SbsWriteHost "Initial Memory Usage: $($initialMemoryUsage | Out-String)"
    SbsWriteHost "Final Memory Usage: $($finalMemoryUsage | Out-String)"
}