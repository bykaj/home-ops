---
description: PVC backups with Kopiur, database backups with CNPG, and deploy-or-restore
---

# Backups

| What | Tool | Destination | Schedule | Retention |
| --- | --- | --- | --- | --- |
| App PVCs | [Kopiur](https://github.com/home-operations/kopiur) (Kopia) | NFS repo on the NAS, `/mnt/vault/Backups/Cluster/main/kopiur` | Hourly (minute hashed per app) | 3 latest, 24 hourly, 7 daily, 4 weekly |
| PostgreSQL (WAL + base) | CNPG Barman Cloud plugin | Garage S3, `s3://postgresql/<app>/` | Continuous WAL, daily base | 14 days |
| PostgreSQL (dumps) | [postgres-backup-local](https://github.com/prodrigestivill/docker-postgres-backup-local) | NFS share on the NAS | Daily | 7 daily, 4 weekly, 6 monthly |

## PVC backups with Kopiur

Apps opt in by adding the `kopiur/backup` component to their Flux
Kustomization (see [Components](../kubernetes/components.md#kopiurbackup)).
The component creates, per app:

- a `SnapshotPolicy`: what to back up (the app's PVC), how (zstd compression,
  CSI snapshot via `csi-ceph-blockpool` first), where (the `nas`
  `ClusterRepository`) and retention
- a `SnapshotSchedule`: `cron: H * * * *`, hourly at a per-app hashed minute
- the app's PVC itself, with `spec.dataSourceRef` pointing at a `Restore`
- the `Restore`, which acts as a volume populator

The mover runs as UID/GID `4000` by default and keeps a persistent cache on
`openebs-hostpath`.

!!! warning "Changing the mover UID"

    Changing `KOPIUR_MOVER_UID` for an existing app breaks its backups until
    the `kopiur-cache-<app>` PVC is deleted. The old cache is owned by the
    previous UID.

## Deploy-or-restore

Bootstrap restores no application data itself. Restores happen declaratively
once Flux takes over:

1. Flux applies an app on a fresh cluster. Its PVC has `spec.dataSourceRef`
   pointing at a Kopiur `Restore` with `target.populator: {}`.
2. Kopiur resolves the latest snapshot for the app's `SnapshotPolicy` and runs
   a restore mover Job into the new volume. The PVC stays unbound meanwhile,
   so the app's pod stays `Pending`. No ordering logic is needed anywhere.
3. When the restore finishes, the PVC binds and the app starts with its data.

The `Restore`s use `onMissingSnapshot: Continue`, so an app with no snapshot
yet (a brand-new app, or a deliberate fresh start) comes up with an empty
volume instead of failing. The same manifests handle both first deploy and
disaster recovery.

Each `Restore` pins the snapshot it resolved on first reconciliation and never
silently retargets, even if a schedule fires mid-restore.

## Database backups

See [PostgreSQL → Backups](postgres.md#backups). A manual base backup is one
recipe away:

```sh
just k8s db-backup <namespace> <app>
```

## Upgrade safety

The tuppr `TalosUpgrade` and `KubernetesUpgrade` plans wait until no Kopiur
`Snapshot` is `Running` and no `Restore` is resolving or restoring, and until
Ceph reports `HEALTH_OK`. See [Upgrades](../runbooks/upgrades.md).
