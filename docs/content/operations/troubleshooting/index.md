---
description: Symptom ladder from what you observe to the matching knowledge-base entry
icon: material/stethoscope
---

# Troubleshooting

Problems that have happened before, with their cause and fix. Each one is a
numbered knowledge-base (KB) entry laid out as symptom, cause and fix.

Before fixing an alert or an odd-looking event, check
[Known Noise](known-noise.md): it lists what is expected and what is broken on
purpose.

## Symptom ladder

Start from what you see and follow the most likely entry.

### Flux and GitOps

- A Kustomization fails with `must be of type object: "null"`, but a kubectl
  dry run passes: [KB-001](kb/001-flux-empty-object-null.md)
- A HelmRelease is `Stalled` with `MissingRollbackTarget` and a sync doesn't
  help: [KB-002](kb/002-helmrelease-missing-rollback-target.md)
- An object you renamed or removed under `flux-instance` is still there:
  [KB-003](kb/003-flux-instance-no-prune.md)
- A resumed HelmRelease upgraded fine but its Deployment is at `0/0`:
  [KB-004](kb/004-resumed-helmrelease-stays-scaled-down.md)
- A chart bump removed a field, but it's still on the live object:
  [KB-005](kb/005-bootstrap-helm-field-manager-leftovers.md)
- An `OCIRepository` on `home-operations/charts-mirror` fails with `DENIED:
  requested access to the resource is denied`:
  [KB-019](kb/019-charts-mirror-chart-pruned.md)

### Networking and certificates

- Requests allowed by a `toFQDNs` egress rule hang until they time out:
  [KB-006](kb/006-tofqdns-timeouts.md)
- A `Certificate` stays not ready after the cause was fixed, or fails with
  `404 No order for ID`: [KB-009](kb/009-certificate-retry-backoff.md)
- A Gatus check fails with `no such host` for an internal name:
  [KB-017](kb/017-gatus-external-route-internal-host.md)
- UniFi refuses to move a node's fixed IP to a new NIC:
  [KB-013](kb/013-unifi-fixed-ip-nic-swap.md)
- `CephNodeNetworkPacketDrops` fires for a node in short bursts:
  [KB-018](kb/018-nic-rx-ring-overflow.md)

### Storage and backups

- NFS mounts fail with `Operation not permitted` on one node, after it
  rebooted: [KB-007](kb/007-nfs-eperm-after-reboot.md)
- Kopiur backups fail with `PermissionDenied` on `/var/cache/kopia`:
  [KB-008](kb/008-kopiur-mover-uid-change.md)

### Secrets

- 1Password Connect fails with `failed to Unmarshal credentials file data`
  and ExternalSecrets stop syncing:
  [KB-010](kb/010-onepassword-connect-credentials.md)

### Monitoring

- nut-exporter crash loops with `Access denied`:
  [KB-012](kb/012-nut-exporter-access-denied.md)

### NAS

- Zot ignores a config change that doco-cd deployed:
  [KB-011](kb/011-zot-ignores-config-changes.md)

### Renovate and local tooling

- `renovate/artifacts` fails with `installing plugins is disabled in safe
  mode`: [KB-014](kb/014-renovate-mise-safe-mode.md)
- An image never gets update PRs:
  [KB-015](kb/015-renovate-release-age-holds-forever.md)
- yamllint fails on a trailing space after `- ` that keeps coming back:
  [KB-016](kb/016-oxfmt-dash-comment-trailing-space.md)

## All entries

See the [Knowledge Base](kb/index.md) for every entry, and how to add one.
