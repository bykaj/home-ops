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
just docker reconcile-nas   # restarts doco-cd on the NAS via Ansible
```

### Webhook

GitHub sends push events for `bykaj/home-ops` to
`https://doco-cd-webhook.bykaj.io/v1/webhook`. The NAS is LAN-only, so the
request goes through the cluster: Cloudflare Tunnel → `envoy-external` → an
Envoy Gateway `Backend` in the `network` namespace that points at doco-cd on
the NAS (`nas.internal:8880`). The `HTTPRoute` only matches `/v1/webhook`, so doco-cd's
REST API stays off the internet. See
[`kubernetes/apps/network/doco-cd-webhook/`](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/network/doco-cd-webhook).

doco-cd checks each request's HMAC-SHA256 signature against
`WEBHOOK_SECRET_FILE` (`~/.config/doco-cd/webhook_secret` on the NAS). The
GitHub webhook must use the same secret, with content type
`application/json` and only the push event.

Gatus checks the route with a `GET`, which doco-cd answers with
`405 Method Not Allowed`. That status means the whole path from Cloudflare to
the NAS is up.

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
