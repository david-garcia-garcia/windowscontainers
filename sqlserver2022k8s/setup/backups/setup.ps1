$global:ErrorActionPreference = 'Stop'

Write-Host "`n---------------------------------------"
Write-Host " Registering Backup Scheduled Tasks"
Write-Host "-----------------------------------------`n"

Register-ScheduledTask -Xml (Get-Content "c:\setup\cron\MssqlDifferential.xml" -Raw) -TaskName "MssqlDifferential";
Register-ScheduledTask -Xml (Get-Content "c:\setup\cron\MssqlFull.xml" -Raw) -TaskName "MssqlFull";
Register-ScheduledTask -Xml (Get-Content "c:\setup\cron\MssqlLog.xml" -Raw) -TaskName "MssqlLog";
Register-ScheduledTask -Xml (Get-Content "c:\setup\cron\MssqlReleaseMemory.xml" -Raw) -TaskName "MssqlReleaseMemory";
Register-ScheduledTask -Xml (Get-Content "c:\setup\cron\MssqlSystem.xml" -Raw) -TaskName "MssqlSystem";
Register-ScheduledTask -Xml (Get-Content "c:\setup\cron\MssqlBackupLtsAzCopy.xml" -Raw) -TaskName "MssqlBackupLtsAzCopy";
Register-ScheduledTask -Xml (Get-Content "c:\setup\cron\MssqlCleanupBackups.xml" -Raw) -TaskName "MssqlCleanupBackups";

Write-Host "`n---------------------------------------"
Write-Host " Registering Backup Mssql Jobs"
Write-Host "-----------------------------------------`n"

Start-Service 'MSSQLSERVER';
$sqlInstance = Connect-DbaInstance "localhost";
Invoke-DbaQuery -SqlInstance $sqlInstance -File "c:\setup\mssqljobs\MssqlFull.sql" -EnableException;
Invoke-DbaQuery -SqlInstance $sqlInstance -File "c:\setup\mssqljobs\MssqlLog.sql" -EnableException;
Invoke-DbaQuery -SqlInstance $sqlInstance -File "c:\setup\mssqljobs\MssqlDifferential.sql" -EnableException;
Invoke-DbaQuery -SqlInstance $sqlInstance -File "c:\setup\mssqljobs\MssqlCleanupBackups.sql" -EnableException;

# Clean temp data
Get-ChildItem -Path $env:TEMP, 'C:\Windows\Temp' -Recurse | Remove-Item -Force -Recurse;
Remove-Item -Path "$env:TEMP\*" -Recurse -Force;
