---
description: All just recipes, grouped by module
---

# Just Recipes

[`just`](https://just.systems) is the command runner. The root
[`.justfile`](https://github.com/bykaj/home-ops/blob/main/.justfile) imports
one module per area. Run `just` on its own to list everything.

## Root

| Recipe | Does |
| --- | --- |
| `just docs` | Serve this site locally with live reload (`zensical serve`) |

## `just k8s`

Day-2 cluster operations
([`kubernetes/mod.just`](https://github.com/bykaj/home-ops/blob/main/kubernetes/mod.just)).

| Recipe | Does |
| --- | --- |
| `sync <hr\|ks\|gitrepo\|ocirepo\|es>` | Force reconciliation of every resource of that kind |
| `sync-hr <ns> <name>` | Force-reconcile one HelmRelease |
| `sync-ks <ns> <name>` | Reconcile one Flux Kustomization |
| `sync-es <ns> <name>` | Force-sync one ExternalSecret |
| `apply-ks <ns> <ks>` | Render a Flux Kustomization locally with `flate` and server-side apply it |
| `delete-ks <ns> <ks>` | Render a Flux Kustomization locally and delete its resources |
| `toolbox` | Shell into the `rook-ceph-tools` pod |
| `view-secret <ns> <secret>` | Print a Secret's decoded values |
| `browse-pvc <ns> <claim>` | Start an Alpine pod with the PVC mounted at `/mnt` |
| `debug-node <node>` | Privileged debug shell on a node (`kubectl debug --profile=sysadmin`) |
| `db-backup <ns> <app>` | Create a one-off CNPG `Backup` |
| `prune-pods` | Delete pods in `Failed`, `Pending` or `Succeeded` phase |
| `cron-minute <name>` | Derive a stable pseudo-random minute (0–59) from a name |

!!! note "HelmRelease stuck with `MissingRollbackTarget`"

    `sync hr` skips releases that are stalled with no successful revision to
    roll back to. Use `flux reconcile hr <name> -n <ns> --force` for those.

## `just talos`

Node operations
([`kubernetes/talos/mod.just`](https://github.com/bykaj/home-ops/blob/main/kubernetes/talos/mod.just)).
Recipes that change a node ask for confirmation.

| Recipe | Does |
| --- | --- |
| `render-config <node>` | Render the node's full machine config to stdout |
| `apply-node <node>` | Render and apply the machine config |
| `upgrade-node <node>` | Upgrade Talos using the node's schematic image |
| `upgrade-k8s <version>` | Upgrade Kubernetes across the cluster |
| `reboot-node <node>` | Reboot a node |
| `shutdown-node <node>` | Shut down a node |
| `reset-node <node>` | Reset (wipe) a node |
| `download-image <version> [node]` | Download a metal ISO for the node's schematic |
| `nvme-power <node> [state]` | Set the Micron NVMe power state (0 = 8.25 W full, 4 = 4.25 W coolest), saved across reboots |

## `just bootstrap`

End-to-end bring-up
([`bootstrap/mod.just`](https://github.com/bykaj/home-ops/blob/main/bootstrap/mod.just)).
See [Bootstrap](../runbooks/bootstrap.md).

| Recipe | Does |
| --- | --- |
| `cluster` | Talos config → `talosctl bootstrap` → kubeconfig → CRDs and bootstrap Secrets → helmfile apps → kubeconfig |
| `nas` | Run the Ansible playbook that provisions TrueNAS |

## `just docker`

NAS operations
([`docker/mod.just`](https://github.com/bykaj/home-ops/blob/main/docker/mod.just)).

| Recipe | Does |
| --- | --- |
| `reconcile-nas` | Restart doco-cd on the NAS via Ansible, triggering an immediate redeploy |
