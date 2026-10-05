---
description: How apps are laid out under kubernetes/apps and the conventions they follow
---

# Kubernetes

The cluster runs [Talos Linux](talos.md) on three control plane nodes. Workloads
are scheduled on all three. Flux reconciles everything under
[`kubernetes/apps/`](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps).
See [GitOps](../architecture/gitops.md) for how that works.

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

Namespace kustomizations usually pull in two [components](components.md) for
every app in the namespace: `alerts` (Flux alerts to Alertmanager and GitHub
commit statuses) and `kopiur/secret` (the repository credentials Kopiur needs).

## The Flux Kustomization

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app memini
spec:
  components:
    - ../../../../components/kopiur/backup
  interval: 1h
  path: ./kubernetes/apps/ai/memini/app
  postBuild:
    substitute:
      APP: *app
      KOPIUR_MOVER_UID: "1000"
      KOPIUR_MOVER_GID: "1000"
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  targetNamespace: ai
```

!!! tip "What not to add"

    `wait`, `timeout`, `retryInterval`, `commonMetadata` and HelmRelease
    install/upgrade strategies are injected by `cluster-apps`. See
    [cluster-wide defaults](../architecture/gitops.md#cluster-wide-defaults).

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

The [Adding an App](../runbooks/adding-an-app.md) runbook walks through
scaffolding one.

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
