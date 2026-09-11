# postgres

CloudNative-PG backed PostgreSQL component. Default PostgreSQL for all apps in this repo.

## Substitution variables

| Variable                   | Default                      | Notes                                                               |
| -------------------------- | ---------------------------- | ------------------------------------------------------------------- |
| `APP`                      | _(required)_                 | Name of the consuming app — used for cluster, secret, backup paths. |
| `POSTGRES_USERNAME`        | `${APP}`                     | Username created on initial bootstrap.                              |
| `POSTGRES_DATABASE`        | `${APP}`                     | Database name created on initial bootstrap.                         |
| `POSTGRES_IMAGE`           | [_see YAML_](./cluster.yaml) | Specific PostgreSQL image for this cluster.                         |
| `POSTGRES_BACKUP_SCHEDULE` | `23 0 * * *`                 | Cron schedule for local NFS backup.                                 |

## Bootstrap behavior

The component's `Cluster` CR defaults to `bootstrap.recovery` from Barman at `s3://postgresql/${APP}/${POSTGRES_DATABASE}/`. A torn-down cluster (delete the `Cluster` CR + PVCs) rebuilds itself from the latest base backup + replays WAL. Same-path same-`serverName` rebuilds work because of the `cnpg.io/skipEmptyWalArchiveCheck: enabled` annotation — the recovered cluster inherits the source's `system_identifier` and writes new WAL on a new timeline (no name collisions).

That default works for any app that already has a Barman base backup at the destination. For a brand-new app with **no** prior backup, use the init flow instead.

### Adding a net-new DB (no prior backup)

For a brand-new app — i.e. nothing exists at `s3://postgresql/${APP}/` yet — `bootstrap.recovery` would fail with "no target backup found." Use the `components.postgres/cnpg=init` label on the consuming Flux Kustomization to switch to plain `initdb`.

Concretely, an app's Flux Kustomization looks like:

```yaml
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app myapp
  labels:
    components.postgres/cnpg: init # <-- add this for initialization only
spec:
  components:
    - ../../../../components/postgres
  healthCheckExprs:
    - apiVersion: postgresql.cnpg.io/v1
      kind: Cluster
      failed: status.conditions.filter(e, e.type == 'Ready').all(e, e.status == 'False')
      current: status.conditions.filter(e, e.type == 'Ready').all(e, e.status == 'True')
  interval: 1h
  path: ./kubernetes/apps/.../myapp
  postBuild:
    substitute:
      APP: *app
      # Optional overrides; defaults to ${APP}
      # POSTGRES_DATABASE: myapp-db
      # POSTGRES_USERNAME: myapp-user
      # Complete image override; defaults to the standard from CNPG
      # POSTGRES_IMAGE: ghcr.io/tensorchord/cloudnative-vectorchord:18.6
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
```

What the label does (via the patch in [`clusters/main/apps.yaml`](../../clusters/main/apps.yaml)): strips `spec.bootstrap.recovery` and `spec.externalClusters`, replacing `bootstrap` with a plain `initdb` that creates a database + owner role named `${POSTGRES_USERNAME:=${APP}}`. CNPG generates the role's password into the `${APP}-app` Secret as usual.

**After the first scheduled backup lands** (Daily at night, or after manually creating a one-shot `Backup` CR), **remove the `cnpg: init` label**. Future cluster rebuilds will then follow the default `recovery` path. Keeping the label after a backup exists is harmless during normal operation (bootstrap is only consulted at cluster creation), but it would prevent a rebuild from restoring data if you ever destroy and recreate the cluster.

To force an immediate backup so you can drop the label sooner:

```sh
kubectl apply -f - <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata: { name: ${APP}-postgres-initial, namespace: ${NAMESPACE} }
spec: { cluster: { name: ${APP}-postgres }, method: plugin,
pluginConfiguration: { name: barman-cloud.cloudnative-pg.io } }
EOF
```

Also added as a Just recipe in [`mod.just`](../../mod.just):

```sh
just k8s db-backup ${NAMESPACE} ${APP}
```

## Backups

Daily full backups via:

- the `ScheduledBackup` resource (see [`scheduledbackup.yaml`](./scheduledbackup.yaml)). Continuous WAL archiving to the same `s3://postgresql/${APP}/${POSTGRES_DATABASE}/` prefix. `retentionPolicy: 14d`.
- a [prodrigestivill/docker-postgres-backup-local](https://github.com/prodrigestivill/docker-postgres-backup-local) container to a local NFS share with a retention of 7 days, 4 weeks and 6 months.

## Connecting from an app

CNPG generates a `${APP}-app` Secret with these keys: `uri`, `jdbc-uri`, `username`, `password`, `host`, `port`, `dbname`, `pgpass`.

Standard app-template pattern:

```yaml
DATABASE_URL:
  valueFrom:
    secretKeyRef:
      name: "{{ .Release.Name }}-app"
      key: uri
```

The `uri` points at the cluster's read-write primary service `${APP}-rw`. There is no `Pooler` / PgBouncer in this component — apps connect directly. If transaction-mode pooling is ever needed (e.g. authentik at scale), add a `Pooler` CRD per cluster as a follow-up.

## Health check expression

```yaml
healthCheckExprs:
  - apiVersion: postgresql.cnpg.io/v1
    kind: Cluster
    failed: status.conditions.filter(e, e.type == 'Ready').all(e, e.status == 'False')
    current: status.conditions.filter(e, e.type == 'Ready').all(e, e.status == 'True')
```
