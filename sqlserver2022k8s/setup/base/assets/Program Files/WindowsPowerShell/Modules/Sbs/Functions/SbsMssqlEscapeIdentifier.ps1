function SbsMssqlEscapeIdentifier {
    param (
        [string]$identifier
    )
    
    # Validate that the identifier contains only allowed characters
    if ($identifier -match '^[a-zA-Z0-9_\-]+$') {
        # Escape square brackets (although with validation this might be less necessary)
        $identifier = $identifier -replace '\[', '[[]'
        $identifier = $identifier -replace '\]', ']]'
        return $identifier
    } else {
        throw "Invalid characters in identifier"
    }
}