---
description: A Talos upgrade fails and leaves a node cordoned because a Postgres pod doesn't stop in time
---

# KB-020: Talos upgrade fails on a Postgres pod that won't stop

## Symptom

The `TalosUpgrade` is `Failed`, and the node is `Ready,SchedulingDisabled` on
the old Talos version without having rebooted. The upgrade job logs:

```text
failed to drain node "k8s-03": error when waiting for pod "windshift-postgres-2"
in namespace "default" to terminate: context deadline exceeded
```

Pods bound to that node stay `Pending`, including its Ceph OSD and mon, and
databases on local storage.

## Cause

The CNPG instance manager sometimes hangs after Postgres has stopped. Its last
log line is `Releasing primary lease`. Kubernetes only kills the pod when its
grace period ends. That comes from the cluster's `stopDelay`, which defaults to
30 minutes, while `talosctl` gives up on a drain after 5. tuppr stops after three
failed attempts and leaves the node cordoned.

The Postgres component now sets `stopDelay: 180` and `smartShutdownTimeout: 60`,
so a hung pod is killed within the drain timeout. The hang itself isn't fixed.

## Fix

1. Uncordon the node, so the pending pods start again:

    ```sh
    kubectl uncordon <node>
    ```

2. Wait for `HEALTH_OK` in Ceph and for every database instance to be ready.
   Don't reboot a node before that. The new Talos version is already installed
   as the failed node's default boot entry.
3. If a MariaDB replica stays `1/2` with its replication threads stopped and no
   error, the operator didn't restart them after the switchover. Start them on
   that replica:

    ```sh
    kubectl -n <namespace> exec <pod> -c mariadb -- \
      sh -c 'mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" -e "START ALL SLAVES"'
    ```

4. Retry the upgrade. If a drain hangs on a Postgres pod again, delete exactly
   that pod with `--grace-period=0 --force`, after checking in its log that
   Postgres has stopped.

## Seen

- 2026-10-28, during the Talos 1.14.5 upgrade: two replicas, force-deleted.
- 2026-11-25, during the Talos 1.14.7 upgrade: `windshift-postgres-2` failed the
  upgrade on k8s-03.
