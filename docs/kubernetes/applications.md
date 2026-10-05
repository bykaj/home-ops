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
| [flux-operator](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/flux-system/flux-operator) | Manages the Flux installation |
| [flux-instance](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/flux-system/flux-instance) | The Flux controllers, plus the GitHub webhook `Receiver` |
| [konflate](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/flux-system/konflate) | Renders Flux changes in pull requests as status checks and comments |

### `network`

| App | Purpose |
| --- | --- |
| [envoy-gateway](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/network/envoy-gateway) | Gateway API: `envoy-internal` and `envoy-external` |
| [certificates](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/network/certificates) | Wildcard certificates for the gateways |
| [external-dns](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/network/external-dns) | UniFi (private) and Cloudflare (public) DNS records |
| [cloudflare-tunnel](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/network/cloudflare-tunnel) | Cloudflare Tunnel to `envoy-external` |
| [tailscale-operator](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/network/tailscale-operator) | Tailnet app connector and exit node |
| [echo-server](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/network/echo-server) | Request echo for testing routing |

### `cert-manager`, `external-secrets`, `security`

| App | Purpose |
| --- | --- |
| [cert-manager](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/cert-manager/cert-manager) | ACME certificates via Cloudflare DNS-01 |
| [external-secrets](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/external-secrets/external-secrets) | Syncs secrets from 1Password |
| [onepassword-connect](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/external-secrets/onepassword-connect) | 1Password Connect server backing External Secrets |
| [authentik](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/security/authentik) | Identity provider and SSO (OIDC) |
| [oidc-provider-debugger](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/security/oidc-provider-debugger) | Test client for OIDC flows |

### `rook-ceph`

| App | Purpose |
| --- | --- |
| [rook-ceph](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/rook-ceph/rook-ceph) | Rook operator and the Ceph cluster |
| [ceph-csi-drivers](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/rook-ceph/ceph-csi-drivers) | Ceph CSI drivers for RBD volumes |

### `system`

| App | Purpose |
| --- | --- |
| [kopiur](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/system/kopiur) | PVC backup and restore with the `nas` Kopia repository, replicated nightly to Backblaze B2 |
| [openebs](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/system/openebs) | `openebs-hostpath` local volumes |
| [snapshot-controller](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/system/snapshot-controller) | CSI VolumeSnapshot support |
| [spegel](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/system/spegel) | Peer-to-peer image mirror between nodes |
| [intel-gpu-resource-driver](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/system/intel-gpu-resource-driver) | DRA driver for the Intel iGPUs |
| [descheduler](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/system/descheduler) | Rebalances pods across nodes |
| [reloader](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/system/reloader) | Restarts workloads when their ConfigMaps or Secrets change |
| [reflector](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/system/reflector) | Mirrors Secrets and ConfigMaps across namespaces |
| [k8tz](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/system/k8tz) | Injects the `Europe/Amsterdam` timezone into pods |
| [crd-schema-publisher](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/system/crd-schema-publisher) | Publishes CRD JSON schemas to Cloudflare Pages (`schemas.bykaj.io`) for editor validation |

### `system-upgrade`, `actions-runner-system`

| App | Purpose |
| --- | --- |
| [tuppr](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/system-upgrade/tuppr) | Automated Talos and Kubernetes upgrades |
| [actions-runner-controller](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/actions-runner-system/actions-runner-controller) | Self-hosted GitHub Actions runners |

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
| [kube-prometheus-stack](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/observability/kube-prometheus-stack) | Prometheus, Alertmanager and alerting rules |
| [grafana-operator](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/observability/grafana-operator) | Grafana and dashboards as CRDs |
| [victoria-logs](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/observability/victoria-logs) | Log storage and collection |
| [gatus](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/observability/gatus) | Status page and endpoint monitoring, auto-discovered from routes |
| [blackbox-exporter](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/observability/blackbox-exporter) | Probes, including the NFS probe used by `zeroscaler` |
| [prometheus-adapter](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/observability/prometheus-adapter) | Exposes Prometheus metrics to HPAs |
| [silence-operator](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/observability/silence-operator) | Alertmanager silences as CRDs |
| [kromgo](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/observability/kromgo) | Cluster stats for the README badges |
| [headlamp](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/observability/headlamp) | Kubernetes web UI |
| [goldilocks](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/observability/goldilocks) | Resource request recommendations |
| [unpoller](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/observability/unpoller) | UniFi metrics |
| [nut-exporter](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/observability/nut-exporter) | UPS metrics |
| [drm-exporter](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/observability/drm-exporter) | Intel GPU metrics |

## Workloads

### `media`

| App | Purpose |
| --- | --- |
| [plex](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/media/plex) | Media server, published externally |
| [jellyfin](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/media/jellyfin) | Media server |
| [tautulli](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/media/tautulli) | Plex statistics |
| [immich](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/media/immich) | Photo and video library |
| [audiobookshelf](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/media/audiobookshelf) | Audiobooks and podcasts |
| [stash](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/media/stash) | Media organizer |

### `downloads`

| App | Purpose |
| --- | --- |
| [sonarr](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/downloads/sonarr) | TV series management |
| [radarr](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/downloads/radarr) | Movie management |
| [whisparr](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/downloads/whisparr) | Media management |
| [bazarr](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/downloads/bazarr) | Subtitles |
| [prowlarr](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/downloads/prowlarr) | Indexer management |
| [autobrr](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/downloads/autobrr) | Release automation |
| [sabnzbd](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/downloads/sabnzbd) | Usenet downloader |
| [configarr](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/downloads/configarr) | Syncs TRaSH quality profiles into the *arrs |

### `default`

| App | Purpose |
| --- | --- |
| [homepage](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/default/homepage) | Dashboard |
| [paperless](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/default/paperless) | Document management |
| [karakeep](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/default/karakeep) | Bookmarks and read-later |
| [atuin](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/default/atuin) | Shell history sync |
| [changedetection](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/default/changedetection) | Website change monitoring |
| [mail-archiver](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/default/mail-archiver) | Email archiving |
| [wallos](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/default/wallos) | Subscription tracking |
| [wastebin](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/default/wastebin) | Pastebin |
| [it-tools](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/default/it-tools) | Developer utilities |
| [thelounge](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/default/thelounge) | IRC client |
| [spoolman](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/default/spoolman) | 3D printer filament inventory |
| [windshift](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/default/windshift) | Work and project management |
| [pgadmin](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/default/pgadmin) | PostgreSQL administration |

## Disabled

Manifests kept in the repository but commented out of their namespace
`kustomization.yaml`:

| Namespace | Apps |
| --- | --- |
| `ai` | litellm, llmkube, memini, open-webui |
| `default` | filabridge, n8n, opencloud |
| `development` | coder |
| `media` | komga |
