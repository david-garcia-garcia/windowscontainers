$global:ErrorActionPreference = 'Stop'

Write-Host "`n---------------------------------------"
Write-Host " Registering Backup Scheduled Tasks"
Write-Host "-----------------------------------------`n"

$xmlFiles = Get-ChildItem -Path "c:\setup\cron" -Filter *.xml
foreach ($file in $xmlFiles) {
    $taskName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
    $xmlContent = Get-Content -Path $file.FullName -Raw
    Register-ScheduledTask -Xml $xmlContent -TaskName $taskName
}

Write-Host "`n---------------------------------------"
Write-Host " Registering Backup Mssql Jobs"
Write-Host "-----------------------------------------`n"

Start-Service 'MSSQLSERVER';
$sqlInstance = Connect-DbaInstance "localhost";

$sqlFiles = Get-ChildItem -Path "c:\setup\mssqljobs" -Filter *.sql
foreach ($file in $sqlFiles) {
    Invoke-DbaQuery -SqlInstance $sqlInstance -File $file -EnableException;
}

# Clean temp data
Get-ChildItem -Path $env:TEMP, 'C:\Windows\Temp' -Recurse | Remove-Item -Force -Recurse;
Remove-Item -Path "$env:TEMP\*" -Recurse -Force;
