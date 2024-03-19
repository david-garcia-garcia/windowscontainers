$global:ErrorActionPreference = 'Stop'

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;

Write-Host "`n---------------------------------------"
Write-Host " Installing Log-Rotate (https://github.com/theohbrothers/Log-Rotate)"
Write-Host "-----------------------------------------`n"

$testCommand = Get-Command -Name Log-Rotate -ErrorAction SilentlyContinue;
if(-not($testCommand)){
  Install-Module -Name Log-Rotate -Force -Repository PSGallery -Scope AllUsers;
}

Write-Host "`n---------------------------------------"
Write-Host " Registering log rotate scheduled task"
Write-Host "-----------------------------------------`n"

Register-ScheduledTask -Xml (Get-Content "c:\setup\cron\LogRotate.xml" -Raw) -TaskName "LogRotate";

Get-ChildItem -Path $env:TEMP, 'C:\Windows\Temp' -Recurse | Remove-Item -Force -Recurse;
Remove-Item -Path "$env:TEMP\*" -Recurse -Force;
