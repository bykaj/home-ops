---
description: The checks to run after an upgrade or a risky change before calling it done
---

# Health Check

Run these after a Talos or Kubernetes upgrade, a change to Cilium, Ceph,
CoreDNS, Flux or External Secrets, a node reboot, or anything else that could
affect more than one app. Every step is read-only. A change is done when every
step shows the healthy result.

If something looks wrong, check [Known Noise](../troubleshooting/known-noise.md)
first: some events during and right after an upgrade are expected.

## 1. Nodes

```sh
kubectl get nodes
talosctl -n k8s-01 health --server=false
```

All three nodes are `Ready`, and `talosctl health` ends without errors.

## 2. etcd

```sh
talosctl -n k8s-01,k8s-02,k8s-03 etcd status
```

All three members report the same leader, and `ERRORS` is empty. A database
well above 150 MB means it needs a defrag (see the
[Talos gotchas](../kubernetes/talos.md#gotchas)).

## 3. Upgrades

```sh
kubectl get talosupgrade,kubernetesupgrade
```

Both are `Completed` and `Ready`. Skip this step if no upgrade ran.

## 4. Flux

```sh
flux get all -A --status-selector ready=false
```

Prints nothing. Anything listed is a Kustomization, HelmRelease or source
that isn't ready. For a stalled HelmRelease, see
[KB-002](../troubleshooting/kb/002-helmrelease-missing-rollback-target.md).

## 5. Ceph

```sh
kubectl -n rook-ceph exec deploy/rook-ceph-tools -- ceph health
```

`HEALTH_OK`. After a node reboot it takes about 3 minutes to get there. For
details, run `ceph status` the same way, or `just k8s toolbox` for a shell.

## 6. Pods

```sh
kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded
```

`No resources found`. Pods stuck in `Pending` or `ContainerCreating` after a
reboot are often NFS mounts; see
[KB-007](../troubleshooting/kb/007-nfs-eperm-after-reboot.md).
`just k8s prune-pods` clears leftover `Failed` pods.

## 7. Databases

```sh
kubectl get clusters.postgresql.cnpg.io -A
```

Every cluster shows `Cluster in healthy state` with all instances ready.

## 8. Secrets

```sh
kubectl get externalsecrets -A | grep -v SecretSynced
```

Only the header line is printed. If every ExternalSecret fails, check
1Password Connect first
([KB-010](../troubleshooting/kb/010-onepassword-connect-credentials.md)).

## 9. Alerts

```sh
kubectl -n observability exec alertmanager-kube-prometheus-stack-0 -c alertmanager -- \
  amtool alert query --alertmanager.url=http://localhost:9093
```

Only `Watchdog` and `InfoInhibitor` are active. Both always fire; anything else
needs a look. This also covers Gatus, which raises `GatusEndpointDown` for
failing external and infrastructure endpoints.

## 10. The change itself

The checks above cover the platform. Also verify what the change was meant to
do: open the affected app, send a real request through a new network policy
(a dry run doesn't test it), or trigger a manual backup after a backup change.
