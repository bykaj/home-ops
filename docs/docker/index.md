---
description: Docker Compose stacks on the NAS, deployed by doco-cd
---

# Docker

Some services run outside Kubernetes, as Docker Compose stacks on the TrueNAS
host. Some must keep working when the cluster is down or being rebuilt (the
registry mirror, S3 for database recovery, PXE boot). Others are simply
NAS-local (BGP, hardware exporters).

## How stacks are deployed

[doco-cd](https://github.com/kimdre/doco-cd) runs on the NAS (its own compose
file lives in `docker/nas/.doco-cd/`) and is configured by
[`docker/nas/.doco-cd.yaml`](https://github.com/bykaj/home-ops/blob/main/docker/nas/.doco-cd.yaml):

- deploys on every push to `main` through a GitHub webhook (see
  [Webhook](#webhook)), and polls `bykaj/home-ops` `main` every hour as a
  fallback
- auto-discovers stacks one directory deep under `docker/nas/`
- deletes stacks whose directory disappears
- resolves `op://` secrets from 1Password and passes them to compose as
  `${VAR}` (see [Secrets](../architecture/secrets.md#nas-doco-cd))

Each stack is `docker/nas/NN-<app>/docker-compose.yaml`. The `NN-` prefix only
sets the order.

!!! danger "Don't rename stack directories"

    Renaming or renumbering a stack directory makes doco-cd delete the old
    stack and create a new one, including its anonymous volumes. Keep
    directory names stable.

To redeploy without a push, for example after a failed deploy:

```sh
just docker sync-stacks     # poll main now through doco-cd's REST API
```

The recipe calls `POST /v1/api/poll/run` on `nas.internal:8880` with the API
secret from 1Password (`op://Homelab/doco-cd/API_SECRET`). It waits for the run
and fails if the run doesn't succeed. Only changed stacks are redeployed.

doco-cd can't manage its own stack. After changing
`docker/nas/.doco-cd/docker-compose.app.yaml`, run `just bootstrap nas`: it
copies the file and its secrets to the NAS and runs `docker compose up`.
`just docker restart-doco-cd` only restarts the running container (via Ansible)
and doesn't pick up compose changes. Changes to `docker/nas/.doco-cd.yaml`
need neither: doco-cd reads it from the repo on every run.

### Webhook

GitHub sends push events for `bykaj/home-ops` to
`https://doco-cd-webhook.bykaj.io/v1/webhook`. The NAS is LAN-only, so the
request goes through the cluster: Cloudflare Tunnel → `envoy-external` → an
Envoy Gateway `Backend` in the `network` namespace that points at doco-cd on
the NAS (`nas.internal:8880`). The `HTTPRoute` only matches `/v1/webhook` and
`/v1/health` (exact paths), so doco-cd's REST API stays off the internet. See
[`kubernetes/apps/network/doco-cd-webhook/`](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/network/doco-cd-webhook).

doco-cd checks each request's HMAC-SHA256 signature against
`WEBHOOK_SECRET_FILE` (`~/.config/doco-cd/webhook_secret` on the NAS). The
GitHub webhook must use the same secret, with content type
`application/json` and only the push event.

GitHub sends push events for every branch, not just `main`. `.doco-cd.yaml`
sets `webhook_filter: ^refs/heads/main$` so doco-cd skips the others, and
`reference: refs/heads/main` so deploys always run from `main`. Without them,
pushing a PR branch (Renovate's included) would deploy it to the NAS before
it is merged.

Gatus checks `https://doco-cd-webhook.bykaj.io/v1/health` from the cluster,
through the same public path GitHub uses. It doesn't probe `/v1/webhook`,
because every request there (even a `GET`) shows up as a failed job in
doco-cd's run history. `/v1/health` only returns `{"content":"healthy"}`.

## Ingress and DNS

[Traefik](https://traefik.io) (`02-traefik`) is the reverse proxy for every
stack on the shared `apps` network. It terminates TLS for `*.bykaj.app` and
`*.bykaj.io` with Let's Encrypt certificates (Cloudflare DNS-01) and also
forwards TFTP (UDP 69), HTTP on 8080 and SMB (445).

A stack opts in with labels:

```yaml
labels:
  dexd.enabled: "true"       # create a DNS record in UniFi
  traefik.enable: "true"
  traefik.http.routers.myapp.rule: Host(`myapp.bykaj.app`)
  traefik.http.services.myapp.loadbalancer.server.port: "8080"
```

[dexd](https://github.com/ishioni/dexd) (`01-dexd`) watches Docker labels and
writes a CNAME to the UDM for each `Host()` rule, pointing at `docker.bykaj.app`
(a static A record for `10.73.2.100`). NAS services are LAN-only. See
[DNS → NAS records](../networking/dns.md#nas-records-dexd).

## Stacks

### `00-frr`

[FRR](https://frrouting.org) in host network mode. It peers with the UDM as
ASN 64515 and announces the NAS address `10.73.1.10/32`. See
[BGP & Load Balancing](../networking/bgp.md).

### `01-dexd`

DNS records in UniFi for labelled containers.

### `02-traefik`

Reverse proxy and TLS termination for the stacks below.

### `03-exporters`

`node-exporter` and `smartctl-exporter` for NAS host and disk metrics, scraped
by the cluster's Prometheus.

### `04-bootimus`

[Bootimus](https://github.com/garybowers/bootimus) PXE/netboot server (TFTP +
HTTP), with its admin UI at `bootimus.bykaj.app`. It is used to boot Talos
installers on bare metal.

### `05-garage`

[Garage](https://garagehq.deuxfleurs.fr) S3-compatible object storage at
`s3.bykaj.io`, with [garage-ui](https://github.com/noooste/garage-ui) for
management (OIDC login). CNPG stores WAL archives and base backups here.

### `06-zot`

[Zot](https://zotregistry.dev) OCI registry at `registry.bykaj.app`, acting as
an on-demand pull-through cache for Docker Hub (`/docker-hub`), GHCR (`/ghcr`),
Quay (`/quay`) and `registry.k8s.io` (`/k8s`). Talos nodes use it as their
registry mirror, falling back to upstream when it is unavailable.

!!! note

    `config.json` is a single-file bind mount. After doco-cd redeploys a config
    change, restart the container (`sudo docker restart zot`) for it to take
    effect.

## Adding a stack

Follow the
[`add-docker-app`](https://github.com/bykaj/home-ops/blob/main/.agents/skills/add-docker-app/SKILL.md)
skill for proxy, network and secret conventions. Validate locally with:

```sh
docker compose -f docker/nas/NN-<app>/docker-compose.yaml config --quiet
```

Warnings about unset `${VAR}`s are expected; doco-cd provides those at deploy
time.
