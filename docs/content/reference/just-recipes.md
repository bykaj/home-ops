---
description: All just recipes, grouped by module
---

# Just Recipes

[`just`](https://just.systems) is the command runner. The root
[`.justfile`](https://github.com/bykaj/home-ops/blob/main/.justfile) imports
one module per area. Run `just` on its own to list everything.

## `just bootstrap`

End-to-end bring-up
([`bootstrap/mod.just`](https://github.com/bykaj/home-ops/blob/main/bootstrap/mod.just)).
See [Bootstrap](../runbooks/bootstrap.md).

| Recipe | Does |
| --- | --- |
| `cluster` | Talos config → `talosctl bootstrap` → kubeconfig → CRDs and bootstrap Secrets → helmfile apps → kubeconfig → `store-configs` |
| `docker <host>` | Run `bootstrap/docker/<host>/bootstrap.yaml` against the `<host>` inventory group ([details](../runbooks/bootstrap.md#docker-hosts)) |
| `restore-configs` | Restore `kubeconfig` and `talosconfig` from the `cluster` item in 1Password ([details](../runbooks/bootstrap.md#client-configs)) |
| `store-configs [files...]` | Upload `kubeconfig` and `talosconfig`, or only the files given, with their certificate expiry dates to the `cluster` item in 1Password (skips unchanged files) |

## `just docker`

NAS operations
([`docker/mod.just`](https://github.com/bykaj/home-ops/blob/main/docker/mod.just)).

| Recipe | Does |
| --- | --- |
| `restart-doco-cd` | Restart doco-cd on the NAS via Ansible, without applying anything (doco-cd deploys its own compose changes) |
| `sync-stacks` | Trigger a doco-cd poll of `main` through its REST API and wait for the result |

## `just docs`

This site
([`docs/mod.just`](https://github.com/bykaj/home-ops/blob/main/docs/mod.just)).

| Recipe | Does |
| --- | --- |
| `apps [--check]` | Regenerate the tables on [Applications](../kubernetes/applications.md) from `kubernetes/apps`; `--check` only verifies |
| `build` | Strict build into `docs/site`, as CI runs it (`zensical build --clean --strict`) |
| `serve` | Serve this site locally with live reload (`zensical serve`) |

## `just k8s`

Day-2 cluster operations
([`kubernetes/mod.just`](https://github.com/bykaj/home-ops/blob/main/kubernetes/mod.just)).

| Recipe | Does |
| --- | --- |
| `apply-ks <ns> <ks>` | Render a Flux Kustomization locally with `flate` and server-side apply it |
| `browse-pvc <ns> <claim>` | Start an Alpine pod with the PVC mounted at `/mnt` |
| `cron-minute <name>` | Derive a stable minute (0–59) from an app name, for `POSTGRES_BACKUP_SCHEDULE` ([details](../storage/postgres.md)) |
| `db-backup <ns> <app>` | Create a one-off CNPG `Backup` |
| `debug-node <node>` | Privileged debug shell on a node (`kubectl debug --profile=sysadmin`) |
| `delete-ks <ns> <ks>` | Render a Flux Kustomization locally and delete its resources |
| `prune-pods` | Delete pods in `Failed`, `Pending` or `Succeeded` phase |
| `pvc-backup <ns> <policy>` | Create a one-off Kopiur `Snapshot` and wait for it ([details](../storage/backups.md#manual-backups)) |
| `sync <hr\|ks\|gitrepo\|ocirepo\|es>` | Force reconciliation of every resource of that kind |
| `sync-es <ns> <name>` | Force-sync one ExternalSecret |
| `sync-hr <ns> <name>` | Force-reconcile one HelmRelease |
| `sync-ks <ns> <name>` | Reconcile one Flux Kustomization |
| `toolbox` | Shell into the `rook-ceph-tools` pod |
| `view-secret <ns> <secret>` | Print a Secret's decoded values |

!!! note "HelmRelease stuck with `MissingRollbackTarget`"

    `sync hr` skips releases that are stalled with no successful revision to
    roll back to. Use `flux reconcile hr <name> -n <ns> --force` for those.

## `just talos`

Node operations
([`kubernetes/talos/mod.just`](https://github.com/bykaj/home-ops/blob/main/kubernetes/talos/mod.just)).
Recipes that change a node ask for confirmation.

| Recipe | Does |
| --- | --- |
| `apply-node <node>` | Render and apply the machine config |
| `download-image <version> [node]` | Download a metal ISO for the node's schematic |
| `gen-kubeconfig` | Generate `kubeconfig` with a new client certificate, check it against the API server and store it in 1Password ([details](../kubernetes/talos.md#kubeconfig)) |
| `gen-talosconfig` | Generate `talosconfig` from the Talos secrets in 1Password, check it against a node and store it in 1Password ([details](../kubernetes/talos.md#talosconfig)) |
| `nvme-power <node> [state]` | Set the Micron NVMe power state (0 = 8.25 W full, 4 = 4.25 W coolest), saved across reboots |
| `reboot-node <node>` | Reboot a node |
| `render-config <node>` | Render the node's full machine config to stdout |
| `reset-node <node>` | Reset (wipe) a node |
| `shutdown-node <node>` | Shut down a node |
| `upgrade-k8s <version>` | Upgrade Kubernetes across the cluster |
| `upgrade-node <node>` | Upgrade Talos using the node's schematic image |
