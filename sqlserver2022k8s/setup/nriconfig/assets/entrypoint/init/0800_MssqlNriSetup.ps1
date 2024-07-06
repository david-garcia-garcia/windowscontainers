Import-Module Sbs;

SbsDeployDbBackupInfo "localhost";

$password = SbsRandomPassword 30;
SbsAddNriMonitorUser -instanceName "localhost" -User "monitoring" -Password $password;