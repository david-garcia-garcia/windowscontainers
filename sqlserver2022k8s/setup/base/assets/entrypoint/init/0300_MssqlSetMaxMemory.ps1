# We want to set MAXMEMORY after all the startup scripts have run, so
# that startup (and eventually restore) is not memory constrained.
# . "c:\entrypoint\refreshenv\MssqlSetMaxMemory.ps1";