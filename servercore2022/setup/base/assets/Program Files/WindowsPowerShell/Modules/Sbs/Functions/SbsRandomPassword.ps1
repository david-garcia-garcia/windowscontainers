Function SbsRandomPassword {
    param([int]$PasswordLength = 15)
 
    $CharacterSet = @{
        Lowercase   = (97..122) | Get-Random -Count 10 | % { [char]$_ }
        Uppercase   = (65..90)  | Get-Random -Count 10 | % { [char]$_ }
        Numeric     = (48..57)  | Get-Random -Count 10 | % { [char]$_ }
        # Exclude single quote by removing 39 from the range
        SpecialChar = ((33..38) + (40..47) + (58..64) + (91..96) + (123..126)) | Get-Random -Count 10 | % { [char]$_ }
    }
 
    #Frame Random Password from given character set
    $StringSet = $CharacterSet.Uppercase + $CharacterSet.Lowercase + $CharacterSet.Numeric + $CharacterSet.SpecialChar
    -join (Get-Random -Count $PasswordLength -InputObject $StringSet)
}