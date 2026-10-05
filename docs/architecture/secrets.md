---
description: How runtime secrets reach the cluster, the NAS and bootstrap tooling
---

# Secrets

Runtime secrets never live in Git. Everything resolves from 1Password (vault
`Homelab`), through three different paths.

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
    [Bootstrap](../runbooks/bootstrap.md).

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
