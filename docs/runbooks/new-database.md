---
description: First deploy of an app that gets a brand-new CNPG cluster with no prior backup
---

# New Database

The [`postgres` component](../storage/postgres.md) bootstraps every cluster
from a Barman backup by default. For a brand-new app, nothing exists at
`s3://postgresql/${APP}/` yet, so that would fail with "no target backup
found". The `components.postgres/cnpg: init` label switches the cluster to a
plain `initdb` for its first deploy.

## 1. Deploy with the init label

```yaml title="kubernetes/apps/<namespace>/myapp/ks.yaml"
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app myapp
  labels:
    components.postgres/cnpg: init # (1)!
spec:
  components:
    - ../../../../components/postgres
  healthCheckExprs:
    - apiVersion: postgresql.cnpg.io/v1
      kind: Cluster
      failed: status.conditions.filter(e, e.type == 'Ready').all(e, e.status == 'False')
      current: status.conditions.filter(e, e.type == 'Ready').all(e, e.status == 'True')
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
the `${APP}-app` Secret as usual.

## 2. Get a first backup

Wait for the nightly `ScheduledBackup`, or force one:

```sh
just k8s db-backup <namespace> myapp
kubectl -n <namespace> get backup
```

## 3. Remove the label

Once a backup has completed, remove `components.postgres/cnpg: init` and
merge. From then on, a cluster rebuild follows the default `recovery` path.

!!! warning "Don't leave the label in place"

    Keeping the label is harmless day to day, because bootstrap is only read
    when the cluster is created. But if the cluster is ever destroyed and
    recreated, it would come back **empty** instead of restoring.
