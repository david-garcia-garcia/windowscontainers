##########################################################################
# Reads environment variables from C:\environment.d\{anyname}.json if available
# + prepares them (system level promotion or DPAPI protection)
##########################################################################
function SbsPrepareEnv {
    [OutputType([bool])]
    param (
    )

    $confFiles = @();
    $secretFiles = @();

    # Configmaps and files
    $configDir = "C:\environment.d";
    $confHashes = @()

    if (Test-Path $configDir) {
        
        # We make this recursive to allow mounting full configmap without subpaths in K8S
        # see https://github.com/Azure/AKS/issues/4309
        $confFiles = Get-ChildItem -File -Recurse -Path $configDir -Include *.json | `
            Where-object { -not ($_.FullName -match "\\\.") } | `
            Sort-Object Name;
        
        foreach ($configFile in $confFiles) {
            $confHashes += (Get-FileHash $configFile.FullName -Algorithm SHA1).Hash;
        }
    }

    # Secrets
    $secretsDir = "c:\secrets.d";
    
    if (Test-Path $secretsDir) {
        # We make this recursive to allow mounting full configmap without subpaths in K8S
        # see https://github.com/Azure/AKS/issues/4309
        $secretFiles = Get-ChildItem -File -Recurse -Path $secretsDir | `
            Where-object { -not ($_.FullName -match "\\\.") } | `
            Sort-Object Name;
        
        # With secrets, every file is a value, and the file name is the secret name
        foreach ($secretFile in $secretFiles) {
            $confHashes += (Get-FileHash $secretFile.FullName -Algorithm SHA1).Hash;
        }
    }

    $hashFilePath = "c:\env.json.hash";

    if (Test-Path $hashFilePath) {
        $currentHash = Get-Content -Path $hashFilePath;
    }

    $mergedHashes = -join($confHashes);
    $md5Hash = [System.Security.Cryptography.HashAlgorithm]::Create("SHA1").ComputeHash([System.Text.Encoding]::UTF8.GetBytes($mergedHashes));
    $md5HashString = [System.BitConverter]::ToString($md5Hash);

    # In docker this is confusing because the ENV is gone when restarting containers, but the filesystem inside
    # the container is preserved. So we use ENVHASH to coordinate that.
    if ($md5HashString -eq $currentHash -and $md5HashString -eq $Env:ENVHASH) {
        return $false;
    }

    # Time to parse and merge the configuration
    $mergedConfig = @{}

    foreach ($configFile in $confFiles) {
        $fileContent = Get-Content -Path $configFile.FullName -Raw | ConvertFrom-Json
        foreach ($key in $fileContent.PSObject.Properties.Name) {
            $mergedConfig[$key] = $fileContent.$key
        }
    }

    # With secrets, every file is a value, and the file name is the secret name
    foreach ($secretFile in $secretFiles) {
        $fileContent = Get-Content -Path $secretFile.FullName -Raw;
        # This TRIM here is just convenience...
        # See https://github.com/kubernetes/kubernetes/issues/23404
        $mergedConfig["$($secretFile.Name)"] = "$($fileContent)".Trim();
    }

    $configuration = $mergedConfig | ConvertTo-Json -Depth 50;

    $configChangeCount = SbsGetEnvInt -name "SBS_CONFIG_CHANGECOUNT" -defaultValue 0
    Write-Host "Configuration change count $($configChangeCount)"
    $Env:SBS_CONFIG_CHANGECOUNT = ($configChangeCount + 1);
    
    foreach ($file in $confFiles) {
        Write-Host "Read environment configuration file $($file.FullName)"
    }

    foreach ($file in $secretFiles) {
        Write-Host "Read secret from file $($file.FullName)"
    }
    
    # Store to avoid reprocessing
    $md5HashString | Set-Content -Path $hashFilePath;
    [System.Environment]::SetEnvironmentVariable("ENVHASH", $md5HashString, [System.EnvironmentVariableTarget]::Process);

    if (-not [String]::IsNullOrWhiteSpace($configuration)) {
        Write-Host "Reading environment from C:\environment.d"
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
    # We can have runtime replacements in environment variable values. Why?
    # i.e. we need info that is only available once the pod/container is running
    # such as the hostname assigned by K8S
    ##########################################################################
    $processEnvironmentVariables = [System.Environment]::GetEnvironmentVariables([System.EnvironmentVariableTarget]::Process);
    Write-Host "Initiating ENV replacements";
    foreach ($key in $processEnvironmentVariables.Keys) {
        $variableName = $key.ToString();
        $variableValue = $processEnvironmentVariables[$key];
        if ($variableValue -match "{Env:(.*)}") {
            $envVariableNames = $variableValue | Select-String -Pattern "{Env:(.*)}" -AllMatches | ForEach-Object { $_.Matches.Groups[1].Value }
            foreach ($envVariableName in $envVariableNames) {
                Write-Host "Replacing $envVariableName in $variableName";
                $envVariableValue = [System.Environment]::GetEnvironmentVariable($envVariableName, [System.EnvironmentVariableTarget]::Process);
                $newVariableValue = $variableValue -replace "{Env:$envVariableName}", $envVariableValue;
                [System.Environment]::SetEnvironmentVariable($variableName, $newVariableValue, [System.EnvironmentVariableTarget]::Process);
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
            $protectedValue = SbsDpapiEncode -ClearValue $originalValue;
            [System.Environment]::SetEnvironmentVariable($originalVariableName, $protectedValue, [System.EnvironmentVariableTarget]::Process);
            Remove-Item -Path "Env:\$variableName";
            Write-Host "Protected environment variable '$variableName' with DPAPI at the machine level and renamed to '$originalVariableName'";
        }
    }

    ##########################################################################
    # Promote process level env variables to machine level. This is the most straighforward
    # way for making these accessible ot other processes in the container such as IIS pools,
    # scheduled tasks, etc.
    # Some of these contain sensible information that should not be promoted or readily available
    # to those services.
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