---
description: Bring the Talos/Kubernetes cluster or the TrueNAS host up from scratch
---

# Bootstrap

Takes freshly installed Talos nodes all the way to a self-managing Flux
cluster, provisions a fresh TrueNAS server with its Docker stacks, and sets up
a new workstation to operate both.
Everything is driven by
[`bootstrap/mod.just`](https://github.com/bykaj/home-ops/blob/main/bootstrap/mod.just).

## Prerequisites

- [mise](https://mise.jdx.dev) installed and activated, and `mise install` run
- A signed-in 1Password CLI (`op`). Every `op://` reference is resolved at
  apply time with `op inject`.
- A valid `talosconfig` at the repo root. The controller endpoint and node list
  are derived from `talosctl config info`, so nothing is hardcoded. For a new
  cluster, generate it with `just talos gen-talosconfig` (see
  [Talos → talosconfig](../kubernetes/talos.md#talosconfig)); for an existing
  one, `just bootstrap workstation` restores it (see
  [Workstation](#workstation)).
- The UDM [BGP config](../networking/bgp.md#udm-frr-config) and
  [static DNS records](../networking/dns.md#manual-records) in place.
  `k8s.internal` only works once Cilium is running, so bootstrap talks to the
  controller's node IP until then.
- Nodes booted into Talos maintenance mode, for example from a
  [Bootimus](../docker/index.md#06-bootimus) PXE boot or an ISO from
  `just talos download-image <version>`.

## Cluster

```sh
just bootstrap cluster
```

```mermaid
graph LR
    nodes --> k8s --> kubeconfig --> base --> apps --> store-configs
```

1. **nodes**: renders each node's Talos config (templates plus 1Password
   injection) and applies it with `talosctl apply-config --insecure`. Nodes
   that are already configured are skipped.
2. **k8s**: runs `talosctl bootstrap` against the controller, retrying until
   etcd reports that the cluster exists.
3. **kubeconfig**: fetches the kubeconfig and rewrites the server to the
   controller's node IP, because the generated `https://k8s.internal:6443`
   points at a Cilium VIP that doesn't exist yet.
4. **base**: waits for every apiserver to answer `/readyz` and for nodes to
   register (they stay `Ready=False` until the CNI is up), then applies:
    - `kustomize/`: bootstrap Secrets rendered through `op inject` (1Password
      Connect credentials and token, Cloudflare tunnel ID) plus their
      namespaces, so no controller deadlocks on a missing Secret
    - `helmfile/crds.yaml`: CRDs extracted from upstream charts
      (envoy-gateway, grafana-operator, kopiur, kube-prometheus-stack)
5. **apps**: `helmfile sync` of the minimal release chain Flux needs before it
   can take over:

    ```text
    cilium → coredns → spegel → cert-manager → external-secrets →
    onepassword-connect → flux-operator → flux-instance
    ```

    The kubeconfig is then fetched again, so its endpoint is back to
    `k8s.internal`.

6. **store-configs**: uploads `kubeconfig` and `talosconfig` to the
   `cluster` item in 1Password (see [Workstation](#workstation)).

Once `flux-instance` is healthy, Flux reconciles `kubernetes/` and manages the
same releases from then on.

!!! tip "Every stage is safe to re-run"

    If bootstrap fails partway, fix the issue and run `just bootstrap cluster`
    again.

### Single source of truth

The helmfiles define no chart versions or values of their own. Each release's
chart and version are read from the app's `ocirepository.yaml`, and its values
from the app's `helmrelease.yaml`, under `kubernetes/apps/` (see
[`bootstrap/kubernetes/helmfile/templates/`](https://github.com/bykaj/home-ops/tree/main/bootstrap/kubernetes/helmfile/templates)).
Bootstrap therefore installs exactly what Flux will reconcile later, and
Renovate only updates one place.

### Data

Bootstrap restores no application data itself. As Flux deploys each app, its
PVC is populated from the latest Kopiur snapshot, and CNPG clusters recover
from Barman. Pods stay `Pending` until their volume is restored. See
[Backups → Deploy-or-restore](../storage/backups.md#deploy-or-restore).

### Verifying

```sh
kubectl get nodes                                  # all Ready
flux get ks -A | grep -v True                      # nothing stuck
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph status
curl -k https://k8s.internal:6443/livez
```

## Workstation

```sh
just bootstrap workstation
```

Restores `kubeconfig` and `talosconfig` to the repo root from the file
attachments on the `cluster` item in the `Homelab` 1Password vault, with mode
`0600`. Files that already match are left alone, and a local file that differs
is only overwritten after a prompt. Run it on a new machine after
`mise install` and signing in to `op`.

```sh
just bootstrap store-configs
```

Uploads the local `kubeconfig` and `talosconfig` to that item, replacing the
attachments in place. Files that already match are skipped. `just bootstrap
cluster` runs this as its last stage. Run it by hand whenever either file
changes outside bootstrap, for example after renewing the client certificates
(both expire after a year). `just talos gen-talosconfig` already runs it after
renewing the talosconfig.

## NAS

```sh
just bootstrap nas
```

This runs the Ansible playbook against the hosts in `ansible/inventory.yaml`.
It provisions TrueNAS, writes doco-cd's secrets and starts doco-cd from
`docker/nas/00-doco-cd`, which then reconciles the `docker/nas/` stacks,
including its own. Nothing in `bootstrap/` is used again until the next
provisioning.
