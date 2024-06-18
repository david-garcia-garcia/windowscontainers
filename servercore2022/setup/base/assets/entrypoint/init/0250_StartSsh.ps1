$global:ErrorActionPreference = if ($null -ne $Env:SBS_ENTRYPOINTERRORACTION ) { $Env:SBS_ENTRYPOINTERRORACTION } else { 'Stop' }

$SBS_ENABLESSH = SbsGetEnvBool "SBS_ENABLESSH";

if ($true -eq $SBS_ENABLESSH) {
    Set-Service -Name ssh-agent -StartupType Manual;
    Start-Service -Name ssh-agent;
    Set-Service -Name sshd -StartupType Manual;
    Start-Service -Name sshd;
}
