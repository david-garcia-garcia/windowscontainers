##########################################################################
# Reads environment variables from c:\configmap\env.json if available
# + prepares them (system level promotion or DPAPI protection)
##########################################################################
function SbsPrepareEnv {
    [OutputType([bool])]
    param (
    )

    $configuration = "";

    if (Test-Path "c:\configmap\env.json") {
        $configuration = Get-Content -Raw -Path "c:\configmap\env.json";
    }

    $hashFilePath = "c:\env.json.hash";

    if (Test-Path $hashFilePath) {
        $currentHash = Get-Content -Path $hashFilePath;
    }

    $md5Hash = [System.Security.Cryptography.HashAlgorithm]::Create("MD5").ComputeHash([System.Text.Encoding]::UTF8.GetBytes($configuration))
    $md5HashString = [System.BitConverter]::ToString($md5Hash);

    # In docker this is confusing because the ENV is gone when restarting containers, but the filesystem inside
    # the container is preserved. So we use ENVHASH to coordinate that.
    if ($md5HashString -eq $currentHash -and $md5HashString -eq $Env:ENVHASH) {
        return $false;
    }
    
    # Store to avoid reprocessing
    $md5HashString | Set-Content -Path $hashFilePath;
    [System.Environment]::SetEnvironmentVariable("ENVHASH", $md5HashString, [System.EnvironmentVariableTarget]::Process);

    if (-not [String]::IsNullOrWhiteSpace($configuration)) {
        Write-Host "Reading environment from config map."
        $configMap = $configuration | ConvertFrom-Json;
        foreach ($key in $configMap.PSObject.Properties) {
            $variableName = $key.Name
            $variableValue = $key.Value
            try {
                [System.Environment]::SetEnvironmentVariable($variableName, $variableValue, [System.EnvironmentVariableTarget]::Process)
            }
            catch {
                $originalErrorMessage = $_.Exception.Message;
                Write-Error "Cannot set environment variable '$variableName' ($originalErrorMessage)";
            }
        }
    }

    ##########################################################################
    # Protect environment variables using DPAPI
    ##########################################################################
    $processEnvironmentVariables = [System.Environment]::GetEnvironmentVariables([System.EnvironmentVariableTarget]::Process);
    Write-Host "Initiating ENV protection";
    foreach ($key in $processEnvironmentVariables.Keys) {
        $variableName = $key.ToString()
        if ($variableName -match "^(.*)_PROTECT$") {
            Add-Type -AssemblyName System.Security;
            $originalVariableName = $matches[1];
            $originalValue = $processEnvironmentVariables[$key];
            $protectedValue = [System.Convert]::ToBase64String([System.Security.Cryptography.ProtectedData]::Protect([System.Text.Encoding]::UTF8.GetBytes($originalValue), $null, 'LocalMachine'));
            [System.Environment]::SetEnvironmentVariable($originalVariableName, $protectedValue, [System.EnvironmentVariableTarget]::Process);
            Remove-Item -Path "Env:\$variableName";
            Write-Host "Protected environment variable '$variableName' with DPAPI at the machine level and renamed to '$originalVariableName'";
        }
    }

    ##########################################################################
    # Promote process level env variables to machine level. This is the most straighforward
    # way making these accessible ot other processes in the container such as IIS pools,
    # scheduled tasks, etc.
    # Some of these contain sensible information that should not be promoted or readily available
    # to those services (i.e. there could be 3d party software such as NR running that will
    # have access to theses inmmediately)
    ##########################################################################
    $SBS_PROMOTE_ENV_REGEX = [System.Environment]::GetEnvironmentVariable("SBS_PROMOTE_ENV_REGEX");
    if (-not [string]::IsNullOrWhiteSpace($SBS_PROMOTE_ENV_REGEX)) {
        Write-Host "Initiating ENV system promotion for variables that match '$SBS_PROMOTE_ENV_REGEX'";
        $processEnvironmentVariables = [System.Environment]::GetEnvironmentVariables([System.EnvironmentVariableTarget]::Process);
        foreach ($key in $processEnvironmentVariables.Keys) {
            $variableName = $key.ToString();
            if ($variableName -match $SBS_PROMOTE_ENV_REGEX) {
                $variableValue = [System.Environment]::GetEnvironmentVariable($variableName, [System.EnvironmentVariableTarget]::Process);
                [System.Environment]::SetEnvironmentVariable($variableName, $variableValue, [System.EnvironmentVariableTarget]::Machine);
                Write-Host "Promoted environment variable: $variableName";
            }
        }
    }

    return $true;
}