# USE THIS TO SET THE IMAGE NAMES FOR THE BUILD

param ()

if (Test-Path -Path ".\envsettings.ps1") {
    # If the file exists, run the script
    .\envsettings.ps1
}

# Remove PIPELINE_ prefix from environment variables
Get-ChildItem env: | Where-Object { $_.Name -like "PIPELINE_*" } | ForEach-Object {
    Write-Host "Removing PIPELINE_ prefix from $($_.Name)"
    $newName = $_.Name -replace "^PIPELINE_", ""
    Set-Item -Path "env:$newName" -Value $_.Value
    Remove-Item -Path "env:$($_.Name)"
}



# Define the array of environment variable names to check
$envVarsToCheck = @(
    "MSSQLINSTALL_ISO_URL",
    "MSSQLINSTALL_CU_URL",
    "MSSQLINSTALL_CUFIX_URL",
    "REGISTRY_PATH",
    "IMAGE_VERSION"
)

# Check each environment variable
foreach ($envVarName in $envVarsToCheck) {
    $envVarValue = [System.Environment]::GetEnvironmentVariable($envVarName)
    
    if ([string]::IsNullOrWhiteSpace($envVarValue)) {
        throw "Environment variable '$envVarName' is empty or not set. Rename envsettings.ps1.template to envsettings.ps1 and complete the environment variables or set them for the current environment."
    }
}

$version = $ENV:IMAGE_VERSION;
$containerregistry = $ENV:REGISTRY_PATH;

Write-Host "Environment IMAGE_VERSION: $($version)"
Write-Host "Environment REGISTRY_PATH: $($containerregistry)"

if (-not $containerregistry.EndsWith('/')) {
    # Add a slash to the end of $containerregistry
    $containerregistry = "$containerregistry/"
}

# Image names
$Env:IMG_SERVERCORE2022 = "$($containerregistry)servercore2022:$($version)";
$Env:IMG_SERVERCORE2022IIS = "$($containerregistry)servercore2022iis:$($version)";
$Env:IMG_SERVERCORE2022IISNET48 = "$($containerregistry)servercore2022iisnet48:$($version)";

$Env:IMG_SQLSERVER2022AS = "$($containerregistry)sqlserver2022as:$($version)";
$Env:IMG_SQLSERVER2022IS = "$($containerregistry)sqlserver2022is:$($version)";
$Env:IMG_SQLSERVER2022BASE = "$($containerregistry)sqlserver2022base:$($version)";
$Env:IMG_SQLSERVER2022K8S = "$($containerregistry)sqlserver2022k8s:$($version)";

$Env:IMG_SQLSERVER2019BASE = "$($containerregistry)sqlserver2019base:$($version)";
$Env:IMG_SQLSERVER2017BASE = "$($containerregistry)sqlserver2017base:$($version)";



