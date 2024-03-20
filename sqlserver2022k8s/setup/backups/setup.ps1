$global:ErrorActionPreference = 'Stop'

Write-Host "`n---------------------------------------"
Write-Host " Registering Backup Scheduled Tasks"
Write-Host "-----------------------------------------`n"

Register-ScheduledTask -Xml (Get-Content "c:\setup\cron\MssqlDifferential.xml" -Raw) -TaskName "MssqlDifferential";
Register-ScheduledTask -Xml (Get-Content "c:\setup\cron\MssqlFull.xml" -Raw) -TaskName "MssqlFull";
Register-ScheduledTask -Xml (Get-Content "c:\setup\cron\MssqlLog.xml" -Raw) -TaskName "MssqlLog";
Register-ScheduledTask -Xml (Get-Content "c:\setup\cron\MssqlReleaseMemory.xml" -Raw) -TaskName "MssqlReleaseMemory";
Register-ScheduledTask -Xml (Get-Content "c:\setup\cron\MssqlSystem.xml" -Raw) -TaskName "MssqlSystem";

# Clean temp data
Get-ChildItem -Path $env:TEMP, 'C:\Windows\Temp' -Recurse | Remove-Item -Force -Recurse;
Remove-Item -Path "$env:TEMP\*" -Recurse -Force;