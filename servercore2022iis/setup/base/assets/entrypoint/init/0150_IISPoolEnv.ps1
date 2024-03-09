# Ensure the IISAdministration module is loaded
Import-Module IISAdministration

# Read the environment variable
$SBS_IISENV = [System.Environment]::GetEnvironmentVariable("SBS_IISENV");

# Format for the setting: POOLREGEX:ENVREGEX#POOLREGEX2:ENVREGEX2
$systemEnvVars = [System.Environment]::GetEnvironmentVariables("Machine");

# Check if the environment variable is empty or null
if ([string]::IsNullOrWhiteSpace($SBS_IISENV)) {
    SbsWriteHost "SBS_IISENV is empty or null. No action taken."
} else {
    # Parse the environment variable
    $pools = $SBS_IISENV -split "#"  # Split by '#' to get each pool definition

    foreach ($pool in $pools) {
        $parts = $pool -split ":", 2  # Split by ':' to separate pool regex and variable regex
        $poolRegex = $parts[0]
        $varRegex = $parts[1]

        # List all IIS app pools and match against the pool regex
        $matchingPools = Get-IISAppPool | Where-Object { $_.Name -match $poolRegex }

        foreach ($matchingPool in $matchingPools) {
            $propagatedEnv = 0
            $envVars = @{}

            # Enumerate all environment variables and filter based on the variable regex pattern
            Get-ChildItem env: | Where-Object {
                $_.Name -match $varRegex -and -not $systemEnvVars.ContainsKey($_.Name)
            } | ForEach-Object {
                $varName = $_.Name
                $varValue = $_.Value

                # Add the variable to the hashtable
                $envVars[$varName] = $varValue
                $propagatedEnv++
            }

            if ($propagatedEnv -gt 0) {
                # Invoke the cmdlet with the hashtable if there are any variables to propagate
                Invoke-IISChefPoolEnvUpsert -Pool $matchingPool.Name -Env $envVars
                SbsWriteHost "Propagated $($envVars) environment variable(s) to pool $($matchingPool.Name)."
            } else {
                SbsWriteHost "No environment variables were propagated to pool $($matchingPool.Name)."
            }
        }
    }
}
