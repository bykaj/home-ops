<div align="center">

<img src="https://github.com/bykaj/home-ops/blob/main/assets/images/home-ops-logo.png?raw=true" align="center" width="144px" height="144px"/>

## HOME OPERATIONS REPOSITORY

_Managed with Flux, Renovate, and GitHub Actions_

[![Talos](https://img.shields.io/endpoint?url=https%3A%2F%2Fstats.bykaj.io%2Fbadges%2Ftalos_version%3Fformat%3Dshields&style=for-the-badge&logo=talos&logoColor=white&color=blue&label=talos)](https://talos.dev)&nbsp;
[![Kubernetes](https://img.shields.io/endpoint?url=https%3A%2F%2Fstats.bykaj.io%2Fbadges%2Fkubernetes_version%3Fformat%3Dshields&style=for-the-badge&logo=kubernetes&logoColor=white&color=blue&label=k8s)](https://kubernetes.io)&nbsp;
[![Flux](https://img.shields.io/endpoint?url=https%3A%2F%2Fstats.bykaj.io%2Fbadges%2Fflux_version%3Fformat%3Dshields&style=for-the-badge&logo=flux&logoColor=white&color=blue&label=flux)](https://fluxcd.io)&nbsp;
[![Renovate](https://img.shields.io/github/actions/workflow/status/bykaj/home-ops/renovate.yaml?branch=main&label=renovate&logo=renovate&logoColor=white&style=for-the-badge&color=blue)](https://github.com/bykaj/home-ops/actions/workflows/renovate.yaml)

[![Age-Days](https://img.shields.io/endpoint?url=https%3A%2F%2Fstats.bykaj.io%2Fbadges%2Fcluster_birth_age%3Fformat%3Dshields&style=for-the-badge&label=Age)](https://github.com/home-operations/kromgo)&nbsp;
[![Uptime-Days](https://img.shields.io/endpoint?url=https%3A%2F%2Fstats.bykaj.io%2Fbadges%2Fcluster_uptime_age%3Fformat%3Dshields&style=for-the-badge&label=Uptime)](https://github.com/home-operations/kromgo)&nbsp;
[![Node-Count](https://img.shields.io/endpoint?url=https%3A%2F%2Fstats.bykaj.io%2Fbadges%2Fcluster_node_count%3Fformat%3Dshields&style=for-the-badge&label=Nodes)](https://github.com/home-operations/kromgo)&nbsp;
[![Pod-Count](https://img.shields.io/endpoint?url=https%3A%2F%2Fstats.bykaj.io%2Fbadges%2Fcluster_pod_count%3Fformat%3Dshields&style=for-the-badge&label=Pods)](https://github.com/home-operations/kromgo)&nbsp;
[![CPU-Usage](https://img.shields.io/endpoint?url=https%3A%2F%2Fstats.bykaj.io%2Fbadges%2Fcluster_cpu_usage%3Fformat%3Dshields&style=for-the-badge&label=CPU)](https://github.com/home-operations/kromgo)&nbsp;
[![Memory-Usage](https://img.shields.io/endpoint?url=https%3A%2F%2Fstats.bykaj.io%2Fbadges%2Fcluster_memory_usage%3Fformat%3Dshields&style=for-the-badge&label=MEM)](https://github.com/home-operations/kromgo)&nbsp;
[![Power](https://img.shields.io/endpoint?url=https%3A%2F%2Fstats.bykaj.io%2Fbadges%2Fcluster_power_usage%3Fformat%3Dshields&style=for-the-badge&label=PWR)](https://github.com/home-operations/kromgo)

📖 **Documentation:** [docs.bykaj.com](https://docs.bykaj.com)

</div>

---

<details>
<summary><strong>Table of Contents</strong> (click to expand)</summary>

1. [Overview](#-overview)
2. [Kubernetes](#-kubernetes)
   - [Core Components](#core-components)
3. [Cloud Dependencies](#-cloud-dependencies)
4. [DNS](#-dns)
5. [Hardware](#-hardware)
   - [Compute](#compute)
   - [Storage](#storage)
   - [Networking](#networking)
   - [Power](#power)
   - [Eye candy](#eye-candy)
6. [Gratitude and Thanks](#-gratitude-and-thanks)
7. [License](#-license)

</details>

---

## <img src="https://fonts.gstatic.com/s/e/notoemoji/latest/1f4a1/512.gif" alt="💡" width="20" height="20"> Overview

This is a mono repository for my wildly over-engineered home infrastructure and Kubernetes cluster, because apparently I hate free time. I try to follow Infrastructure as Code (IaC) and GitOps practices using enterprise-grade tools like [Ansible](https://www.ansible.com/), [Kubernetes](https://kubernetes.io/), [Flux](https://github.com/fluxcd/flux2), [Renovate](https://github.com/renovatebot/renovate) and [GitHub Actions](https://github.com/features/actions)—you know, the same stack Netflix uses, except mine just runs my Plex server and some smart lightbulbs. Ok, I also use some trusty [bash](<https://en.wikipedia.org/wiki/Bash_(Unix_shell)>) scripts held together by duct tape and prayer.

---

## <img src="https://fonts.gstatic.com/s/e/notoemoji/latest/1f331/512.gif" alt="🌱" width="20" height="20"> Kubernetes

My Kubernetes cluster is deployed with [Talos](https://www.talos.dev). This is a semi-hyper-converged cluster, workloads and block storage are sharing the same available resources on my nodes while I have a separate [TrueNAS](https://www.truenas.com) server with multiple ZFS pools for NFS/SMB shares, bulk file storage and backups.

How it all fits together, from the [GitOps flow](https://docs.bykaj.com/architecture/gitops/) to [bootstrapping the cluster](https://docs.bykaj.com/runbooks/bootstrap/), is covered in the [documentation](https://docs.bykaj.com).

### Core Components

- [actions-runner-controller](https://github.com/actions/actions-runner-controller) – Self-hosted GitHub runners.
- [cert-manager](https://github.com/cert-manager/cert-manager) – Creates SSL certificates for services in my cluster.
- [cilium](https://github.com/cilium/cilium) – eBPF-based networking for my workloads.
- [cloudflared](https://github.com/cloudflare/cloudflared) – Enables Cloudflare secure access to my routes.
- [external-dns](https://github.com/kubernetes-sigs/external-dns) – Automatically syncs Gateway API route DNS records to UniFi and Cloudflare (see [DNS](#-dns) below).
- [external-secrets](https://github.com/external-secrets/external-secrets) – Kubernetes secrets injection using [1Password Connect](https://github.com/1Password/connect).
- [flux](https://github.com/fluxcd/flux2) – Syncs Kubernetes configuration in Git to the cluster.
- [kopiur](https://github.com/home-operations/kopiur) – Backup and recovery of persistent volume claims.
- [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) – Kubernetes cluster monitoring and alerting.
- [openebs](https://github.com/openebs/openebs) – Local container-attached storage for caching.
- [rook](https://github.com/rook/rook) – Distributed block storage with Ceph for persistent storage.
- [spegel](https://github.com/spegel-org/spegel) – Stateless local OCI registry mirror.

Everything else that runs in the cluster is listed in the [application catalog](https://docs.bykaj.com/kubernetes/applications/).

---

## <img src="https://fonts.gstatic.com/s/e/notoemoji/latest/1f636_200d_1f32b_fe0f/512.gif" alt="😶" width="20" height="20"> Cloud Dependencies

While most of my infrastructure and workloads are self-hosted, I do rely on the cloud for certain key parts:

- [1Password](https://1password.com/) – Password management and Kubernetes secrets injection with [External Secrets](https://external-secrets.io/).
- [Cloudflare](https://www.cloudflare.com/) – Public DNS, Zero Trust tunnel and hosting Kubernetes schemas.
- [Fastmail](https://fastmail.com/) – Email hosting.
- [GitHub](https://github.com/) – Hosting this repository and continuous integration/deployments.
- [Pushover](https://pushover.net/) – Kubernetes alerts and application notifications.
- [Backblaze B2](https://backblaze.com/) – S3 object storage for applications and backups.

This helps me avoid three major headaches:

1. **Chicken-and-egg scenarios** – Dependencies that prevent initial system bootstrapping.
2. **Critical service availability** – Services I need whether my cluster is up or not.
3. **The "hit by a bus" factor** – Making sure critical apps like email, password management, and photo storage stay accessible to my family and friends when I'm no longer around.

I could tackle the first two problems by spinning up another Kubernetes cluster in the cloud and deploying alternative apps like [HashiCorp Vault](https://www.vaultproject.io/), [Vaultwarden](https://github.com/dani-garcia/vaultwarden), [ntfy](https://ntfy.sh/), and [Gatus](https://gatus.io/). But honestly, maintaining another cluster and babysitting more workloads would be way more work and expense. Something about free time.

The [documentation](https://docs.bykaj.com/reference/cloud-dependencies/) lists what each service is used for in more detail.

---

## <img src="https://fonts.gstatic.com/s/e/notoemoji/latest/1f30e/512.gif" alt="🌎" width="20" height="20"> DNS

My cluster runs split-horizon DNS: the same hostname resolves differently on my LAN than on the internet. Two [ExternalDNS](https://github.com/kubernetes-sigs/external-dns) instances watch my [Gateway API](https://gateway-api.sigs.k8s.io/) routes and write records for six zones, each to its own provider.

- **Private (UniFi)** – The first instance syncs records to my UniFi UDM via the [ExternalDNS Webhook Provider for UniFi](https://github.com/home-operations/external-dns-unifi-webhook). It watches routes on _both_ Envoy gateways plus annotated LoadBalancer Services, so every app on my LAN is a CNAME to `internal.bykaj.app` or `external.bykaj.app`, which in turn are A records for the gateway VIPs. Even publicly exposed apps resolve to the local gateway at home instead of taking a detour through Cloudflare.
- **Public (Cloudflare)** – The second instance only watches routes attached to the `envoy-external` gateway and syncs them to Cloudflare as proxied CNAMEs to `external.bykaj.app`, which a `DNSEndpoint` points at my [Cloudflare Tunnel](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/). Internal-only apps simply never show up in public DNS.

The Docker apps on my NAS get their (LAN-only) records from [dexd](https://github.com/ishioni/dexd), which reads container labels and points each hostname at the Traefik reverse proxy. Each controller marks its records with its own TXT ownership prefix (`k8s.` and `dkr.`), so they never step on each other's toes. Only a handful of bootstrap records, like the Kubernetes API endpoint, are maintained by hand. The full details are in the [DNS docs](https://docs.bykaj.com/networking/dns/).

---

## <img src="https://fonts.gstatic.com/s/e/notoemoji/latest/2699_fe0f/512.gif" alt="⚙" width="20" height="20"> Hardware

### Compute

**Cluster** · Talos/Kubernetes

- **Systems** — 2 × Lenovo M920x (i9-9900T), 1 × Lenovo M90q Gen 5 (i5-13400T), 64GB RAM
- **OS & Local Storage** — Kingston NV3, 1TB (NVMe)
- **Rook-Ceph** — Micron 7300 PRO, 480GB (NVMe)
- **Network** — Intel X520-DA2, 10G
- **Out-of-band** — JetKVM + DC Power Control Extension

### Storage

**NAS** · TrueNAS SCALE

- **System** — Self-built 3U (i7-6700K), 64GB RAM
- **OS** — WD Red SA500, 500GB (SSD)
- **Bulk pool**
  - 6 × 14TB Toshiba MG09 (SATA), 1 × 6-wide RAIDZ2
  - 5 × 4TB HGST Ultrastar 7K4000 (SAS), 1 × 5-wide RAIDZ1
- **Fast pool**
  - 2 × 1TB Crucial MX500 (SSD), mirrored
- **Network** — Intel X520-DA2, 10G
- **Out-of-band** — JetKVM + ATX Extension Board

### Networking

**Server Rack** · 12U

- **UniFi UDM Pro Max** — 2.5G/10G router & NVR, 1 × 8TB Seagate SkyHawk AI (SATA)
- **UniFi USW Aggregation** — 10G aggregation switch
- **UniFi USW Pro HD 24 PoE** — 2.5G/10G PoE++ core switch

### Power

- **UniFi UPS 2U** — 1500VA rackmount UPS

### Eye candy

<details>
  <summary>Expand to look in my basement</summary>
  <img src="https://github.com/bykaj/home-ops/blob/main/assets/images/rack.jpg?raw=true" width="400px">
</details>

Per-node details (disks, NICs, Talos volumes) are in the [hardware documentation](https://docs.bykaj.com/hardware/), and what's planned next lives under [Future Plans](https://docs.bykaj.com/reference/future-plans/).

---

## <img src="https://fonts.gstatic.com/s/e/notoemoji/latest/1f64f/512.gif" alt="🙏" width="20" height="20"> Gratitude and Thanks

A lot of inspiration for my cluster comes from the people that have shared their clusters using the [k8s-at-home](https://github.com/topics/k8s-at-home) GitHub topic. Be sure to check out the [Kubesearch](http://kubesearch.dev) tool for ideas on how to deploy applications or get ideas on what you can deploy.

If you want to try and follow along with some of the practices I use here, there is a template available at [onedr0p/cluster-template](https://github.com/onedr0p/cluster-template).

For learning the basics of running and maintaining a Kubernetes cluster, particularly [K3s](https://k3s.io/), I highly recommend starting with [Jim's Garage](https://youtube.com/@jims-garage) excellent [Kubernetes at Home](https://youtube.com/playlist?list=PLXHMZDvOn5sVXjb88kYXSI7UMx4rhQwOj&si=E6qRPZ915IXQYGL0) series. Once you're comfortable with the basics and ready to automate your deployments, [Techno Tim's](https://www.youtube.com/@TechnoTim) [K3s Ansible guide](https://github.com/techno-tim/k3s-ansible) provides a great foundation for automated cluster rollouts. Thanks to both [@JamesTurland](https://github.com/JamesTurland) and [@timothystewart6](https://github.com/timothystewart6) for these great resources!

And of course, shoutout to [@QNimbus](https://github.com/QNimbus) for his bash scripts that are more engineered than a Swiss watch—but hey, they actually work!

---

## <img src="https://fonts.gstatic.com/s/e/notoemoji/latest/1f512/512.gif" alt="🔒" width="20" height="20"> License

See [LICENSE](https://github.com/bykaj/home-ops/blob/main/LICENSE). **TL;DR**: Do with it as you please, but if it becomes sentient, you're responsible for teaching it manners.
