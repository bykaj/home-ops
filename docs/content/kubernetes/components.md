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

## `postgres`

A CloudNative-PG cluster per app, with Barman backups to Garage S3 and local
dumps to NFS. See [PostgreSQL](../storage/postgres.md).

## `dragonfly`

A [Dragonfly](https://www.dragonflydb.io) (Redis-compatible) instance per app,
with a `NetworkPolicy` and `PodMonitor`. It runs with `--cluster_mode=emulated`
and `--default_lua_flags=allow-undeclared-keys`; the latter is needed for
BullMQ (Immich), whose Lua scripts access keys they don't declare in `KEYS`,
which Dragonfly rejects by default. `authentication/` is an optional
sub-component that enables password auth from `${DRAGONFLY_PASSWORD_SECRET}`.

## `gpu`

A `ResourceClaimTemplate` named `${APP}-gpu` that requests the node's Intel
iGPU through Dynamic Resource Allocation (`deviceClassName: gpu.intel.com`),
served by the `intel-gpu-resource-driver`. Reference it from the app's pod
`resourceClaims` for hardware transcoding.

## `gateway-oidc`

Puts a [Pocket ID](https://cyrannus.id) login in front of an app that has no
OIDC support of its own, using Envoy Gateway's built-in OIDC. It adds a
`SecurityPolicy` and an `ExternalSecret` (`${APP}-gateway-oidc`) that reads the
client ID and secret from the app's own 1Password item. Each app gets its own
Pocket ID client, so who may sign in is decided per app, by that client's
**allowed user groups**.

Prefer an app's own OIDC support when it has one. Sonarr (v5) does: it sets
`SONARR__AUTH__METHOD: Oidc` and reads the client ID and secret and the one
Pocket ID user it allows (`OIDC_USER`, that user's ID) from its 1Password
item, with the callback URL `https://<host>/signin-oidc`.

The policy attaches to **one named rule** of the app's HTTPRoute (`app` by
default), not to the whole route. That way API paths, which other apps, the
Homepage widgets and mobile apps call with an API key, can stay in a separate
rule without a login. The HelmRelease's route needs both rules:

```yaml
route:
  app:
    rules:
      - name: api # no login, still guarded by the app's API key
        backendRefs:
          - identifier: app
            port: *port
        matches:
          - path:
              type: PathPrefix
              value: /api
      - name: app # everything else: Pocket ID login
        backendRefs:
          - identifier: app
            port: *port
```

| Variable | Default | Notes |
| --- | --- | --- |
| `APP` | _(required)_ | Names the HTTPRoute to protect, and the policy and secret |
| `APP_DOMAIN` / `APP_SUBDOMAIN` | `${APP}.bykaj.app` | The redirect URL is `https://<host>/oauth2/callback` |
| `GATEWAY_OIDC_ITEM` | `${APP}` | 1Password item with `OIDC_CLIENT_ID` and `OIDC_CLIENT_SECRET` |
| `GATEWAY_OIDC_RULE` | `app` | Route rule (`sectionName`) the policy attaches to |

In Pocket ID, create a confidential client per app with the callback URL
`https://<host>/oauth2/callback`, and add its client ID and secret to the
app's 1Password item as `OIDC_CLIENT_ID` and `OIDC_CLIENT_SECRET`. These are
the same 1Password field names the apps with native OIDC use. Their
ExternalSecrets add a per-app prefix (`AB_`, `KK_`, …) through `rewrite`,
but this component reads the fields unprefixed. Point `GATEWAY_OIDC_ITEM` at
another item only when several apps should deliberately share one client, and
with it one set of allowed groups. `/oauth2/logout` clears the Envoy session cookies
for that host; the Pocket ID session itself stays signed in.

For an app with its own form login that also accepts an API key, the second
login can be skipped: an Envoy Gateway `HTTPRouteFilter` with
`credentialInjection` on the `app` rule adds the app's API key to every request
that passed the Pocket ID login. The `api` rule then matches requests that bring
their own key, not a path. See
[`media/stash`](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/media/stash/app),
where the browser UI and the API share `/graphql`.

!!! warning "Only traffic through Envoy is protected"

    Anything that reaches the app's Service directly bypasses the login, such
    as other pods using the cluster-internal Service address. Don't add a
    Tailscale ingress (`className: tailscale`) to an app behind this login, or
    a Tailscale route to the Service network (see
    [Remote access](../networking/index.md#remote-access)).

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
