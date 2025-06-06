$global:ErrorActionPreference = if ($null -ne $Env:SBS_ENTRYPOINTERRORACTION ) { $Env:SBS_ENTRYPOINTERRORACTION } else { 'Stop' }

# Check if WER should be enabled
$WER_ENABLE = SbsGetEnvBool "WER_ENABLE";

if ($true -eq $WER_ENABLE) {
    # WER Dump enable
    Enable-WindowsErrorReporting;
    
    # Get configurable WER parameters with defaults using Sbs utility functions
    $werDumpFolder = SbsGetEnvString -name "WER_DUMPFOLDER" -defaultValue $null;
    $werDumpCount = SbsGetEnvInt -name "WER_DUMPCOUNT" -defaultValue 4;
    $werDumpType = SbsGetEnvInt -name "WER_DUMPTYPE" -defaultValue 2;
    $werCustomDumpFlags = SbsGetEnvInt -name "WER_CUSTOMDUMPFLAGS" -defaultValue 0;
    
    # Validate and ensure dump folder is properly configured
    if ([string]::IsNullOrWhiteSpace($werDumpFolder) -or -not (Test-Path $werDumpFolder)) {
        SbsWriteWarning "WER_DUMPFOLDER not specified or does not exist.";
        return; 
    }
    
    # Configure WER registry settings
    $werDumpRegistryPath = "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps";
    if (-Not (Test-Path $werDumpRegistryPath)) { New-Item -Path $werDumpRegistryPath }
    Set-ItemProperty -Path $werDumpRegistryPath -Name DumpFolder -Value "$werDumpFolder" -Type String;
    Set-ItemProperty -Path $werDumpRegistryPath -Name DumpCount -Value $werDumpCount -Type DWord;
    Set-ItemProperty -Path $werDumpRegistryPath -Name DumpType -Value $werDumpType -Type DWord;
    Set-ItemProperty -Path $werDumpRegistryPath -Name CustomDumpFlags -Value $werCustomDumpFlags -Type DWord;
    
    SbsWriteDebug "Get-WindowsErrorReporting: $(Get-WindowsErrorReporting)";
    SbsWriteDebug "WER Dump Set Up with DumpFolder: $werDumpFolder, DumpCount: $werDumpCount, DumpType: $werDumpType, CustomDumpFlags: $werCustomDumpFlags";
    Get-Service WerSvc;
    Start-Service WerSvc;
}
else {
    SbsWriteDebug "WER configuration skipped (WER_ENABLE not set to true)";
}