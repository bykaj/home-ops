---
description: Expected alerts and events, and settings that look wrong but are deliberate
---

# Known Noise

Alerts and events where the obvious corrective action is wrong. Check this
page before "fixing" something.

## Expected during Talos upgrades

A rolling tuppr upgrade takes about 6 to 7 minutes per node, and Ceph is back
to `HEALTH_OK` about 3 minutes after the last node returns. Along the way
(see also [Upgrades](../runbooks/upgrades.md#what-normal-looks-like)):

- **Pending for minutes before the first node starts.** The installer pre-pull
  can stall ("no pull progress after 1m30s") or time out against
  `factory.talos.dev`, especially on release day, while the Image Factory
  builds the installer. tuppr retries; it took three attempts once.
- **CNPG clusters report "error while interacting with plugins".** This lasts
  about 30 seconds while the single Barman Cloud plugin pod is evicted and
  rescheduled. CNPG then moves primaries off the cordoned node by itself.
- **envoy-external takes about 3 minutes to terminate.** That is its
  connection drain timeout, not a stuck drain.
- **The Ceph OSD init step `expand-bluefs` takes about 75 seconds** after a
  power cycle. Pod age includes the node's downtime, so don't judge a slow
  start by it.
- **`kubectl` hangs** while a control-plane node drains. Give watch scripts
  `--request-timeout`.

## Talos

- A config apply whose dry run says "without a reboot" still restarts the
  API server and controller manager static pods. Apply one node at a time; see
  [Talos gotchas](../../platforms/kubernetes/talos.md#gotchas).
- NVMe kernel names can swap between reboots. Match drives by model or serial.

## Ceph

- **The active Ceph mgr's memory grows** by about 55 to 60 MiB a day; the
  standby stays flat. The likely cause is the `prometheus` mgr module. The
  memory limit was raised to 1536Mi
  ([#3060](https://github.com/bykaj/home-ops/pull/3060)), which allows
  several weeks between restarts. If the mgr is OOM-killed it is back within
  seconds, without a failover. Disabling and re-enabling a module drops memory
  because the module reloads, so don't read that as finding the leak; compare
  growth over a day or more instead.
- `CephNodeDiskspaceWarning` for NVMe devices and the `nfsmount.conf` mount is
  silenced on purpose; see [Silences](../alerting/index.md#silences).

## Gatus

- **Internal routes stay green even when the app is down.** The
  `envoy-internal` Gateway is marked `guarded`, so gatus-sidecar only checks
  that the hostname does *not* resolve in public DNS. Only external routes
  check for HTTP 200. To see whether an internal app is up, request it
  directly: a 503 from Envoy means it has no backends.
- In a `no such host` error from an external-route check, the DNS server Go
  prints is not the one it used. See
  [KB-017](kb/017-gatus-external-route-internal-host.md).

## Flux

- **Switching a HelmRelease to a chart with a different name** (for example
  from app-template to a dedicated chart) uninstalls the old release and
  installs the new one. Expect up to a minute of downtime. Selector changes
  don't fail as "field is immutable" here, so there's no need to delete the
  Deployment first. A version bump of the same chart is a normal upgrade,
  where selector changes do fail.

## Deliberate settings

These look like mistakes but are intended. Don't change them without reading
the linked entry.

| Setting | Why |
| --- | --- |
| `prune: false` on the `flux-instance` Kustomization | Flux must never delete its own `FluxInstance`; see [KB-003](kb/003-flux-instance-no-prune.md) |
| No `autopath` in CoreDNS | It breaks Cilium `toFQDNs` rules; see [KB-006](kb/006-tofqdns-timeouts.md) |
| **Allow non-root mount** on the TrueNAS NFS service | Nodes mount with `noresvport`; see [KB-007](kb/007-nfs-eperm-after-reboot.md) |
| "Credential required" off on the UPS NUT server | The nut-exporter relay can only read anonymously; see [KB-012](kb/012-nut-exporter-access-denied.md) |
| Internal Gatus checks only test public DNS | They guard against internal names leaking, not uptime; see [Gatus](#gatus) |
