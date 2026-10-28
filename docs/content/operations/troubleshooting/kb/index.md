---
description: Every knowledge-base entry, and how to add one
---

# Knowledge Base

Problems that have happened before, one entry each, laid out as symptom, cause
and fix. To find one from what you see, start at the
[symptom ladder](../index.md#symptom-ladder).

| KB | Title |
| --- | --- |
| [001](001-flux-empty-object-null.md) | Flux applies `{}` as `null` |
| [002](002-helmrelease-missing-rollback-target.md) | HelmRelease stalled with `MissingRollbackTarget` |
| [003](003-flux-instance-no-prune.md) | Old objects left behind in `flux-instance` |
| [004](004-resumed-helmrelease-stays-scaled-down.md) | Resumed HelmRelease stays scaled to zero |
| [005](005-bootstrap-helm-field-manager-leftovers.md) | Leftover fields on bootstrap-installed releases |
| [006](006-tofqdns-timeouts.md) | `toFQDNs` egress rule times out |
| [007](007-nfs-eperm-after-reboot.md) | NFS mounts fail with EPERM after a reboot |
| [008](008-kopiur-mover-uid-change.md) | Kopiur backups fail after a mover UID change |
| [009](009-certificate-retry-backoff.md) | Certificate stuck after a failed issuance |
| [010](010-onepassword-connect-credentials.md) | 1Password Connect can't parse its credentials |
| [011](011-zot-ignores-config-changes.md) | Zot ignores config changes |
| [012](012-nut-exporter-access-denied.md) | nut-exporter crash loops with `ACCESS-DENIED` |
| [013](013-unifi-fixed-ip-nic-swap.md) | UniFi refuses a fixed IP after a NIC swap |
| [014](014-renovate-mise-safe-mode.md) | Renovate fails to update the mise lockfile |
| [015](015-renovate-release-age-holds-forever.md) | Renovate never updates an image with a release-age rule |
| [016](016-oxfmt-dash-comment-trailing-space.md) | yamllint fails on a trailing space after `- ` |
| [017](017-gatus-external-route-internal-host.md) | Gatus check fails with `no such host` |
| [018](018-nic-rx-ring-overflow.md) | Packet drop alerts from NIC RX ring overflows |
| [019](019-charts-mirror-chart-pruned.md) | Chart pull `DENIED` from the charts mirror |

## Adding an entry

1. Copy an existing entry to `<next number>-<slug>.md` in this folder, and
   keep its sections: Symptom, Cause, Fix, Seen.
2. Quote the exact error text under Symptom, so search finds it.
3. Add it to the [symptom ladder](../index.md#symptom-ladder), to the table
   above, and to the `nav` in `docs/zensical.toml`.
