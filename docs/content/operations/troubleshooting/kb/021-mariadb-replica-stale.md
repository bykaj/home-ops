---
description: A MariaDB replica reports Ready and no lag but no longer receives changes
---

# KB-021: MariaDB replica is stale but reports Ready

## Symptom

A `MariaDB` is `Ready` and every replica shows running threads and
`Seconds_Behind_Master: 0`, but one replica's GTID doesn't move. After a
failover, a former primary can fail with:

```text
Got fatal error 1236 from master when reading data from binary log: 'Error:
connecting slave requested to start from GTID 0-10-15337, which is not in the
master's binlog.
```

## Cause

In the switchover during a drain, mariadb-operator (26.10.2) doesn't repoint a
replica that isn't ready, and doesn't do it later either. The replica keeps
following the old primary, which has become a replica itself. With
`log_slave_updates` off it forwards nothing, so the replica is frozen. Lag is
measured against the server it follows, so it stays at 0.

If such a replica is promoted, the transactions it missed are lost. Another
replica that has them diverges from the new primary (error 1236).

## Fix

1. Compare the replicas with the primary:

    ```sh
    kubectl -n <namespace> get mariadb <app>-mariadb -o json |
      jq '.status | .currentPrimary, (.replication.replicas | map_values(.gtidCurrentPos))'
    kubectl -n <namespace> exec <pod> -c mariadb -- sh -c \
      'mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" -e "SHOW ALL SLAVES STATUS\G"' |
      grep Master_Host
    ```

2. Before changing anything, check whether the replica has transactions the
   primary lacks. Compare the tables with `CHECKSUM TABLE`, and take a
   `mariadb-dump` of the replica.
3. Point the replica at the primary. If it has diverged, it fails with 1236 and
   the operator deletes its data and rebuilds it from a backup:

    ```sh
    kubectl -n <namespace> exec <pod> -c mariadb -- sh -c \
      'mariadb -uroot -p"$MARIADB_ROOT_PASSWORD" -e "STOP ALL SLAVES; CHANGE MASTER TO MASTER_HOST=\"<primary-pod>.<app>-mariadb-internal.<namespace>.svc.cluster.local\"; START ALL SLAVES"'
    ```

tuppr's MariaDB health check holds a Talos upgrade while replicas are at
different GTIDs.

## Seen

2026-11-25, during the Talos 1.14.7 upgrade: `seafile-mariadb-2` was promoted
without nine transactions of the previous primary, and `seafile-mariadb-1` was
left following a replica. All 198 tables had the same checksum on all three.
