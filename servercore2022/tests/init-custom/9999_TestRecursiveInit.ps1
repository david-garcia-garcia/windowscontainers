$global:ErrorActionPreference = if ($null -ne $Env:SBS_ENTRYPOINTERRORACTION ) { $Env:SBS_ENTRYPOINTERRORACTION } else { 'Stop' }

Import-Module Sbs;
SbsWriteHost "TEST_RECURSIVE_INIT_SCRIPT_EXECUTED: Custom initialization script from mounted subdirectory executed successfully"

