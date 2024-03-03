# Read the environment variable
$SBS_IISBINDINGS = [System.Environment]::GetEnvironmentVariable("SBS_IISBINDINGS");

if (![string]::IsNullOrEmpty($SBS_IISBINDINGS)) {
    $sites = $SBS_IISBINDINGS -split '\|';
    Import-Module WebAdministration;
    
    foreach ($site in $sites) {
        # Split to get the site name and binding definitions
        $parts = $site -split ':', 2;
        $siteName = $parts[0];
        
        if ($parts.Count -lt 2 -or [string]::IsNullOrEmpty($parts[1])) {
            Write-Host "No bindings defined for site `"$siteName`". Skipping..."
            continue
        }

        # Split the bindings part by "," to handle multiple bindings
        $bindings = $parts[1].Split(',');

        foreach ($binding in $bindings) {
            $removeBinding = $binding.StartsWith('!');
            $binding = $binding.TrimStart('!');
            
            # Split the clean binding into protocol, port, and hostname
            $bindingParts = $binding -split '[:/]+';
            if ($bindingParts.Count -lt 3) {
                Write-Host "Invalid binding format for `"$binding`" in site `"$siteName`". Expected format: protocol/port/hostname. Skipping..."
                continue;
            }

            $protocol = $bindingParts[0];
            $port = $bindingParts[1];
            $hostname = $bindingParts[2];

            $bindingInfo = "*:$($port):$hostname";
            Write-Host "Binding info $bindingInfo"
            # Attempt to retrieve existing bindings that match the specified criteria
            $existingBindings = Get-WebBinding -Name $siteName | Where-Object {
                $_.bindingInformation -eq $bindingInfo;
            };

            # Determine if any matching bindings exist by checking the count of the results
            $bindingExists = $existingBindings.Count -gt 0;

            if ($removeBinding -and $bindingExists) {
                Write-Host "Removing $protocol binding for '$hostname' on port $port from site '$siteName'"
                Remove-WebBinding -Name $siteName -Protocol $protocol -IPAddress "*" -Port $port -HostHeader $hostname
            }
            elseif ($removeBinding) {
                Write-Host "Binding to remove `"$binding`" does not exist in site `"$siteName`"."
            }
            elseif (-not $removeBinding -and -not $bindingExists) {
                Write-Host "Creating new $protocol binding for '$hostname' on port $port for site '$siteName'"
                New-WebBinding -Name $siteName -Protocol $protocol -IPAddress "*" -Port $port -HostHeader $hostname
            }
            elseif (-not $removeBinding) {
                Write-Host "$protocol binding for '$hostname' on port $port already exists on site '$siteName'"
            }
        }
    }
}
