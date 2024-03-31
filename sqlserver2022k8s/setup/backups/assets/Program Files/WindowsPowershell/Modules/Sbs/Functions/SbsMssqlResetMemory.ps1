function SbsMssqlResetMemory {

    Import-Module dbatools;

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

    SbsWriteHost "MSSQL Memory reset start";

    $sqlInstance = "localhost";
    $sqlServer = Connect-DbaInstance -SqlInstance $sqlInstance;

    $initialMemoryUsage = Get-MemoryUsage -SqlInstance $sqlServer

    # Get the current max server memory setting
    $currentMaxMemory = (Get-DbaMaxMemory -SqlInstance $sqlServer).MaxValue;
    $currentMinMemory = 512;

    $reducedMaxMemory = [Math]::Max(($currentMaxMemory * 0.75), $currentMinMemory);

    Set-DbaMaxMemory -SqlInstance $sqlServer -Max $reducedMaxMemory;

    # Output original and temporary max memory settings for verification
    SbsWriteHost "Original Max Memory: $currentMaxMemory MB"
    SbsWriteHost "Temporary Reduced Max Memory: $reducedMaxMemory MB"

    Write-Host "Waiting...";
    Start-Sleep -Seconds 30;
    $finalMemoryUsage = Get-MemoryUsage -SqlInstance $sqlServer;

    # Restore the original max server memory setting
    Set-DbaMaxMemory -SqlInstance $sqlServer -Max $currentMaxMemory;

    # Output memory usage before and after the change
    SbsWriteHost "Initial Memory Usage: $($initialMemoryUsage | Out-String)"
    SbsWriteHost "Final Memory Usage: $($finalMemoryUsage | Out-String)"
}