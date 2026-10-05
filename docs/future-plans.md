---
description: What's planned next for the platform, and what earlier plans became
---

# Future Plans

## Planned

Nothing is planned right now. The previous round of plans wrapped up in
Q3 2026 (see below).

## Completed

### Q3 2026

- [x] **Upgrading to more powerful hardware**: replace the Lenovo M920q units
      and the self-built server with three Minisforum MS-01 units as Proxmox VE
      hosts.

    Done differently: the cluster now runs on 2 × Lenovo M920x and
    1 × Lenovo M90q Gen 5, going from 15 to 48 CPU cores. See
    [Hardware](hardware/index.md).

- [x] **Expanding network capacity**: add an aggregation switch, because the
      existing 10G SFP+ ports were at capacity. This also follows networking
      best practices.

    Done: a UniFi USW Aggregation now connects the cluster nodes and the NAS.

- [x] **Dedicated NAS hardware**: move TrueNAS from a virtualized setup with
      hardware passthrough to bare metal on the existing 3U server.

    Done: TrueNAS SCALE runs bare metal. See [Hardware → NAS](hardware/index.md#nas).

- [x] **Better power management**: upgrade to a more powerful UPS and add a
      managed PDU for better power distribution and management.

    Done: a UniFi UPS 2U (1500 VA) is in the rack and monitored by
    `nut-exporter`.

## Dropped

- [ ] ~~**Building a distributed storage foundation**: run Ceph directly on the
      Proxmox VE cluster, with Kubernetes consuming it through
      `rook-ceph-operator` only.~~

    No more virtualization: the cluster is bare metal now, and Rook-Ceph runs
    inside Kubernetes. Proxmox and Ceph competing for disk I/O was... not
    great. See [Storage](storage/index.md).

- [ ] ~~**Optimizing inter-node connectivity**: 20G Thunderbolt networking
      between the cluster nodes, plus dedicated 10G SFP+ links for virtualized
      Kubernetes nodes.~~

    Not possible with the current hardware.
