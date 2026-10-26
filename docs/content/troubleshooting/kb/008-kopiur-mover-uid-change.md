---
description: Kopiur backups fail with PermissionDenied after changing the mover UID
---

# KB-008: Kopiur backups fail after a mover UID change

## Symptom

After changing `KOPIUR_MOVER_UID` or `KOPIUR_MOVER_GID` in an app's `ks.yaml`,
its backups fail with `PermissionDenied` on `/var/cache/kopia`.

## Cause

The mover's cache PVC `kopiur-cache-<app>` (OpenEBS hostpath, owned by the
`SnapshotPolicy`) is still owned by the old UID.

## Fix

Delete the cache PVC after the change is merged. It only holds a disposable
cache, and Kopiur recreates it on the next run:

```sh
kubectl -n <namespace> delete pvc kopiur-cache-<app>
```

Then test with a manual `Snapshot` whose `spec.policyRef.name` is the app.
See [Backups](../../storage/backups.md).

## Seen

2026-10-04: Paperless, when its UID changed
([#2703](https://github.com/bykaj/home-ops/pull/2703)).
