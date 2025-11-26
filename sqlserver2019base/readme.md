# Microsoft SQL Server 2019 base image

The purpose of this image is to serve as working base installation of MSSQL2019.

The installation sets up a Default Instance, with IP bindings and enabling SQL Authentication, so you can use the image as it is.

As part of the boostrapping, a random master key is automatically provisioned if none exists.

The image takes care automatically of moving all storage through env variables.

| Name                 | Default Value       | Description                                                  | Supports live refresh (changes are applied without restarting the container) |
| -------------------- | ------------------- | ------------------------------------------------------------ | ------------------------------------------------------------ |
| MSSQL_ADMIN_USERNAME | null                | Admin username, reconfigured every time when container starts | Yes                                                          |
| MSSQL_ADMIN_PWD      | null                | Admin password, reconfigured every time when container starts | Yes                                                          |
| MSSQL_PATH_DATA      | C:\SQLSystemDB\Data | Data file location                                           | No                                                           |
| MSSQL_PATH_LOG       | C:\SQLSystemDB\Log  | Log file location                                            | No                                                           |
| MSSQL_PATH_BACKUP    | C:\SQLBackup        | Backup file location                                         | No                                                           |
| MSSQL_PATH_SYSTEM    | C:\SQLUserDB\Data   | By design, this image is intended to be ephemeral, so system databases are kept inside the continer itself. Use this ENV to move the system databases to a persistent location if you want/need to preserve state. | No                                                           |
| MSSQL_SERVERNAME     | null                | Change the @@servername when starting the instance. This will slow down container boot times for about 2-3 additional seconds, as the change requires booting the engine in minimal configuration and the stopping it again. | No                                                           |

*Example composer setup for development environments, all the database state is moved out of the container to a local f:/databases/example* directory

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

