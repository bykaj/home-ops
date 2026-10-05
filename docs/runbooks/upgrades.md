---
description: Talos and Kubernetes upgrades with tuppr, and manual fallbacks
---

# Upgrades

## Automatic (tuppr)

[tuppr](https://github.com/home-operations/tuppr) handles Talos and Kubernetes
upgrades declaratively. The target versions are pinned in two places, and
Renovate's `talos` and `kubernetes` groups update them together in one PR each
(the Talos group also bumps `talosctl` in `.mise/config.toml`):

- [`kubernetes/talos/version.yaml`](https://github.com/bykaj/home-ops/blob/main/kubernetes/talos/version.yaml):
  used by `just talos` and bootstrap
- [`kubernetes/apps/system-upgrade/tuppr/upgrades/`](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/system-upgrade/tuppr/upgrades):
  the `TalosUpgrade` and `KubernetesUpgrade` resources

Merging the PR is the upgrade. tuppr upgrades one node at a time
(`rebootMode: powercycle` for Talos), and only starts each step when:

- no Kopiur `Snapshot` is `Running`
- no Kopiur `Restore` is `Resolving` or `Restoring`
- the `CephCluster` reports `HEALTH_OK`

Nodes due for an upgrade get the `tuppr.home-operations.com/outdated` taint.
Ceph daemons tolerate it, so they aren't evicted early.

### What normal looks like

A full rolling Talos upgrade takes a while and logs some alarming but harmless
events:

- image pre-pull retries before a node starts
- CNPG's Barman plugin pods being evicted and rescheduled
- Envoy taking around 3 minutes to drain connections
- the Ceph OSD's `expand-bluefs` init step taking around 75 seconds after a
  reboot

Watch progress with:

```sh
kubectl get talosupgrade,kubernetesupgrade
kubectl -n system-upgrade logs -l app.kubernetes.io/name=tuppr -f
```

## Manual

When tuppr can't be used (it's broken, or a node needs a one-off), use the
`just talos` recipes. Each one asks for confirmation.

```sh
just talos upgrade-node <node>        # Talos, using the node's schematic image
just talos upgrade-k8s <version>      # Kubernetes, across the cluster
```

Upgrade one node at a time, and wait for `ceph status` to return to
`HEALTH_OK` before moving to the next.

## Changing the schematic

Adding a system extension or kernel argument changes the schematic ID, and
therefore the installer image. Edit `kubernetes/talos/schematic.yaml.j2`, then
run `just talos upgrade-node <node>` for each node to move it onto the new
image at the current Talos version.

## Applying machine config changes

Most changes to the Talos templates apply without a reboot:

```sh
just talos render-config <node> | talosctl -n <node> apply-config -f /dev/stdin --dry-run
just talos apply-node <node>
```
