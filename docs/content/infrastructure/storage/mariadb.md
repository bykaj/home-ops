---
description: The mariadb-operator component for apps that need MySQL or MariaDB
---

# MariaDB

Apps that need MySQL or MariaDB get their own replicated
[MariaDB](https://mariadb.org) from the shared
[`kubernetes/components/database/mariadb`](https://github.com/bykaj/home-ops/tree/main/kubernetes/components/database/mariadb)
component, run by [mariadb-operator](https://github.com/mariadb-operator/mariadb-operator)
(in the `database` namespace). It follows the
[PostgreSQL](postgres.md) component: three instances on `openebs-hostpath`,
continuous archiving to Garage S3, a restore from S3 when the cluster is
created, and a nightly dump to the NAS.

## Using the component

Add the component and its health check to the app's Flux Kustomization:

```yaml
spec:
  components:
    - ../../../../components/database/mariadb
  healthCheckExprs:
    - apiVersion: k8s.mariadb.com/v1alpha1
      kind: MariaDB
      current: has(status.conditions) && status.conditions.exists(e, e.type == 'Ready' && e.status == 'True')
  postBuild:
    substitute:
      APP: *app
      MARIADB_BACKUP_SCHEDULE: "<minute> 0 * * *"
```

The app's HelmRelease needs `dependsOn: []`: the component appends
`mariadb-operator` to it.

| Variable | Default | Notes |
| --- | --- | --- |
| `APP` | _(required)_ | Name of the consuming app; used for the `MariaDB`, its Secrets and the backup paths |
| `MARIADB_USERNAME` | `${APP}` | User created with the instance; can't change afterwards |
| `MARIADB_DATABASE` | `${APP}` | Database created with the instance, the user gets all privileges on it; can't change afterwards |
| `MARIADB_MAX_USER_CONNECTIONS` | `100` | Connection limit of that user. The operator would give it a fixed 20, which Seafile exceeds at idle |
| `MARIADB_BACKUP_SCHEDULE` | `23 0 * * *` | Cron schedule for the dump to the NAS. Set it per app to `<minute> 0 * * *` with the minute from `just k8s cron-minute <app>` |
| `MARIADB_TIMELINE` | `1` | Archive generation in S3, see [Rebuilding](#rebuilding) |
| `MARIADB_RECOVERY_TIMELINE` | `${MARIADB_TIMELINE}` | Generation a new instance restores from, see [Rebuilding](#rebuilding) |

A brand-new database has no backup to restore yet. Deploy it once with the
label `components.database/mariadb: init` on the Flux Kustomization: a patch
in `cluster-apps` then removes `bootstrapFrom` and the instance starts empty.
Remove the label once the first base backup has completed (the
`PhysicalBackup` takes one right away), as with
[PostgreSQL](../../operations/runbooks/new-database.md#3-remove-the-label).
Create the NAS dump folder before the first scheduled dump:

```sh
sudo install -d -o 4000 -g 4000 /mnt/vault/Backups/Database/myapp
```

More databases or users (some apps need several) are `Database`, `User` and
`Grant` resources in the app itself, with `mariaDbRef: ${APP}-mariadb`.

## Connecting from an app

The primary is the `${APP}-mariadb-primary` Service on port 3306. The
operator generates the user's password into the `${APP}-mariadb-app` Secret
(key `password`):

```yaml
env:
  DB_HOST: "${APP}-mariadb-primary"
  DB_PASSWORD:
    valueFrom:
      secretKeyRef:
        name: "${APP}-mariadb-app"
        key: password
```

TLS is optional, so clients without TLS can connect.

## Topology

Three instances with asynchronous replication (semi-synchronous by default),
spread over the nodes (`antiAffinityEnabled`). The operator fails over to the
most up-to-date replica when the primary goes away. Data lives on
`openebs-hostpath`, so a lost node takes its replica's data with it: delete
that replica's PVC and the operator rebuilds it. A replica that can't catch up
from the primary's binlogs (error 1236) is rebuilt from a fresh physical
backup of a healthy replica (`${APP}-mariadb-replica`, a template under
`s3://mariadb/${APP}/replica/`).

The root password comes from the `mariadb` 1Password item
(`MARIADB_ROOT_PASSWORD`), shared by every instance: a restore needs the root
password the backup was taken with, so it can't be generated per cluster.

## Backups

All in the `mariadb` Garage bucket, under the app's name, plus a dump on the
NAS:

| What | Resource | Where | When | Kept |
| --- | --- | --- | --- | --- |
| Base backups (`mariadb-backup`) | `PhysicalBackup` `${APP}-mariadb-v<timeline>` | `s3://mariadb/${APP}/v<timeline>/base/` | Daily at 04:50, and once right after creation | 14 days |
| Binlogs | `PointInTimeRecovery` `${APP}-mariadb`, archived by the agent sidecar on the primary | `s3://mariadb/${APP}/v<timeline>/binlogs/` | Every 10 minutes; `SqlJob` `${APP}-mariadb-flush-binlogs` closes the current binlog every 15 minutes | Not pruned by the operator |
| Logical dump (`mariadb-dump`) | `Backup` `${APP}-mariadb-dump` | NAS, `/mnt/vault/Backups/Database/${APP}` | `MARIADB_BACKUP_SCHEDULE` | 30 days |

The S3 credentials are `MARIADB_S3_ACCESS_KEY_ID` and
`MARIADB_S3_SECRET_ACCESS_KEY` in the `mariadb` 1Password item; the component
copies them into the `${APP}-mariadb` Secret.

The agent only uploads closed binlogs, on a fixed 10-minute cycle. MariaDB
closes one at 128 MB (`max_binlog_size`), which a quiet database takes days to
reach, so the `${APP}-mariadb-flush-binlogs` `SqlJob` runs `FLUSH BINARY LOGS`
on the primary (as root) every 15 minutes. The archive is then at most 25
minutes behind, at the cost of up to 96 small binlogs a day per app; the
operator never prunes archived binlogs.

`kubectl get pitr -n <namespace>` shows the last recoverable time. It stays
empty until a binlog closed after the first base backup has been archived.

Take a base backup outside the schedule, for example before a risky change,
with:

```sh
just k8s db-backup <namespace> <app>
```

It sets a new `spec.schedule.onDemand` on the current timeline's
`PhysicalBackup`, which runs it once. Flux leaves that field alone, because
it isn't in the manifest. The backup counts toward the 14-day retention like
the scheduled ones.

## Rebuilding

A new `MariaDB` (deleted together with its PVCs, or on a fresh cluster)
restores through `bootstrapFrom`: the operator restores the newest base backup
of `MARIADB_RECOVERY_TIMELINE` on every instance and replays the archived
binlogs up to the last recoverable time.

Unlike CNPG, mariadb-operator only starts archiving binlogs into an **empty**
prefix, and a recreated `MariaDB` has no record of what it archived before. A
rebuilt instance would restore fine, but then never archive. So every rebuild
starts a new timeline:

1. In the app's Flux Kustomization, set `MARIADB_RECOVERY_TIMELINE` to the
   current timeline and `MARIADB_TIMELINE` to the next one, for example `"1"`
   and `"2"`. Merge.
2. Delete the `MariaDB` and its PVCs (`storage-${APP}-mariadb-*`). Flux
   recreates it, restoring from the old timeline and archiving to the new one.
   A base backup of the new timeline is taken at the next 04:50; to get one
   sooner, run `just k8s db-backup <namespace> <app>`.

Leave both values in place afterwards; the next rebuild moves them up by one
again. The old timeline's objects in S3 aren't deleted.

!!! warning "Same timeline twice"

    If a rebuild keeps the timeline, the restore works but archiving stops
    with "Archival must start from a clean state" (the `BinlogsArchived`
    condition and an event on the `MariaDB`). Bump `MARIADB_TIMELINE` to fix
    it; the new timeline only becomes recoverable after its first base
    backup.

`storage` can't change on a `PhysicalBackup`, so the timeline is part of its
name: a bump creates a new `${APP}-mariadb-v<timeline>` and Flux removes the
old one, without touching its backups in S3.
