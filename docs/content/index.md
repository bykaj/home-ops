---
icon: material/home
---

# Home Operations

!!! tip "Home-Ops: Where Hobby Meets High-Tech Infrastructure"

Documentation for my home infrastructure: a three-node bare-metal Kubernetes
cluster running [Talos Linux](https://www.talos.dev/), and a
[TrueNAS](https://www.truenas.com/) server that provides bulk storage, backups
and a handful of supporting services. Everything is declared in a single Git
repository, [bykaj/home-ops](https://github.com/bykaj/home-ops). That includes
the Kubernetes manifests, the Talos machine configs, the Docker Compose stacks,
the bootstrap tooling and these docs.

Merging to `main` is the deploy step:
[Flux](https://fluxcd.io/) reconciles the cluster and
[doco-cd](https://github.com/kimdre/doco-cd) redeploys the NAS stacks, both
immediately through webhooks, and [Renovate](https://github.com/renovatebot/renovate) opens
pull requests for every dependency in the repository.

## At a glance

| Area | Choice |
| --- | --- |
| OS | [Talos Linux](platforms/kubernetes/talos.md) on three control-plane nodes; upgrades by [tuppr](operations/runbooks/upgrades.md) |
| GitOps | [Flux](infrastructure/architecture/gitops.md) for the cluster, [doco-cd](platforms/docker/index.md) for the NAS, Renovate for updates |
| CNI | [Cilium](infrastructure/networking/index.md#cilium): native routing, no kube-proxy, LoadBalancer IPs over [BGP](infrastructure/networking/bgp.md) |
| Ingress | [Envoy Gateway](infrastructure/networking/index.md#gateways) (Gateway API), Cloudflare Tunnel for public apps |
| DNS | [Split-horizon](infrastructure/networking/dns.md): external-dns to UniFi on the LAN and to Cloudflare publicly |
| Certificates | cert-manager with Let's Encrypt wildcard certificates |
| Identity | Pocket ID (OIDC) |
| Secrets | [External Secrets with 1Password Connect](infrastructure/architecture/secrets.md) in the cluster, doco-cd `op://` references on the NAS |
| Storage | [Rook-Ceph](infrastructure/storage/index.md#rook-ceph) block storage, [OpenEBS](infrastructure/storage/index.md#openebs) local volumes, NFS from the [NAS](infrastructure/storage/index.md#nas) |
| Backups | [Kopiur](infrastructure/storage/backups.md) (Kopia) for PVCs, off-site to Backblaze B2 |
| Databases | [CloudNativePG](infrastructure/storage/postgres.md) with Barman Cloud backups to Garage S3; Dragonfly caches |
| Images | Spegel node-to-node sharing, Zot pull-through mirror on the NAS |
| Monitoring | [kube-prometheus-stack](operations/alerting/index.md) with Pushover alerts, VictoriaLogs, Grafana, Gatus |

## Where to start

<div class="grid cards" markdown>

- :material-sitemap: **[Architecture](infrastructure/architecture/index.md)**

    ***

    How the pieces fit together: GitOps flow, repository layout, secrets.

- :material-server: **[Hardware](infrastructure/hardware/index.md)**

    ***

    Cluster nodes, NAS, network gear and power.

- :material-lan: **[Networking](infrastructure/networking/index.md)**

    ***

    Subnets, BGP-announced VIPs, gateways and split-horizon DNS.

- :material-database: **[Storage](infrastructure/storage/index.md)**

    ***

    Rook-Ceph, OpenEBS, the NAS pools, PVC backups and PostgreSQL.

- :material-kubernetes: **[Kubernetes](platforms/kubernetes/index.md)**

    ***

    Talos, app layout conventions, reusable components and the app catalog.

- :material-docker: **[Docker](platforms/docker/index.md)**

    ***

    Compose stacks on the NAS, deployed by doco-cd.

- :material-book-open-variant: **[Runbooks](operations/runbooks/index.md)**

    ***

    Bootstrap, upgrades, new databases, adding apps.

- :material-stethoscope: **[Troubleshooting](operations/troubleshooting/index.md)**

    ***

    Symptom ladder, known noise and the knowledge base of past problems.

- :material-history: **[History](operations/history/index.md)**

    ***

    Incidents and major migrations, and what changed because of them.

- :material-format-list-bulleted: **[Reference](reference/index.md)**

    ***

    `just` recipes, tooling, cloud dependencies, glossary.

</div>
