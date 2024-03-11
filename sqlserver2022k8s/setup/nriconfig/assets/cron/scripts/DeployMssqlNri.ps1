## We need to keep redeploying monitoring
## so that we are 100% sure that the
## newrelic identity is in all databases
## if this was not scheduled periodically
## after a i.e. restore you would need to
## manually add the newrelic user again
Import-Module Sbs;
SbsDeployDbBackupInfo;
SbsAddNriMonitor "localhost";