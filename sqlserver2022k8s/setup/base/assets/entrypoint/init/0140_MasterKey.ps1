########################################################
# Setup a master key so that encryption operations
# can be run in this engine
########################################################

$global:ErrorActionPreference = if ($null -ne $Env:SBS_ENTRYPOINTERRORACTION ) { $Env:SBS_ENTRYPOINTERRORACTION } else { 'Stop' }

Function Get-RandomPassword
{
    #define parameters
    param([int]$PasswordLength = 10)
 
    #ASCII Character set for Password
    $CharacterSet = @{
            Lowercase   = (97..122) | Get-Random -Count 10 | % {[char]$_}
            Uppercase   = (65..90)  | Get-Random -Count 10 | % {[char]$_}
            Numeric     = (48..57)  | Get-Random -Count 10 | % {[char]$_}
            # Exclude single quote by removing 39 from the range
            SpecialChar = ((33..38)+(40..47)+(58..64)+(91..96)+(123..126)) | Get-Random -Count 10 | % {[char]$_}
    }
 
    #Frame Random Password from given character set
    $StringSet = $CharacterSet.Uppercase + $CharacterSet.Lowercase + $CharacterSet.Numeric + $CharacterSet.SpecialChar
 
    -join(Get-Random -Count $PasswordLength -InputObject $StringSet)
}

# Generate a random password for the master key
$randomPassword = Get-RandomPassword 30;
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