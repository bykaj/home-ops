---
description: How apps are laid out under kubernetes/apps and the conventions they follow
icon: material/kubernetes
---

# Kubernetes

The cluster runs [Talos Linux](talos.md) on three control plane nodes. Workloads
are scheduled on all three. Flux reconciles everything under
[`kubernetes/apps/`](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps).
See [GitOps](../../infrastructure/architecture/gitops.md) for how that works.

## Directory layout

```text
kubernetes/apps/<namespace>/
├── kustomization.yaml          # Namespace + list of app ks.yaml files + shared components
├── namespace.yaml
└── <app>/
    ├── ks.yaml                 # Flux Kustomization
    └── app/
        ├── kustomization.yaml
        ├── ocirepository.yaml  # Chart source (usually app-template)
        ├── helmrelease.yaml
        ├── externalsecret.yaml # Optional: secrets from 1Password
        └── resources/          # Optional: files for configMapGenerator
```

An app is enabled by listing its `ks.yaml` in the namespace `kustomization.yaml`.
Commenting it out disables the app, and Flux prunes it.

Namespace kustomizations pull in the `alerts` [component](components.md#alerts)
for every app in the namespace: Flux alerts to Alertmanager and GitHub commit
statuses.

## The Flux Kustomization

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app atuin
spec:
  components:
    - ../../../../components/kopiur
  dependsOn:
    - name: rook-ceph-cluster
      namespace: rook-ceph
  interval: 1h
  path: ./kubernetes/apps/default/atuin/app
  postBuild:
    substitute:
      APP: *app
      APP_NAME: Atuin
      APP_SUBDOMAIN: sh
      KOPIUR_CAPACITY: 1Gi
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  targetNamespace: default
```

!!! tip "What not to add"

    `timeout`, `retryInterval`, `deletionPolicy` and the HelmRelease
    install/upgrade strategies are injected by `cluster-apps` (see
    [cluster-wide defaults](../../infrastructure/architecture/gitops.md#cluster-wide-defaults)).
    `commonMetadata` isn't used: the chart already sets the
    `app.kubernetes.io/*` labels.

    `wait` is **not** injected. Leave it unset for a normal app. Set
    `wait: true` only when another Kustomization `dependsOn` this one and it
    has no `healthChecks`/`healthCheckExprs`, as the operator Kustomizations
    (CloudNative-PG, Dragonfly, Rook-Ceph and others) do. With health checks
    defined, leave `wait` unset, because `wait: true` makes Flux ignore them.

## The HelmRelease

Almost every app uses the
[bjw-s app-template](https://bjw-s-labs.github.io/helm-charts/docs/app-template/)
chart, pinned through an `OCIRepository` at
`oci://ghcr.io/bjw-s-labs/helm/app-template`. A HelmRelease describes
`controllers`, `service`, `route` (an `HTTPRoute` attached to `envoy-internal`
or `envoy-external`) and `persistence`.

Conventions:

- Containers run as non-root with a read-only root filesystem and all
  capabilities dropped, unless the image can't.
- Liveness and readiness probes are set, and resource requests are always
  present.
- Hostnames are `${APP_DOMAIN:=${APP_SUBDOMAIN:=${APP}}.bykaj.app}`, so they
  default to `<app>.bykaj.app` and can be overridden from `ks.yaml`.
- [Gatus](https://gatus.io) monitors every route automatically. Opt out with
  `gatus.home-operations.com/enabled: "false"`, or customize the check with a
  `gatus.home-operations.com/endpoint` annotation.
- YAML keys follow the repository
  [sorting rules](https://github.com/bykaj/home-ops/blob/main/.agents/instructions/sorting.instructions.md).

The [Adding an App](../../operations/runbooks/adding-an-app.md) runbook walks through
scaffolding one.

## Pod Security

Every namespace sets a
[Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
level with labels in its `namespace.yaml`. Talos's own admission defaults are
not in effect here, so a namespace without labels allows anything.

| Namespaces | Labels | Why |
| --- | --- | --- |
| actions-runner-system, ai, cert-manager, database, default, development, downloads, external-secrets, media, security, system-upgrade | `audit: baseline`, `warn: baseline` | App namespaces; nothing running in them needs more than baseline |
| kube-system, network, observability, rook-ceph, system | `enforce: privileged` | Run pods that need host access: control plane and Cilium, the Tailscale exit node, node-exporter and kguardian, Ceph OSDs and CSI, Spegel and the GPU driver |
| flux-system | `warn: restricted` | Set by flux-operator, which owns this namespace: it marks it `kustomize.toolkit.fluxcd.io/ssa: Ignore`, so labels in `flux-system/namespace.yaml` are never applied |

`baseline` forbids privileged containers, host namespaces, `hostPath`
volumes, host ports and added capabilities beyond a small safe set. Kopiur's
privileged movers stay within that set (`CHOWN`, `DAC_OVERRIDE`, `FOWNER`,
`FSETID`).

The app namespaces are in a warn-and-audit phase: violations are reported but
not blocked, and switch to `enforce: baseline` once none show up. Violations
fire the `PodSecurityBaselineViolation` alert (see
[Alerting](../../operations/alerting/index.md#custom-rules)). The metric behind
it has no namespace, so find the pod with:

```sh
just k8s pss-violations [files]   # reads the newest audit file(s) on each node
```

The audit logs keep about ten hours (ten hourly files per node). A pod created
by a controller shows as `(new)` with the creating controller as user; the
workload itself appears by name when Flux applies it. To check what is running
right now against a level, without changing anything:

```sh
kubectl label --dry-run=server --overwrite ns <namespace> pod-security.kubernetes.io/enforce=baseline
```

## Validating changes locally

```sh
kustomize build kubernetes/apps/<namespace>/<app>/app
yamllint --config-file .yamllint.yaml kubernetes/apps/<namespace>/<app>
```

`${APP}`-style variables staying literal in the output is expected. Flux
substitutes them at apply time. To render exactly what Flux would apply,
including components and substitutions:

```sh
just k8s apply-ks <namespace> <ks>   # render with flate and apply
```

Opening a pull request also triggers konflate, which posts the rendered Flux
diff as a PR comment and status check.

## Pages in this section

- [Talos](talos.md): machine config templates, schematics, rendering
- [Components](components.md): reusable kustomize components
- [Applications](applications.md): every app running in the cluster
- [App Notes](app-notes.md): per-app settings and gotchas the manifests don't show
