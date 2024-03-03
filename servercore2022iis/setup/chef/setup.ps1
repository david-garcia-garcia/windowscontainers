$global:ErrorActionPreference = 'Stop';

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; 

$download = [System.IO.Path]::GetTempFileName();
$url = "https://ci.appveyor.com/api/projects/david-garcia-garcia/iischef/artifacts/iischef.cmdlet.zip?branch=1.x";
(New-Object Net.WebClient).DownloadFile($url, $download);

$destination = "$($Env:ProgramFiles)\WindowsPowerShell\Modules\iischef";
7z x "$download" -o"$destination" -y;
Remove-Item $download -Force;

Import-Module "$($Env:ProgramFiles)\WindowsPowerShell\Modules\iischef\iischef.dll";

Get-ChildItem -Path $env:TEMP, 'C:\Windows\Temp' -Recurse | Remove-Item -Force -Recurse;