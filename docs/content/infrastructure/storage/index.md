---
description: Rook-Ceph block storage, OpenEBS local volumes and the NAS
icon: material/database
---

# Storage

Three storage tiers, each with a clear job:

| Tier | Backed by | StorageClass | Used for |
| --- | --- | --- | --- |
| Replicated block | Rook-Ceph on the Micron 7300 NVMe drives | `ceph-block` (default) | App config and state PVCs |
| Local | OpenEBS hostpath on each node's `local-hostpath` volume | `openebs-hostpath` | Caches and scratch that can be lost (for example the Kopiur mover cache) |
| Bulk | TrueNAS ZFS pools over NFS / SMB | (static NFS volumes) | Media, documents, backups |

## Rook-Ceph

[Rook](https://rook.io) runs a Ceph cluster on the three nodes, with one OSD
per node on a dedicated Micron 7300 PRO 480 GB NVMe drive. The
`rook-ceph-cluster` HelmRelease
([`kubernetes/apps/rook-ceph/rook-ceph/cluster/`](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/rook-ceph/rook-ceph/cluster))
creates:

- the `ceph-block` RBD StorageClass (default, `reclaimPolicy: Delete`)
- the `csi-ceph-blockpool` VolumeSnapshotClass (default), used by Kopiur for
  crash-consistent snapshots before backup

The VolumeSnapshot CRDs come from the `snapshot-controller` chart with
`keepCRDs: true`, so a Helm uninstall or failed-upgrade remediation can't
delete them, and every VolumeSnapshot with them.

Notable settings: msgr2 is required on the wire, discard is enabled on the
block devices, local disk-failure prediction is on, and all Ceph daemons
tolerate tuppr's `outdated` taint so upgrades don't evict them prematurely.

Day-2 access to the cluster is through the toolbox:

```sh
just k8s toolbox
ceph status
ceph osd df tree
```

## OpenEBS

Each node has a `local-hostpath` Talos `UserVolumeConfig` on the OS disk
(minimum 20 GiB, grows to fill free space), mounted at
`/var/mnt/local-hostpath`. [OpenEBS](https://openebs.io) LocalPV hostpath
provisions volumes from it as `openebs-hostpath`. These volumes are tied to a
node and not replicated.

## NAS

The NAS (`nas.internal`, `10.73.1.10`) exports NFS shares from its ZFS pools
for media libraries, documents and backups. Talos mounts NFS with tuned
options from an `nfsmount.conf` in the machine config. The `nfsrahead`
extension, configured by an `nfs.conf`, raises read-ahead on NFSv4 mounts to
16 MiB.

!!! warning "The NAS must allow non-root mounts"

    `nfsmount.conf` sets `noresvport`, so nodes connect from unprivileged
    source ports. TrueNAS rejects those by default (`secure` exports, seen as
    `mount.nfs: Operation not permitted`), so the NFS service has **Allow
    non-root mount** enabled, which adds `insecure` to every export. This is
    set in the TrueNAS UI and isn't managed from this repository. Existing
    NFS connections survive without it; it only shows up once a node reboots.

Apps that depend on an NFS share can use the
[`zeroscaler/nfs` component](../../platforms/kubernetes/components.md#zeroscalernfs) to
scale to zero when the NAS is unreachable, instead of hanging on a stale mount.

It also serves an SMB share for the Macs' Time Machine backups (see
[Backups → Time Machine](backups.md#time-machine)).

The NAS also runs [Garage](https://garagehq.deuxfleurs.fr/) as an
S3-compatible object store at `s3.bykaj.io`. CNPG uses it for WAL archives
and base backups. Karakeep and Windshift keep their assets and
attachments in the `karakeep` and `windshift` buckets, and OpenCloud its
file contents in the `opencloud` bucket.

## Pages in this section

- [Backups](backups.md): what is backed up, where, and how restores work,
  for both the cluster and the NAS
- [PostgreSQL](postgres.md): the CNPG component every database uses
