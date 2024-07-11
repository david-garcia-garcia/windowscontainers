# This here is only for testing purposes, to ensure
# we properly handle exceptions during boot
if ($true -eq (SbsGetEnvBool "SBS_TESTERROR")) {
    throw "Forced error due to environment variable SBS_TESTERROR";
}