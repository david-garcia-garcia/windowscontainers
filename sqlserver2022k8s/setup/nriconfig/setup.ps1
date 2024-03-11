$global:ErrorActionPreference = 'Stop'

Start-Service 'MSSQLSERVER';

Import-Module Sbs;

#########################################
# Configure a DatabaseBackupInfoTable that we
# can use from within NRI to consolidate metrics
# about database backup state
#########################################
SbsDeployDbBackupInfo "localhost";