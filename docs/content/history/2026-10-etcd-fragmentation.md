---
description: etcd database files grew to three times their live data, mostly from Helm release history
---

# etcd Fragmentation

!!! abstract "Summary"

    **2026-10-15.** The etcd fragmentation alert kept firing overnight. Each
    member's database file was about 410 MB for about 123 MB of live data.
    No outage. Fixed by defragmenting, a weekly defrag CronJob and shorter
    Helm history.

## Timeline

- **Before 2026-10-15.** The alert fired briefly at night, then resolved. It
  fires when less than half of the file is in use and more than 100 MB is
  live, and live data hovered right around 100 MB.
- **2026-10-15.** The members were defragmented by hand: the two followers
  first, then the leader after `etcd forfeit-leadership`. Each took under a
  second, and the API stayed ready. Files dropped to 104 to 136 MB.
- **2026-10-16.** The alert came back after a night with three Cilium
  upgrades, a Talos upgrade and a mass pod restart. The new CronJob hadn't
  run yet, so it was started by hand.

## Cause

etcd's database file never shrinks by itself, and Talos doesn't defragment
it. Most of the live data was Helm release Secrets (`helm.sh/release.v1`):
326 of them, 56.6 MB in total, with app-template releases at about 0.9 MB per
5 revisions.

## What changed

[#2862](https://github.com/bykaj/home-ops/pull/2862):

- The [`etcd-defrag`](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/kube-system/etcd-defrag)
  CronJob defragments every Sunday at 04:00, one member at a time, leader
  last.
- `cluster-apps` sets `maxHistory: 3` on every HelmRelease.

## What to watch

If the alert returns, first check that the CronJob ran, and how much space
the Helm Secrets take. To run it now:

```sh
kubectl -n kube-system create job etcd-defrag-manual-$(date +%s) --from=cronjob/etcd-defrag
```
