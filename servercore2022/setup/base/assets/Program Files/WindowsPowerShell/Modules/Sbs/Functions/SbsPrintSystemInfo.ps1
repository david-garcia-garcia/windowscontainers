
function SbsPrintSystemInfo {
    [OutputType([bool])]
    param (
    )

    $computerInfo = Get-WmiObject Win32_ComputerSystem | Select-Object NumberOfProcessors, NumberOfLogicalProcessors, Name, Manufacturer, Model, TotalPhysicalMemory;
    $cpuInfo = Get-WmiObject -Class Win32_Processor | Select-Object CurrentClockSpeed, MaxClockSpeed, Name;
    $memoryGb = [math]::round(($computerInfo.TotalPhysicalMemory / 1GB), 1);
    Write-Output "SystemInfo: NumberOfLogicalProcessors: $($computerInfo.NumberOfLogicalProcessors)";
    Write-Output "SystemInfo: NumberOfProcessors: $($computerInfo.NumberOfProcessors)";
    Write-Output "SystemInfo: System Memory: $($memoryGb)Gb";
    Write-Output "SystemInfo: CPU Clock Speed: $($cpuInfo.CurrentClockSpeed) of $($cpuInfo.MaxClockSpeed) Hz";
    Write-Output "SystemInfo: CPU Name: $($cpuInfo.Name)";
    Write-Output "SystemInfo: Computer Name: $($computerInfo.Name)"; 
    Write-Output "SystemInfo: Manufacturer: $($computerInfo.Manufacturer)";
    Write-Output "SystemInfo: Model: $($computerInfo.Model)";
}