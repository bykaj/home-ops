---
description: How runtime secrets reach the cluster, the NAS, bootstrap tooling and GitHub Actions
---

# Secrets

Runtime secrets never live in Git. Everything resolves from 1Password: the
cluster, the NAS and bootstrap tooling read vault `Homelab` through three
different paths, and GitHub Actions workflows read vault `Automation`.

## Kubernetes: External Secrets

[External Secrets Operator](https://external-secrets.io) reads from
[1Password Connect](https://github.com/1Password/connect) through the
`onepassword` `ClusterSecretStore`. Apps declare an `ExternalSecret`
that maps 1Password fields to keys in a Kubernetes `Secret`:

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: myapp
spec:
  refreshInterval: 5m
  secretStoreRef:
    kind: ClusterSecretStore
    name: onepassword
  target:
    name: myapp-secret
    creationPolicy: Owner
    template:
      engineVersion: v2
      data:
        API_KEY: "{{ .API_KEY }}"
  dataFrom:
    - extract:
        key: myapp
```

Random values that don't need to live in 1Password (tokens, passwords) come
from a `ClusterGenerator` instead, with `refreshPolicy: CreatedOnce`.

Force a refresh with `just k8s sync-es <namespace> <name>`, or all at once with
`just k8s sync es`.

!!! note "Chicken and egg"

    1Password Connect needs its own credentials before External Secrets can
    work. The bootstrap stage renders those Secrets (plus the Cloudflare tunnel
    ID) through `op inject` and applies them before the controllers start. See
    [Bootstrap](../../operations/runbooks/bootstrap.md).

## NAS: doco-cd

Compose-level secrets are declared in
[`docker/nas/.doco-cd.yaml`](https://github.com/bykaj/home-ops/blob/main/docker/nas/.doco-cd.yaml)
under `external_secrets` as `op://Homelab/<item>/<field>` references. doco-cd
resolves them at deploy time and exposes them as variables, which the compose
files consume as `${VAR_NAME}`.

```yaml
external_secrets:
  GARAGE_ADMIN_TOKEN: op://Homelab/garage/ADMIN_TOKEN
```

## Workstation: `op inject`

Talos machine configs and bootstrap manifests contain `op://` references that
are resolved locally with the 1Password CLI:

```sh
minijinja-cli <template> | op inject
```

That is the `template` recipe in the root `.justfile`, used by
`just talos render-config` and `just bootstrap`. A signed-in `op` session is a
prerequisite for both.

## GitHub Actions: `Automation` vault

Workflows load their credentials with
[`1password/load-secrets-action`](https://github.com/1password/load-secrets-action)
and a service account whose token is the repository secret
`OP_SERVICE_ACCOUNT_TOKEN`. That service account can only read the
`Automation` vault, never `Homelab`:

```yaml
- name: Load Secrets
  uses: 1password/load-secrets-action@<sha> # v5.0.1
  id: load-secrets
  env:
    OP_SERVICE_ACCOUNT_TOKEN: ${{ secrets.OP_SERVICE_ACCOUNT_TOKEN }}
    GITHUB_BOT_APP_CLIENT_ID: op://Automation/github-bot/GITHUB_BOT_APP_CLIENT_ID
```

| Item | Used for |
|---|---|
| `github-bot` | GitHub App token for Renovate, labeler, tag and the review bot |
| `docker-hub` | Authenticated Docker Hub lookups in Renovate |
| `claude-review` | Review bot OAuth token |

The same service account is used by the public
[bykaj/containers](https://github.com/bykaj/containers) repository, which
also reads a `pushover` item for build-failure notifications. Anything in
`Automation` is therefore readable by workflows of a public repository: keep
it to credentials meant for CI, and keep one copy of each item, so a key
rotation can't leave a stale copy behind.
