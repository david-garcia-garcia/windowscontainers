########################################################
# Setup a master key so that encryption operations
# can be run in this engine
########################################################

$global:ErrorActionPreference = if ($null -ne $Env:SBS_ENTRYPOINTERRORACTION ) { $Env:SBS_ENTRYPOINTERRORACTION } else { 'Stop' }

# Generate a random password for the master key
$randomPassword = SbsRandomPassword 30;
$escapedPassword = $randomPassword -replace "'", "''";
$sqlInstance = Connect-DbaInstance -SqlInstance localhost;

$masterKeyExists = Get-DbaDbMasterKey -SqlInstance $sqlInstance -Database master;

if (-not $masterKeyExists) {
    $sqlScript = "CREATE MASTER KEY ENCRYPTION BY PASSWORD = '$escapedPassword';";
    Invoke-DbaQuery -SqlInstance $sqlInstance -Database master -Query $sqlScript;
    SbsWriteHost "Created master key";
} else {
    SbsWriteHost "A master key already exists in the 'master' database.";
}

# Wether the master key exists or not, we need to force regenerate the key service
# so the windows registry gets updated
# https://stackoverflow.com/questions/26637592/an-error-occurred-during-service-master-key-decryption-when-trying-to-create-s
# The master key was never here as part of the image preparation process (which makes sense)
Invoke-DbaQuery -SqlInstance $sqlInstance -Database master -Query "ALTER SERVICE MASTER KEY FORCE REGENERATE";