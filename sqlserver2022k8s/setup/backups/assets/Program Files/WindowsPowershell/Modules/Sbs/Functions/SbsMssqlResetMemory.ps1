function SbsResetMemory {

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

    $sqlInstance = "localhost";
    $sqlServer = Connect-DbaInstance -SqlInstance $sqlInstance;

    $initialMemoryUsage = Get-MemoryUsage -SqlInstance $sqlServer

    # Get the current max server memory setting
    $currentMaxMemory = (Get-DbaMaxMemory -SqlInstance $sqlServer).MaxMemory;
    $currentMinMemory = (Get-DbaMaxMemory -SqlInstance $sqlServer).MinMemory;

    # Calculate 25% of the current max memory
    $reducedMaxMemory = [Math]::Max(($currentMaxMemory * 0.25), $currentMinMemory); # Assuming 1024MB as the minimum

    # Set the max server memory to 25% of its current value or the minimum value, whichever is more
    Set-DbaMaxMemory -SqlInstance $sqlServer -Max $reducedMaxMemory;

    Write-Host "Waiting...";
    Start-Sleep -Seconds 10;
    $finalMemoryUsage = Get-MemoryUsage -SqlInstance $sqlServer;

    # Restore the original max server memory setting
    Set-DbaMaxMemory -SqlInstance $sqlServer -Max $currentMaxMemory;

    # Output original and temporary max memory settings for verification
    Write-Host "Original Max Memory: $currentMaxMemory MB"
    Write-Host "Temporary Reduced Max Memory: $reducedMaxMemory MB"

    # Output memory usage before and after the change
    Write-Host "Initial Memory Usage: $($initialMemoryUsage | Out-String)"
    Write-Host "Final Memory Usage: $($finalMemoryUsage | Out-String)"
}