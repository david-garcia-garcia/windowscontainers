# Microsoft SQL Server 2022 base image

The purpose of this image is to serve as working base installation of MSSQL2022.

The installation sets up a Default Instance, with IP bindings and enabling SQL Authentication, so you can use the image as it is.

The whole engine and data are setup inside the container at:

```powershell
$systemDbDir = 'C:\SQLSystemDB\Data';
$systemDbLogDir = 'C:\SQLSystemDB\Log';
$userDbDir = 'C:\SQLUserDB\Data';
$userDbLogDir = 'C:\SQLUserDB\Log';
$backupDir = 'C:\SQLBackup';
$installDir = 'C:\Program Files\Microsoft SQL Server';
```

Except for test purposes, you should be moving those **out** of the c:\ drive (even if you are mapping them to storage in K8S or other platform). Besides other reasons, when restoring a backup MSSQL does preemptive free space calculations based on the size of the c:\ drive, and even if you have enough space in your mapped storage, MSSQL is not able to see it unless you map it to a drive of its own.

The image takes care automatically of moving all storage through env variables.

**MSSQL_ADMIN_USERNAME and MSSQL_ADMIN_PWD**

Configure an admin username and password.

**MSSQL_PATH_DATA, MSSQL_PATH_LOG, MSSQL_PATH_BACKUP**

Configure the default log, data and backup path.

**MSSQL_PATH_SYSTEM**

This is the tricky one. This ENV variable will MOVE all system databases (including master) to the specified location. This allows you to map off-container the engine configuration if you need to (i.e. in environments where the container state is lost such as K8S).

*Example setup, all the database state is moved out of the container to a local f:/databases/example* directory

```yaml
services:
  web:
    build: .
    volumes:
      - "f:/databases/example:d:"
    environment:
      - MSSQL_ADMIN_USERNAME=sa
      - MSSQL_ADMIN_PWD_PROTECT=sapwd
      - MSSQL_PATH_DATA=d:\data
      - MSSQL_PATH_LOG=d:\log
      - MSSQL_PATH_SYSTEM=d:\system
      - MSSQL_PATH_BACKUP=d:\backup
      - SBS_ENTRYPOINTERRORACTION=Stop
```

