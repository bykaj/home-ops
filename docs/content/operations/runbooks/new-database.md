---
description: First deploy of an app that gets a brand-new CNPG cluster with no prior backup
---

# New Database

!!! note "MariaDB"

    This runbook is for the `postgres` component. The `mariadb` component has
    the same flow with the `components.database/mariadb: init` label, see
    [MariaDB](../../infrastructure/storage/mariadb.md#using-the-component).

The [`postgres` component](../../infrastructure/storage/postgres.md) bootstraps every cluster
from a Barman backup by default. For a brand-new app, nothing exists at
`s3://postgresql/${APP}/` yet, so that would fail with "no target backup
found". The `components.database/postgres: init` label switches the cluster to a
plain `initdb` for its first deploy.

## 1. Deploy with the init label

```yaml title="kubernetes/apps/<namespace>/myapp/ks.yaml"
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app myapp
  labels:
    components.database/postgres: init # (1)!
spec:
  components:
    - ../../../../components/database/postgres
  healthCheckExprs:
    - apiVersion: postgresql.cnpg.io/v1
      kind: Cluster
      current: has(status.conditions) && status.conditions.exists(e, e.type == 'Ready' && e.status == 'True')
  healthChecks:
    - apiVersion: postgresql.cnpg.io/v1
      kind: Cluster
      name: myapp-postgres
      namespace: <namespace>
  interval: 1h
  path: ./kubernetes/apps/<namespace>/myapp/app
  postBuild:
    substitute:
      APP: *app
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  targetNamespace: <namespace>
```

1. Only for the first deploy. Remove it once a backup exists (step 3).

A patch in `cluster-apps` matches the label. It strips
`spec.bootstrap.recovery` and `spec.externalClusters` from the `Cluster`, and
replaces `bootstrap` with an `initdb` that creates a database and owner role
named `${POSTGRES_USERNAME:=${APP}}`. CNPG generates the role's password into
the `${APP}-postgres-app` Secret as usual.

!!! warning "Variable escaping in the patch"

    The patch's `${...}` variables are substituted by the app's own Flux
    Kustomization. If `cluster-apps` ever gains a `postBuild`, escape them as
    `$${...}` in the patch, so they survive that first (outer) substitution.

!!! warning "Create the local dump folder on the NAS"

    The `${APP}-postgres-backup-local` CronJob writes to
    `/mnt/vault/Backups/Database/${APP}`, but doesn't create that folder.
    The image checks that it exists and is writable before it creates
    anything, so the first run fails with "BACKUP_DIR points to a file or
    folder with insufficient permissions." Create it on the NAS before the
    first scheduled run, owned by the pod's UID/GID:

    ```sh
    sudo install -d -o 4000 -g 4000 /mnt/vault/Backups/Database/myapp
    ```

    Test it with
    `kubectl -n <namespace> create job --from=cronjob/myapp-postgres-backup-local myapp-backup-manual`.

## 2. Get a first backup

Wait for the nightly `ScheduledBackup`, or force one:

```sh
just k8s db-backup <namespace> myapp
kubectl -n <namespace> get backup
```

## 3. Remove the label

Once a backup has completed, remove `components.database/postgres: init` and
merge. From then on, a cluster rebuild follows the default `recovery` path.

!!! warning "Don't leave the label in place"

    Keeping the label is harmless day to day, because bootstrap is only read
    when the cluster is created. But if the cluster is ever destroyed and
    recreated, it would come back **empty** instead of restoring.
