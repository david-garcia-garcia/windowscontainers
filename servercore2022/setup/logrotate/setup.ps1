$global:ErrorActionPreference = 'Stop'

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;

Write-Host "`n---------------------------------------"
Write-Host " Installing Log-Rotate (https://github.com/theohbrothers/Log-Rotate)"
Write-Host "-----------------------------------------`n"

$maxRetries = 5
$retryCount = 0
$retryDelaySeconds = 5
$installSuccess = $false

while ($retryCount -lt $maxRetries -and -not $installSuccess) {
    try {
        Install-Module -Name Log-Rotate -Force -Repository PSGallery -Scope AllUsers -ErrorAction Stop
        $installSuccess = $true
        Write-Host "Successfully installed Log-Rotate module"
    }
    catch {
        $retryCount++
        if ($retryCount -lt $maxRetries) {
            Write-Host "Installation attempt $retryCount failed. Retrying in $retryDelaySeconds seconds... (Error: $($_.Exception.Message))"
            Start-Sleep -Seconds $retryDelaySeconds
        }
        else {
            Write-Error "Failed to install Log-Rotate module after $maxRetries attempts. Last error: $($_.Exception.Message)"
            throw
        }
    }
}

Write-Host "`n---------------------------------------"
Write-Host " Registering log rotate scheduled task"
Write-Host "-----------------------------------------`n"

Register-ScheduledTask -Xml (Get-Content "c:\setup\cron\LogRotate.xml" -Raw) -TaskName "LogRotate";

Get-ChildItem -Path $env:TEMP, 'C:\Windows\Temp' -Recurse | Remove-Item -Force -Recurse;
Remove-Item -Path "$env:TEMP\*" -Recurse -Force;
