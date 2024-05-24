# USE THIS TO SET THE IMAGE NAMES FOR THE BUILD

param ()

.\envsettings.ps1

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
        throw "Environment variable '$envVarName' is empty or not set. Rename envsettings.ps1.template to envsettings.ps1 and complete the environment variables."
    }
}

$version = $ENV:IMAGE_VERSION;

# Image names
$Env:IMG_SERVERCORE2022 = "$($containerregistry)servercore2022:$($version)";
$Env:IMG_SERVERCORE2022IIS = "$($containerregistry)servercore2022iis:$($version)";
$Env:IMG_SERVERCORE2022IISNET48 = "$($containerregistry)servercore2022iisnet48:$($version)";
$Env:IMG_SQLSERVER2022AS = "$($containerregistry)sqlserver2022as:$($version)";
$Env:IMG_SQLSERVER2022BASE = "$($containerregistry)sqlserver2022base:$($version)";
$Env:IMG_SQLSERVER2022K8S = "$($containerregistry)sqlserver2022k8s:$($version)";

