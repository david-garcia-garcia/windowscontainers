Import-Module WebAdministration;

# Retrieve the environment variable value (assuming it's a delimited string)
$SBS_ADDPOOLSTOGROUPS = [System.Environment]::GetEnvironmentVariable("SBS_ADDPOOLSTOGROUPS");

if (-not [string]::IsNullOrEmpty($SBS_ADDPOOLSTOGROUPS)) {
    # Split the string into an array, assuming the groups are separated by a semicolon (;)
    $Groups = $SBS_ADDPOOLSTOGROUPS -split ";";

    # Initialize an empty array to hold the resolved group names
    $ResolvedGroups = @();

    foreach ($Group in $Groups) {
            # Regular expression to match the SID pattern
            $sidPattern = '^S-\d+(-\d+)+$';

            if ($Group -match $sidPattern) {
                $sid = New-Object System.Security.Principal.SecurityIdentifier $Group;
                $groupName = $sid.Translate([System.Security.Principal.NTAccount]).Value;
                Write-Host "SID $sid translated to $groupName";
            } else {
                # The group string does not match SID pattern, so assume it's already a group name
                $groupName = $Group;
            }

            # Use Get-LocalGroup to verify and get the actual group name
            $localGroup = Get-LocalGroup | Where-Object { $_.Name -eq $groupName -or $_.SID.Value -eq $sid }

            if ($localGroup) {
                # If the group exists, add its name to the resolved groups array
                $ResolvedGroups += $localGroup.Name
            } else {
                Write-Host "Group or SID '$Group' with resolved name '$groupName' does not correspond to an existing group."
            }
    }
    
    # Get the list of all application pools
    $AppPools = Get-ChildItem IIS:\AppPools;

    foreach ($AppPool in $AppPools) {
        # Get the application pool identity type and username
        $processModel = Get-ItemProperty "IIS:\AppPools\$($AppPool.Name)" -Name processModel;
        $identityType = $processModel.identityType;
        $userName = $processModel.userName;

        # Determine the account to add based on the identity type
        if ($identityType -eq "SpecificUser" -and $userName) {
            # Custom user account
            $accountToAdd = $userName;
        } elseif ($identityType -ne "SpecificUser") {
            # Built-in account, using the application pool's name in the format used by virtual accounts
            $accountToAdd = "IIS AppPool\$($AppPool.Name)";
        } else {
            Write-Host "Skipping $($AppPool.Name): No custom user or built-in account to add.";
            continue;
        }

        foreach ($group in $ResolvedGroups) {
            # Check if the account is already a member of the group
            $isMember = (Get-LocalGroupMember -Group $group -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $accountToAdd }).Count -gt 0;

            if (-not $isMember) {
                try {
                    Add-LocalGroupMember -Group $group -Member $accountToAdd -ErrorAction Stop;
                    Write-Host "Added $accountToAdd to group $group";
                } catch {
                    Write-Host "Failed to add $accountToAdd to group $group. Error: $_";
                }
            } else {
                Write-Host "$accountToAdd is already a member of group $group";
            }
        }
    }
}
