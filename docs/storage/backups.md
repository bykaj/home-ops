---
description: PVC backups with Kopiur, database backups with CNPG, and deploy-or-restore
---

# Backups

| What | Tool | Destination | Schedule | Retention |
| --- | --- | --- | --- | --- |
| App PVCs | [Kopiur](https://github.com/home-operations/kopiur) (Kopia) | NFS repo on the NAS, `/mnt/vault/Backups/Cluster/main/kopiur` | Hourly (minute hashed per app) | 3 latest, 24 hourly, 7 daily, 4 weekly |
| PostgreSQL (WAL + base) | CNPG Barman Cloud plugin | Garage S3, `s3://postgresql/<app>/` | Continuous WAL, daily base | 14 days |
| PostgreSQL (dumps) | [postgres-backup-local](https://github.com/prodrigestivill/docker-postgres-backup-local) | NFS share on the NAS | Daily | 7 daily, 4 weekly, 6 monthly |
| Kopia repository (off-site copy) | Kopiur `RepositoryReplication` | [Backblaze B2](https://www.backblaze.com/cloud-storage), `b2://bykaj-backups/cluster/main/` | Daily at 01:30 | Exact mirror of the NAS repository |

Everything above lands on the NAS first. The Kopia repository is then copied
off-site to Backblaze B2 every night, so the PVC backups survive the loss of
the whole house. See [Off-site copy](#off-site-copy).

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

## Off-site copy

The Kopia repository on the NAS (`/mnt/vault/Backups/Cluster/main/kopiur`) is
replicated to Backblaze B2 every night. This follows the 3-2-1 rule: the live
data on Ceph, the Kopia repository on the NAS, and a copy outside the house.

Kopiur runs the replication from inside the cluster, as a `RepositoryReplication`
named `nas-offsite`
([`kubernetes/apps/system/kopiur/repository/repositoryreplication.yaml`](https://github.com/bykaj/home-ops/blob/main/kubernetes/apps/system/kopiur/repository/repositoryreplication.yaml)):

| Setting | Value |
| --- | --- |
| Source | `ClusterRepository` `nas` |
| Destination | B2 bucket `bykaj-backups`, prefix `cluster/main/` |
| Schedule | `30 1 * * *`, daily at 01:30 |
| Sync | `deleteExtra: true` (an exact mirror, so blobs pruned on the NAS are also removed from B2), 8 parallel transfers |
| Credentials | Secret `kopiur-replication-secret` |

Because it is an exact mirror, the B2 copy has the same snapshots and
retention as the NAS. It is also a complete Kopia repository, so any Kopia
client with the B2 credentials and the repository password can open it
directly.

Set `suspend: true` on the `RepositoryReplication` to pause it, for example
while repairing the NAS repository, so a damaged repository isn't mirrored
over the good off-site copy.

!!! note "Restoring from B2"

    The normal [deploy-or-restore](#deploy-or-restore) flow reads from the NAS.
    If the NAS copy is lost, restore the repository from B2 to the same NFS
    path first, then let Flux and Kopiur restore the apps as usual.

The B2 copy lags the NAS by up to a day, so a restore from B2 loses at most the
last day of changes.

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
