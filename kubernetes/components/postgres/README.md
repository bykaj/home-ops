# postgres

CloudNative-PG backed PostgreSQL component, the default PostgreSQL for every app in this repo. It
creates a `${APP}-postgres` cluster with Barman backups to S3 and local dumps to NFS.

- [PostgreSQL](https://docs.bykaj.com/storage/postgres/) ([source](../../../docs/storage/postgres.md)):
  substitution variables, connecting from an app, bootstrap behavior, backups
- [New Database](https://docs.bykaj.com/runbooks/new-database/)
  ([source](../../../docs/runbooks/new-database.md)): the `components.postgres/cnpg: init` label
  for a brand-new database with no prior backup

```sh
just k8s db-backup <namespace> <app>   # manual base backup
```
