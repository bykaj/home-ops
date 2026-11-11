---
description: Restore an app's volume, or only some files on it, from a Kopiur snapshot
---

# Restoring a Volume

Restores of app volumes backed up by the [`kopiur` component](../../platforms/kubernetes/components.md#kopiur).
There are three cases:

| Case | What happens | App |
| --- | --- | --- |
| [Some files](#restore-some-files) | Only the selected paths are written back into the live volume | Keeps running |
| [Whole volume](#roll-back-the-whole-volume) | The volume is rolled back to a snapshot | Scaled down |
| [Lost volume or new cluster](#lost-volume-or-new-cluster) | Flux recreates the PVC and Kopiur fills it from the latest snapshot | Starts when done |

Restores from the first two cases are one-off `Restore` objects applied with
`kubectl`. They don't go into Git: a `Restore` that writes into an existing PVC
runs once and is done.

## 1. Pick a snapshot

List the app's snapshots, newest last:

```sh
kubectl -n <namespace> get snapshots.kopiur.home-operations.com \
  -l kopiur.home-operations.com/config=<app> \
  --sort-by=.metadata.creationTimestamp
```

Scheduled snapshots are named `<app>-<YYYYMMDDHHMMSS>` (UTC), manual ones
`<app>-manual-<suffix>`. The repository keeps 3 latest, 24 hourly, 7 daily and
4 weekly snapshots per app.

To check what is in a snapshot, and the exact path of a file, browse it in the
Kopia UI at <https://kopia.bykaj.app> (internal). Snapshot sources are listed
as `<app>@<namespace>`. Paths in a snapshot are relative to the root of the
volume, so `media/documents/x.pdf` in the snapshot is `media/documents/x.pdf`
in the PVC.

!!! tip "Take a snapshot first"

    Before overwriting anything, take a manual snapshot of the current state
    with `just k8s pvc-backup <namespace> <app>`, so the restore itself can be
    undone.

## Restore some files

Brings back selected files or directories into the live volume and leaves
everything else on it alone. The app can keep running: for a `ReadWriteOnce`
volume, Kopiur schedules the mover on the node of the pod that holds it.

```yaml title="restore.yaml"
apiVersion: kopiur.home-operations.com/v1alpha1
kind: Restore
metadata:
  name: <app>-partial-<date> # (1)!
  namespace: <namespace>
spec:
  credentialProjection:
    enabled: true # (2)!
  mover:
    securityContext:
      runAsUser: 4000 # (3)!
      runAsGroup: 4000
  options:
    overwriteFiles: true
  selection:
    paths: # (4)!
      - path/to/file.ext
      - path/to/directory
  source:
    snapshotRef:
      name: <snapshot> # (5)!
  target:
    pvcRef:
      name: <app> # (6)!
```

1. Any unused name. A `Restore` is one-shot, so each restore needs a new one.
2. Copies the repository password into the namespace for the mover run.
3. The app's `KOPIUR_MOVER_UID` / `KOPIUR_MOVER_GID` from its `ks.yaml`
   (default `4000`), so the restored files get the right owner.
4. Relative to the volume root, without a leading or trailing `/`. 1 to 64
   paths; a directory brings back its whole subtree.
5. A snapshot from step 1 that still has the files.
6. The live PVC: `${KOPIUR_CLAIM}` if the app sets it, else the app name.

```sh
kubectl apply -f restore.yaml
kubectl -n <namespace> get restore <name> -w
```

The phases run `Pending` → `Resolving` → `Restoring` → `Completed`. Files
created since the snapshot and everything outside the selected paths are not
touched. By default the restore is additive: within a selected directory,
files that aren't in the snapshot stay. Add `enableFileDeletion: true` under
`options` to make a selected directory an exact copy of the snapshot.

!!! note "A missing path fails before anything is written"

    If a selected path is not in the snapshot, the `Restore` goes to `Failed`
    and `status.failure.message` names the path. Nothing was written. Check the
    name in the Kopia UI, or pick an older snapshot. A symlink on the way to a
    selected path in the live volume is refused the same way.

## Roll back the whole volume

Replaces the volume's contents with a snapshot, for example after a bad
migration. Stop the app first, so it doesn't write while the files are being
replaced.

1. Suspend the HelmRelease and scale the app down:

    ```sh
    flux -n <namespace> suspend hr <app>
    kubectl -n <namespace> scale deploy/<app> --replicas 0
    ```

2. Apply a `Restore` like the one above without `selection`, and with
   `enableFileDeletion: true` under `options`, so files that are not in the
   snapshot are deleted:

    ```yaml
      options:
        enableFileDeletion: true
        overwriteFiles: true
    ```

3. Wait for `Completed`, then resume and scale back up by hand. Resuming
   alone leaves the manual scale at 0:

    ```sh
    flux -n <namespace> resume hr <app>
    kubectl -n <namespace> scale deploy/<app> --replicas 1
    ```

Use `statefulset/<app>` instead of `deploy/<app>` for StatefulSet controllers.

## Lost volume or new cluster

Nothing to apply by hand. The app's PVC has a `dataSourceRef` to the
component's populator `Restore`, so a missing PVC is recreated by Flux and
filled from a snapshot before the app starts. See
[Deploy-or-restore](../../infrastructure/storage/backups.md#deploy-or-restore).

!!! warning "The populator restores the snapshot it resolved first"

    The component's `Restore` pins the snapshot it picked when it was created.
    Deleting only the PVC restores that same, possibly old, snapshot again. To
    restore the latest one into a new PVC, scale the app down, delete both the
    PVC and the `Restore` (`<app>` in the app's namespace, by exact name), and
    let Flux recreate them.

## Clean up

Delete the `Restore` once it is `Completed` (or `Failed` and dealt with):

```sh
kubectl -n <namespace> delete restore <name>
```

Check for a leftover projected credentials Secret (`kubectl -n <namespace> get
secret | grep restore-creds`) and delete it by exact name. See
[Components → kopiur](../../platforms/kubernetes/components.md#kopiur).
