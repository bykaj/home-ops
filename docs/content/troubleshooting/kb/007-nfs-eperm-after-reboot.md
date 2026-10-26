---
description: NFS mounts fail with Operation not permitted on a node that just rebooted
---

# KB-007: NFS mounts fail with EPERM after a reboot

## Symptom

Pods on one node are stuck in `ContainerCreating` or `Init` with:

```text
MountVolume.SetUp failed ... mount.nfs: Operation not permitted
```

Other nodes mount the same shares fine. During a Talos upgrade, stuck Kopiur
movers can also block tuppr's health check.

## Cause

`nfsmount.conf` in `kubernetes/talos/cluster.yaml.j2` sets `noresvport`, so
new NFS connections come from unprivileged source ports. TrueNAS exports
default to `secure` and reject those. Nodes keep reusing their existing
connection to the NAS, so the problem only shows up once a node reboots.

## Fix

In TrueNAS, enable **Allow non-root mount** in the NFS service settings. This
adds `insecure` to every export and restarts the NFS service. See
[Storage](../../storage/index.md#nas): the setting isn't managed from this
repository.

To confirm, compare the client source ports on the NAS
(`ss -tn | grep :2049`) and check `/etc/exports` for `insecure`. To reproduce a
mount with kubelet's own tools and config:

```sh
kubectl debug node/<node> --profile=sysadmin -it --image=busybox
nsenter -t <kubelet-pid> -m -n -- mount -t nfs <server>:<path> /mnt
```

## Seen

2026-10-16, during the Talos 1.14.4 upgrade, two days after `noresvport` was
added.
