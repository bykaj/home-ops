---
description: Reusable kustomize components under kubernetes/components
---

# Components

Reusable [kustomize components](https://kubectl.docs.kubernetes.io/guides/config_management/components/)
live in
[`kubernetes/components/`](https://github.com/bykaj/home-ops/tree/main/kubernetes/components).
An app's Flux Kustomization opts in with `spec.components`, and the component
is parameterized through `postBuild.substitute`:

```yaml
spec:
  components:
    - ../../../../components/kopiur/backup
  postBuild:
    substitute:
      APP: *app
      KOPIUR_CAPACITY: 10Gi
```

## `alerts`

Included at the **namespace** level. It adds Flux notification `Provider`s and
`Alert`s that send reconciliation failures to Alertmanager and post commit
statuses to GitHub.

## `kopiur/secret`

Included at the **namespace** level wherever an app uses `kopiur/backup`. It
provides the Kopia repository credentials through an `ExternalSecret`.

## `kopiur/backup`

PVC creation, scheduled backup and declarative restore for an app's data
volume. See [Backups](../storage/backups.md) for the full lifecycle.

| Variable | Default | Notes |
| --- | --- | --- |
| `APP` | _(required)_ | Name of the PVC, policy, schedule and restore |
| `KOPIUR_CLAIM` | `${APP}` | Override the PVC name |
| `KOPIUR_CAPACITY` | `5Gi` | PVC size, also used for the mover cache |
| `KOPIUR_ACCESSMODES` | `ReadWriteOnce` | |
| `KOPIUR_STORAGECLASS` | `ceph-block` | |
| `KOPIUR_SNAPSHOTCLASS` | `csi-ceph-blockpool` | |
| `KOPIUR_CACHE_STORAGECLASS` | `openebs-hostpath` | |
| `KOPIUR_MOVER_UID` / `KOPIUR_MOVER_GID` | `4000` | Must match the file ownership in the volume |
| `KOPIUR_NON_ROOT` | `true` | |

## `postgres`

A CloudNative-PG cluster per app, with Barman backups to Garage S3 and local
dumps to NFS. See [PostgreSQL](../storage/postgres.md).

## `dragonfly`

A [Dragonfly](https://www.dragonflydb.io) (Redis-compatible) instance per app,
with a `NetworkPolicy` and `PodMonitor`. `authentication/` is an optional
sub-component that enables password auth from `${DRAGONFLY_PASSWORD_SECRET}`.

## `gpu`

A `ResourceClaimTemplate` named `${APP}-gpu` that requests the node's Intel
iGPU through Dynamic Resource Allocation (`deviceClassName: gpu.intel.com`),
served by the `intel-gpu-resource-driver`. Reference it from the app's pod
`resourceClaims` for hardware transcoding.

## `zeroscaler/nfs`

A `HorizontalPodAutoscaler` (min 0, max 1) driven by the external metric
`probe_success{job="nfs_probe"}` from blackbox-exporter, through
prometheus-adapter. When the NAS's NFS service stops answering, the app scales
to zero instead of hanging on a stale mount. It comes back when the probe
recovers.

| Variable | Default |
| --- | --- |
| `ZEROSCALER_NAME` | `${APP}` |
| `CONTROLLER` | `Deployment` |
| `ZEROSCALER_METRIC_NAME` | `probe_success` |
