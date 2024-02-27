# Read the SSAS_USERS environment variable
$ssasUsers = [System.Environment]::GetEnvironmentVariable("SSAS_USERS")

# Check if the variable is not null or empty
if (![string]::IsNullOrEmpty($ssasUsers)) {
    # Split the variable into individual user:password pairs
    $userPairs = $ssasUsers -split ","
    
    foreach ($userPair in $userPairs) {
        # Split each pair into username and password
        $userDetails = $userPair -split ":"
        $username = $userDetails[0]
        $password = $userDetails[1]

        # Convert the password into a secure string
        $securePassword = ConvertTo-SecureString $password -AsPlainText -Force

        # Attempt to create the user
        try {
            New-LocalUser -Name $username -Password $securePassword -AccountNeverExpires -PasswordNeverExpires
            Write-Host "Successfully created user: $username"
        } catch {
            Write-Host "Failed to create user: $username. Error: $_"
        }
    }
}
