---
description: Every application running in the cluster, grouped by namespace
---

# Applications

Everything Flux deploys, grouped by namespace. Each name links to its
directory in the repository. An app is enabled when its `ks.yaml` is listed in
the namespace `kustomization.yaml`.

## Platform

### `kube-system`

| App | Purpose |
| --- | --- |
| [cilium](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/kube-system/cilium) | CNI, kube-proxy replacement, BGP LoadBalancer IPs |
| [coredns](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/kube-system/coredns) | Cluster DNS |
| [metrics-server](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/kube-system/metrics-server) | Resource metrics for `kubectl top` and HPAs |

### `flux-system`

| App | Purpose |
| --- | --- |
| [flux-instance](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/flux-system/flux-instance) | The Flux controllers, plus the GitHub webhook `Receiver` |
| [flux-operator](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/flux-system/flux-operator) | Manages the Flux installation |
| [konflate](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/flux-system/konflate) | Renders Flux changes in pull requests as status checks and comments |

### `network`

| App | Purpose |
| --- | --- |
| [certificates](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/network/certificates) | Wildcard certificates for the gateways |
| [cloudflare-tunnel](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/network/cloudflare-tunnel) | Cloudflare Tunnel to `envoy-external` |
| [echo-server](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/network/echo-server) | Request echo for testing routing |
| [envoy-gateway](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/network/envoy-gateway) | Gateway API: `envoy-internal` and `envoy-external` |
| [external-dns](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/network/external-dns) | UniFi (private) and Cloudflare (public) DNS records |
| [tailscale-operator](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/network/tailscale-operator) | Tailnet app connector and exit node |

### `cert-manager`, `external-secrets`, `security`

| App | Purpose |
| --- | --- |
| [authentik](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/security/authentik) | Identity provider and SSO (OIDC) |
| [cert-manager](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/cert-manager/cert-manager) | ACME certificates via Cloudflare DNS-01 |
| [external-secrets](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/external-secrets/external-secrets) | Syncs secrets from 1Password |
| [oidc-provider-debugger](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/security/oidc-provider-debugger) | Test client for OIDC flows |
| [onepassword-connect](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/external-secrets/onepassword-connect) | 1Password Connect server backing External Secrets |

### `rook-ceph`

| App | Purpose |
| --- | --- |
| [ceph-csi-drivers](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/rook-ceph/ceph-csi-drivers) | Ceph CSI drivers for RBD volumes |
| [rook-ceph](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/rook-ceph/rook-ceph) | Rook operator and the Ceph cluster |

### `system`

| App | Purpose |
| --- | --- |
| [crd-schema-publisher](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/system/crd-schema-publisher) | Publishes CRD JSON schemas to Cloudflare Pages (`schemas.bykaj.io`) for editor validation |
| [descheduler](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/system/descheduler) | Rebalances pods across nodes |
| [intel-gpu-resource-driver](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/system/intel-gpu-resource-driver) | DRA driver for the Intel iGPUs |
| [k8tz](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/system/k8tz) | Injects the `Europe/Amsterdam` timezone into pods |
| [kopiur](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/system/kopiur) | PVC backup and restore with the `nas` Kopia repository, replicated nightly to Backblaze B2 |
| [openebs](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/system/openebs) | `openebs-hostpath` local volumes |
| [reflector](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/system/reflector) | Mirrors Secrets and ConfigMaps across namespaces |
| [reloader](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/system/reloader) | Restarts workloads when their ConfigMaps or Secrets change |
| [snapshot-controller](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/system/snapshot-controller) | CSI VolumeSnapshot support |
| [spegel](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/system/spegel) | Peer-to-peer image mirror between nodes |

### `system-upgrade`, `actions-runner-system`

| App | Purpose |
| --- | --- |
| [actions-runner-controller](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/actions-runner-system/actions-runner-controller) | Self-hosted GitHub Actions runners |
| [tuppr](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/system-upgrade/tuppr) | Automated Talos and Kubernetes upgrades |

