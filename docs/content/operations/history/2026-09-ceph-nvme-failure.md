---
description: A failing NVMe drive in k8s-03, a node-wide RBD blocklist, and the full Ceph rebuild that followed
---

# OSD NVMe Failure and Ceph Rebuild

!!! abstract "Summary"

    **2026-09-22 to 2026-10-01.** The NVMe drive behind `osd.2` on k8s-03 hung
    three times in three days. Ceph stayed available on two replicas, with no
    data loss, but a second-order RBD blocklist on another node left volumes
    stuck for hours. The cluster was then rebuilt on Micron 7300 drives and
    restored from backups, which exposed a cooling problem in k8s-03.

## Timeline

- **2026-09-22 22:56 UTC.** The SK hynix PC801 behind `osd.2` stopped responding:
  I/O timeouts, a failed controller reset, then the kernel disabled the device.
  The PCIe device stayed visible in `talosctl get pcidevices`, which pointed at
  a hung controller rather than a dead or unseated card. Ceph went to
  `HEALTH_WARN` with 33 PGs undersized. A power cycle
  (`talosctl reboot -m powercycle`) brought the drive back, and Rook
  reactivated the OSD on its existing data.
- **While degraded,** k8s-02's kernel RBD client lost a watch and was
  blocklisted. Every new `rbd map` on that node then failed with
  `Cannot send after transport endpoint shutdown`, so pods and about 23 Kopiur
  backup jobs stayed stuck for hours after Ceph itself was back to
  `HEALTH_OK`. Removing the blocklist entry wasn't enough; rebooting k8s-02
  was.
- **2026-09-23 11:27 UTC and 2026-09-25 21:44 UTC.** The same drive hung twice more.
  Each power cycle fixed it for a while, so a replacement drive was ordered.
- **2026-09-30.** Instead of swapping one drive, all three nodes were reset
  and the cluster rebuilt on Micron 7300 drives, with cephx moved to
  `aes256k` keys. Apps came back from Kopiur and CNPG Barman backups.
- **2026-10-01.** During the backfill, k8s-03's Micron reached 74 °C, close
  to its 76 °C critical limit, so recovery was paused with `nobackfill` and
  `norecover`. k8s-03 was moved somewhere cooler, and recovery finished at
  10:53 UTC with the drive peaking at 69 °C.
- **2026-10-03.** Rack cooling was improved: raised feet, open case bottoms
  and a 140 mm fan per node aimed at the NVMe drives and RAM. NVMe
  temperatures dropped by 18 to 23 °C.

## Cause

A failing consumer NVMe drive. The rebuild then ran into a node chassis that
couldn't cool an enterprise NVMe drive under sustained writes.

## What changed

- Rook only uses Micron 7300 drives, selected by `/dev/disk/by-id`
  ([#2664](https://github.com/bykaj/home-ops/pull/2664),
  [#2669](https://github.com/bykaj/home-ops/pull/2669)).
- cephx uses `aes256k` only; the CSI driver needed a newer image for it
  ([#2670](https://github.com/bykaj/home-ops/pull/2670)).
- Fixes found during the restore: the Dragonfly network policy blocked apps
  on port 6379, node-exporter lost port 9100 to the ephemeral port range
  ([#2671](https://github.com/bykaj/home-ops/pull/2671)), and Traefik on the
  NAS had no restart policy, so S3 stayed down after a NAS reboot and CNPG
  restores failed ([#2672](https://github.com/bykaj/home-ops/pull/2672)).

## What to watch

- **Pool health and a node's RBD session are separate.** After a degraded
  period, check `ceph osd blocklist ls` and look for stuck volume mounts, even
  when Ceph reports `HEALTH_OK`.
- **NVMe temperatures.** k8s-03's Micron idles around 45 °C since the cooling
  changes, with a warning at 72 °C. A drift back up points at a fan.
- **Resetting nodes while Ceph has no quorum** hangs in `unmountPodMounts`,
  because the kernel RBD client can't flush. A hard power-off gets past it.
