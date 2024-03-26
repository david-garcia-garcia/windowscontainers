
$scriptPath = $MyInvocation.MyCommand.Path
$scriptDirectory = Split-Path -Path $scriptPath -Parent

Write-Host $scriptDirectory

$childFiles = Get-ChildItem -Path $scriptDirectory -Recurse -Filter "*.ps1" | Where-Object { $_.FullName -match "Sbs\\Functions" }

foreach ($file in $childFiles) {
    . $file.FullName
    $functionName = [IO.Path]::GetFileNameWithoutExtension($file.Name);
    Write-Host $functionName;
}