### `database`

| App | Purpose |
| --- | --- |
| [cloudnative-pg](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/database/cloudnative-pg) | PostgreSQL operator and Barman Cloud plugin |
| [dragonfly](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/database/dragonfly) | Dragonfly operator (Redis-compatible) |
| [emqx](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/database/emqx) | MQTT broker (operator and cluster) |
| [meilisearch](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/database/meilisearch) | Search engine |

### `observability`

| App | Purpose |
| --- | --- |
| [blackbox-exporter](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/observability/blackbox-exporter) | Probes, including the NFS probe used by `zeroscaler` |
| [drm-exporter](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/observability/drm-exporter) | Intel GPU metrics |
| [gatus](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/observability/gatus) | Status page and endpoint monitoring, auto-discovered from routes |
| [goldilocks](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/observability/goldilocks) | Resource request recommendations |
| [grafana-operator](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/observability/grafana-operator) | Grafana and dashboards as CRDs |
| [headlamp](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/observability/headlamp) | Kubernetes web UI |
| [kromgo](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/observability/kromgo) | Cluster stats for the README badges |
| [kube-prometheus-stack](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/observability/kube-prometheus-stack) | Prometheus, Alertmanager and alerting rules |
| [nut-exporter](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/observability/nut-exporter) | UPS metrics |
| [prometheus-adapter](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/observability/prometheus-adapter) | Exposes Prometheus metrics to HPAs |
| [silence-operator](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/observability/silence-operator) | Alertmanager silences as CRDs |
| [unpoller](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/observability/unpoller) | UniFi metrics |
| [victoria-logs](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/observability/victoria-logs) | Log storage and collection |

## Workloads

### `media`

| App | Purpose |
| --- | --- |
| [audiobookshelf](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/media/audiobookshelf) | Audiobooks and podcasts |
| [immich](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/media/immich) | Photo and video library |
| [jellyfin](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/media/jellyfin) | Media server |
| [plex](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/media/plex) | Media server, published externally |
| [stash](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/media/stash) | Media organizer |
| [tautulli](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/media/tautulli) | Plex statistics |

### `downloads`

| App | Purpose |
| --- | --- |
| [autobrr](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/downloads/autobrr) | Release automation |
| [bazarr](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/downloads/bazarr) | Subtitles |
| [configarr](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/downloads/configarr) | Syncs TRaSH quality profiles into the *arrs |
| [prowlarr](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/downloads/prowlarr) | Indexer management |
| [radarr](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/downloads/radarr) | Movie management |
| [sabnzbd](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/downloads/sabnzbd) | Usenet downloader |
| [sonarr](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/downloads/sonarr) | TV series management |
| [whisparr](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/downloads/whisparr) | Media management |

### `default`

| App | Purpose |
| --- | --- |
| [atuin](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/default/atuin) | Shell history sync |
| [changedetection](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/default/changedetection) | Website change monitoring |
| [homepage](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/default/homepage) | Dashboard |
| [it-tools](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/default/it-tools) | Developer utilities |
| [karakeep](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/default/karakeep) | Bookmarks and read-later |
| [mail-archiver](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/default/mail-archiver) | Email archiving |
| [paperless](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/default/paperless) | Document management |
| [pgadmin](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/default/pgadmin) | PostgreSQL administration |
| [spoolman](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/default/spoolman) | 3D printer filament inventory |
| [thelounge](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/default/thelounge) | IRC client |
| [wallos](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/default/wallos) | Subscription tracking |
| [wastebin](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/default/wastebin) | Pastebin |
| [windshift](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/default/windshift) | Work and project management |

## Disabled

Manifests kept in the repository but commented out of their namespace
`kustomization.yaml`:

| Namespace | Apps |
| --- | --- |
| `ai` | litellm, llmkube, memini, open-webui |
| `default` | filabridge, n8n, opencloud |
| `development` | coder |
| `media` | komga |
