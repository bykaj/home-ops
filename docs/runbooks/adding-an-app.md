---
description: Scaffold and ship a new app-template application to the cluster
---

# Adding an App

The canonical, step-by-step version lives in the
[`add-app`](https://github.com/bykaj/home-ops/blob/main/.agents/skills/add-app/SKILL.md)
skill, which coding agents also follow. This page is the short version.

## Good reference apps

| App | Shows |
| --- | --- |
| [`network/echo-server`](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/network/echo-server) | Minimal stateless app with a route |
| [`security/authentik`](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/security/authentik) | Secrets, and a config file via `configMapGenerator` |
| [`default/paperless`](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/default/paperless) | Custom probes, Dragonfly dependency, Kopiur-backed persistence |

## Steps

1. **Decide the basics**: namespace, image and tag, port, internal
   (`envoy-internal`) or public (`envoy-external`), whether it has state,
   which secrets it needs, and what it depends on.
2. **Create the directory** `kubernetes/apps/<namespace>/<app>/` with
   `ks.yaml` and `app/{kustomization,ocirepository,helmrelease}.yaml`. Copy
   the closest reference app rather than starting from nothing.
3. **State?** Add the [`kopiur/backup`](../kubernetes/components.md#kopiurbackup)
   component and mount the `${APP}` PVC. Set `KOPIUR_MOVER_UID`/`GID` to the
   app's UID/GID if it isn't `4000`.
4. **Database?** Add the [`postgres`](../storage/postgres.md) component and
   follow [New Database](new-database.md).
5. **Secrets?** Add an `externalsecret.yaml` that reads from the
   `onepassword` `ClusterSecretStore`. Use the exact 1Password item and field
   names.
6. **Enable it** by adding `./<app>/ks.yaml` to the namespace
   `kustomization.yaml`.
7. **Validate**:

    ```sh
    kustomize build kubernetes/apps/<namespace>/<app>/app
    yamllint --config-file .yamllint.yaml kubernetes/apps/<namespace>/<app>
    ```

8. **Document it**: run `just docs-apps`, then replace the `TODO` purpose of
    the new row on [Applications](../kubernetes/applications.md) and fill in
    its Upstream link. A new namespace must first be added to `PLATFORM` or
    `WORKLOADS` in `scripts/docs-applications.py`.
9. **Open a PR**. konflate posts the rendered diff. Merging deploys the app.

## Common mistakes

- Adding `timeout` or `commonMetadata` to `ks.yaml`. `cluster-apps` injects
  `timeout`, and the chart already sets the labels `commonMetadata` would add.
- Adding `wait: true` by reflex. Leave it unset, unless another Kustomization
  depends on this app and it has no health checks. Then `wait: true` is what
  gives the dependent a readiness gate.
- `readOnlyRootFilesystem: true` without a writable `tmpfs` for `/tmp`.
- Forgetting the `kopiur/secret` component at the namespace level when the
  app's namespace has no other backed-up apps.
