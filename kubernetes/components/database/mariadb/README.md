# mariadb

mariadb-operator backed MariaDB component for apps that need MySQL or MariaDB. It creates a replicated
`${APP}-mariadb` (three instances on `openebs-hostpath`) with base backups and binlog archiving to S3, a
point-in-time restore when it is created, and daily dumps to NFS.

- [MariaDB](https://docs.bykaj.com/infrastructure/storage/mariadb/) ([source](../../../../docs/content/infrastructure/storage/mariadb.md)):
  substitution variables, connecting from an app, the `components.database/mariadb: init` label, backups, and the
  timeline bump every rebuild needs

```sh
just k8s db-backup <namespace> <app>   # manual base backup
```
