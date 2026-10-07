---
description: Cluster backups with Kopiur and CNPG, NAS backups with ZFS snapshots and TrueCloud, and deploy-or-restore
---

# Backups

Backups come in two halves. The cluster backs its data up to the NAS, and the
NAS protects its own datasets (including the cluster's backups) with ZFS
snapshots and an encrypted off-site copy in Backblaze B2.

| What | Tool | Destination | Schedule | Retention |
| --- | --- | --- | --- | --- |
| App PVCs | [Kopiur](https://github.com/home-operations/kopiur) (Kopia) | NFS repo on the NAS, `/mnt/vault/Backups/Cluster/main/kopiur` | Hourly (minute hashed per app) | 3 latest, 24 hourly, 7 daily, 4 weekly |
| PostgreSQL (WAL + base) | CNPG Barman Cloud plugin | Garage S3, `s3://postgresql/<app>/` | Continuous WAL, daily base | 14 days |
| PostgreSQL (dumps) | [postgres-backup-local](https://github.com/prodrigestivill/docker-postgres-backup-local) | NAS, `/mnt/vault/Backups/Database` | Daily | 7 daily, 4 weekly, 1 monthly |
| Kopia repository (off-site copy) | Kopiur `RepositoryReplication` | [Backblaze B2](https://www.backblaze.com/cloud-storage), `b2://bykaj-backups/cluster/main/` | Daily at 01:30 | Exact mirror of the NAS repository |
| NAS datasets (local versions) | ZFS periodic snapshots | Same pool (`vault`) | Hourly to monthly, per dataset | See [ZFS snapshots](#zfs-snapshots) |
| NAS datasets (off-site copy) | TrueCloud Backup (restic) | Backblaze B2, `b2://bykaj-backups/nas/<dataset>` | Daily or weekly, per dataset | See [TrueCloud Backup](#truecloud-backup) |
| Paperless originals | TrueNAS Cloud Sync (WebDAV) | Nextcloud | Hourly | Mirror |

The cluster's data lands on the NAS first. From there the Kopia repository is
copied off-site by Kopiur itself (see [Off-site copy](#off-site-copy)), and
everything else that matters goes off-site through TrueCloud Backup (see
[NAS backups](#nas-backups)).

## Cluster backups

The cluster backs up app volumes with Kopiur and databases with CNPG. Both
land on the NAS, and the Kopia repository is mirrored to B2 from inside the
cluster.

### PVC backups with Kopiur

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

### Off-site copy

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

### Deploy-or-restore

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

### Database backups

See [PostgreSQL → Backups](postgres.md#backups). A manual base backup is one
recipe away:

```sh
just k8s db-backup <namespace> <app>
```

### Upgrade safety

The tuppr `TalosUpgrade` and `KubernetesUpgrade` plans wait until no Kopiur
`Snapshot` is `Running` and no `Restore` is resolving or restoring, and until
Ceph reports `HEALTH_OK`. See [Upgrades](../runbooks/upgrades.md).
## NAS backups

The NAS has one ZFS pool, `vault`, with one dataset per share. Each dataset
gets a protection level that fits how replaceable its data is:

| Dataset | Contents | ZFS snapshots | Off-site (TrueCloud) |
| --- | --- | --- | --- |
| `Applications` | Data of the [Compose stacks](../docker/index.md) (Garage, Bootimus) | Hourly + daily + weekly | Daily, keep 14 (without `zot`) |
| `Archive` | Paperless documents | Daily + monthly | Daily, keep 30 |
| `Backups` | Client and server backups, Postgres dumps | Daily | Daily, keep 14 (without `Cluster` and `Excluded`) |
| `Downloads`, `Software`, `Transfer`, `Users` | Recreatable or transient data | None | None |
| `Media` | Books, music and video libraries | Daily + monthly | Weekly, keep 12 (only `Books` and `Music`) |
| `Photos` | Photo albums and the Immich library | Daily + monthly | Daily, keep 30 |

### ZFS snapshots

Periodic snapshot tasks give every protected dataset local version history:
quick to take, cheap in space, and the fastest way to undo a deleted or
overwritten file. They live on the same pool, so they don't protect against
losing the pool itself. That is what the off-site copy is for.

All tasks are recursive and use the naming schema `auto-%Y-%m-%d_%H-%M`.

| Dataset | Schedule | Kept for | Allow empty |
| --- | --- | --- | --- |
| `Applications` | Hourly, on the hour | 24 hours | No |
| `Applications` | Daily at 00:00 | 14 days | Yes |
| `Applications` | Weekly, Sunday at 00:00 | 8 weeks | Yes |
| `Archive` | Daily at 01:00 | 30 days | Yes |
| `Archive` | Monthly, 1st at 01:30 | 12 months | Yes |
| `Backups` | Daily at 03:00 | 7 days | No |
| `Media` | Daily at 05:00 | 2 weeks | Yes |
| `Media` | Monthly, 1st at 05:30 | 6 months | Yes |
| `Photos` | Daily at 06:00 | 30 days | Yes |
| `Photos` | Monthly, 1st at 06:30 | 12 months | Yes |

Snapshots of running apps (Garage, Bootimus) are crash-consistent. That is
enough for Garage's immutable data blocks and for embedded metadata stores
that recover like after a power loss.

### TrueCloud Backup

[TrueCloud Backup](https://www.truenas.com/docs/scale/dataprotection/truecloud/)
is TrueNAS's built-in wrapper around [restic](https://restic.net). Each task
backs one dataset up to its own restic repository in the `bykaj-backups` B2
bucket, under `nas/<dataset>`. restic deduplicates, versions and encrypts
everything on the NAS before upload, so B2 only ever sees encrypted chunks.

!!! note "Requires the TrueCloud patch"

    Out of the box, TrueCloud Backup only supports Storj as a destination.
    Backing up to B2 is only possible with
    [truenas-truecloud-patch](https://github.com/sudolulo/truenas-truecloud-patch),
    which adds Backblaze B2 and S3-compatible providers, and snapshots of
    datasets with child datasets. It installs as a PREINIT boot hook that
    re-applies the patch at every boot, so it survives TrueNAS updates. Without
    it, the tasks below can't run.

| Task | Source | B2 folder | Schedule | Keep last | Exclude |
| --- | --- | --- | --- | --- | --- |
| Applications Daily | `/mnt/vault/Applications` | `/nas/applications` | Daily at 06:30 | 14 | `**/zot` |
| Archive Daily | `/mnt/vault/Archive` | `/nas/archive` | Daily at 02:00 | 30 | |
| Backups Daily | `/mnt/vault/Backups` | `/nas/backups` | Daily at 04:30 | 14 | `**/Cluster`, `**/Excluded` |
| Media Weekly | `/mnt/vault/Media` | `/nas/media` | Weekly, Sunday at 04:00 | 12 | `**/Series`, `**/Movies`, `**/Documentaries` |
| Photos Daily | `/mnt/vault/Photos` | `/nas/photos` | Daily at 03:30 | 30 | |

All tasks have **Use Snapshot** enabled: TrueNAS takes a temporary ZFS snapshot
when the task starts and backs that up, so restic reads a frozen,
point-in-time view instead of files that running apps or clients are still
writing. Tasks are staggered so they don't compete for upload bandwidth.
**Keep last** counts backup runs, so a daily task with 30 keeps about a month
and the weekly Media task with 12 keeps about three months.

Why some data is excluded:

- **`Backups/Cluster`** holds the Kopia repository. It already has its own
  versioning and its own off-site mirror (see [Off-site copy](#off-site-copy)).
  Wrapping Kopia's encrypted, chunked blobs in restic would only store them a
  second time.
- **`Backups/Excluded`** is the place for client data that deliberately stays
  local.
- **`Applications/zot`** is the [Zot](../docker/index.md#07-zot) pull-through
  cache. It refills itself from the upstream registries.
- **`Media/Series`, `Movies`, `Documentaries`** are large and recreatable. Only
  `Books` and `Music` go off-site.

Everything else in `Backups` does go off-site. Clients drop backups there
without keeping a copy of their own, so for them the NAS is the only copy. It
also holds the daily Postgres dumps (`Backups/Database`) and cluster app backups
(`Backups/Apps`). Garage's data in `Applications` includes the CNPG WAL
archives and base backups, so those go off-site through the Applications task.

!!! warning "Exclude patterns with Use Snapshot"

    With **Use Snapshot** enabled, the **Use Absolute Paths** option is
    disabled, and restic reads from the snapshot rather than from
    `/mnt/vault/<dataset>`. Root-anchored patterns like `/Series` then match
    nothing, and the task silently backs up the whole dataset. Use `**/Series`
    instead. It matches a `Series` file or folder at **any** depth, so don't
    reuse an excluded name for data deeper in the dataset that must be backed
    up.

The task password is the restic repository password. TrueNAS encrypts the
repository with it, so without it the B2 copy can't be read or restored.

### Documents to Nextcloud

A TrueNAS Cloud Sync task (`Archive Sync`) pushes
`/mnt/vault/Archive/media/documents/originals` to the `/Archief` folder of an
off-site Nextcloud instance over WebDAV, every hour. It runs in sync mode, so it is a
convenient, readable mirror of the original documents rather than a backup:
deletions on the NAS are mirrored too. The versioned copy is the Archive
TrueCloud task.

### Restoring NAS data

- **Recent mistakes**: restore the file or dataset from a ZFS snapshot
  (**Datasets → Snapshots** in the TrueNAS UI, or the dataset's
  `.zfs/snapshot/` directory).
- **Lost pool or older versions**: use **Restore** on the TrueCloud Backup task
  to pick a backup run and restore it, whole or in part, to a path on the NAS.

## Nightly timeline

| Time | Job |
| --- | --- |
| Every hour | `Applications` snapshot, Kopiur PVC backups, Archive Sync to Nextcloud |
| 00:00 | `Applications` daily (and Sunday weekly) snapshot |
| 01:00 | `Archive` snapshot |
| 01:30 | Kopia repository replication to B2 |
| 02:00 | Archive TrueCloud backup |
| 03:00 | `Backups` snapshot |
| 03:30 | Photos TrueCloud backup |
| 04:00 | Media TrueCloud backup (Sundays) |
| 04:30 | Backups TrueCloud backup |
| 05:00 | `Media` snapshot |
| 06:00 | `Photos` snapshot |
| 06:30 | Applications TrueCloud backup |

Monthly snapshots run half an hour after each dataset's daily one, on the 1st.
