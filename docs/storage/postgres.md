---
description: The CloudNative-PG component that backs every app database
---

# PostgreSQL

Every app that needs PostgreSQL gets its own [CloudNative-PG](https://cloudnative-pg.io)
cluster from the shared
[`kubernetes/components/postgres`](https://github.com/bykaj/home-ops/tree/main/kubernetes/components/postgres)
component. There is no shared database server.

## Using the component

Add the component and its health check to the app's Flux Kustomization:

```yaml
spec:
  components:
    - ../../../../components/postgres
  healthCheckExprs:
    - apiVersion: postgresql.cnpg.io/v1
      kind: Cluster
      failed: status.conditions.filter(e, e.type == 'Ready').all(e, e.status == 'False')
      current: status.conditions.filter(e, e.type == 'Ready').all(e, e.status == 'True')
  postBuild:
    substitute:
      APP: *app
```

| Variable | Default | Notes |
| --- | --- | --- |
| `APP` | _(required)_ | Name of the consuming app; used for cluster, Secret and backup paths |
| `POSTGRES_USERNAME` | `${APP}` | Owner role created on initial bootstrap |
| `POSTGRES_DATABASE` | `${APP}` | Database created on initial bootstrap |
| `POSTGRES_BACKUP_SCHEDULE` | `23 0 * * *` | Cron schedule for the local NFS dump |

A brand-new database needs one extra label on first deploy. See
[New Database](../runbooks/new-database.md).

## Connecting from an app

CNPG names everything after the `Cluster`, `${APP}-postgres`. It generates a
`${APP}-postgres-app` Secret with the keys `uri`, `jdbc-uri`,
`username`, `password`, `host`, `port`, `dbname` and `pgpass`. In an
app-template HelmRelease:

```yaml
env:
  DATABASE_URL:
    valueFrom:
      secretKeyRef:
        name: "{{ .Release.Name }}-postgres-app"
        key: uri
```

`uri` points at the read-write primary Service `${APP}-postgres-rw`. There is no
PgBouncer `Pooler`. Apps connect directly.

## Bootstrap behavior

By default the `Cluster` bootstraps with `bootstrap.recovery` from Barman at
`s3://postgresql/${APP}/${POSTGRES_DATABASE}/`. Delete the `Cluster` CR and its
PVCs, and it rebuilds from the latest base backup plus WAL replay.

Same-path, same-`serverName` rebuilds work because of the
`cnpg.io/skipEmptyWalArchiveCheck: enabled` annotation. The recovered cluster
inherits the source's `system_identifier` and writes new WAL on a new timeline,
so names don't collide.

## Backups

- **Barman Cloud** (`ScheduledBackup`, daily) with continuous WAL archiving to
  Garage S3 at `s3://postgresql/${APP}/${POSTGRES_DATABASE}/`,
  `retentionPolicy: 14d`.
- **Local dumps** with
  [postgres-backup-local](https://github.com/prodrigestivill/docker-postgres-backup-local)
  to an NFS share on the NAS, keeping 7 daily, 4 weekly and 1 monthly.

Trigger a manual base backup with `just k8s db-backup <namespace> <app>`.

Administration is through [pgAdmin](https://www.pgadmin.org) in the `default`
namespace.
