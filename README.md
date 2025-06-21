<div align="center">

<img src="https://github.com/bykaj/home-ops/blob/main/assets/images/home-ops-logo.png?raw=true" align="center" width="144px" height="144px"/>

## Home Operations Repository

_Managed with Flux, Renovate, and GitHub Actions_

[![Renovate](https://img.shields.io/badge/powered_by-Renovate-blue?style=for-the-badge&logo=renovate)](https://www.mend.io/renovate/)

Kubernetes cluster stats:

[![Talos](https://img.shields.io/endpoint?url=https%3A%2F%2Fstats.bykaj.io%2Ftalos_version&style=for-the-badge&logo=talos&logoColor=white&color=orange&label=talos)](https://talos.dev)&nbsp;
[![Kubernetes](https://img.shields.io/endpoint?url=https%3A%2F%2Fstats.bykaj.io%2Fkubernetes_version&style=for-the-badge&logo=kubernetes&logoColor=white&color=blue&label=k8s)](https://kubernetes.io)&nbsp;
[![Flux](https://img.shields.io/endpoint?url=https%3A%2F%2Fstats.bykaj.io%2Fflux_version&style=for-the-badge&logo=flux&logoColor=white&color=blue&label=flux)](https://fluxcd.io)

[![Age-Days](https://img.shields.io/endpoint?url=https%3A%2F%2Fstats.bykaj.io%2Fcluster_age_days&style=for-the-badge&label=Age)](https://github.com/kashalls/kromgo)&nbsp;
[![Uptime-Days](https://img.shields.io/endpoint?url=https%3A%2F%2Fstats.bykaj.io%2Fcluster_uptime_days&style=for-the-badge&label=Uptime)](https://github.com/kashalls/kromgo)&nbsp;
[![Node-Count](https://img.shields.io/endpoint?url=https%3A%2F%2Fstats.bykaj.io%2Fcluster_node_count&style=for-the-badge&label=Nodes)](https://github.com/kashalls/kromgo)&nbsp;
[![Pod-Count](https://img.shields.io/endpoint?url=https%3A%2F%2Fstats.bykaj.io%2Fcluster_pod_count&style=for-the-badge&label=Pods)](https://github.com/kashalls/kromgo)&nbsp;
[![CPU-Usage](https://img.shields.io/endpoint?url=https%3A%2F%2Fstats.bykaj.io%2Fcluster_cpu_usage&style=for-the-badge&label=CPU)](https://github.com/kashalls/kromgo)&nbsp;
[![Memory-Usage](https://img.shields.io/endpoint?url=https%3A%2F%2Fstats.bykaj.io%2Fcluster_memory_usage&style=for-the-badge&label=Memory)](https://github.com/kashalls/kromgo)&nbsp;
[![Alerts](https://img.shields.io/endpoint?url=https%3A%2F%2Fstats.bykaj.io%2Fcluster_alert_count&style=for-the-badge&label=Alerts)](https://github.com/kashalls/kromgo)

</div>

---

## <img src="https://fonts.gstatic.com/s/e/notoemoji/latest/1f4a1/512.gif" alt="💡" width="20" height="20"> Overview 

This is a mono repository for my wildly over-engineered home infrastructure and Kubernetes cluster, because apparently I hate free time. I try to follow Infrastructure as Code (IaC) and GitOps practices using enterprise-grade tools like [Ansible](https://www.ansible.com/), [Kubernetes](https://kubernetes.io/), [Flux](https://github.com/fluxcd/flux2), [Renovate](https://github.com/renovatebot/renovate) and [GitHub Actions](https://github.com/features/actions)—you know, the same stack Netflix uses, except mine just runs my Plex server and some smart lightbulbs. Ok, I also use some trusty [bash](https://en.wikipedia.org/wiki/Bash_(Unix_shell)) scripts held together by duct tape and prayer.

---

## <img src="https://fonts.gstatic.com/s/e/notoemoji/latest/1f331/512.gif" alt="🌱" width="20" height="20"> Kubernetes

My Kubernetes cluster is deployed on a [Proxmox VE](https://www.proxmox.com) cluster with [Talos](https://www.talos.dev). This is a semi-hyper-converged cluster, workloads and block storage are sharing the same available resources on my nodes while I have a separate [TrueNAS](https://www.truenas.com) server with ZFS for NFS/SMB shares, bulk file storage and backups.

There is a template over at [onedr0p/cluster-template](https://github.com/onedr0p/cluster-template) if you want to try and follow along with some of the practices I use here.

### Core Components

- [actions-runner-controller](https://github.com/actions/actions-runner-controller): Self-hosted GitHub runners;
- [cert-manager](https://github.com/cert-manager/cert-manager): Creates SSL certificates for services in my cluster;
- [cilium](https://github.com/cilium/cilium): eBPF-based networking for my workloads;
- [cloudflared](https://github.com/cloudflare/cloudflared): Enables Cloudflare secure access to my routes;
- [external-dns](https://github.com/kubernetes-sigs/external-dns): Automatically syncs ingress DNS records to a DNS provider;
- [external-secrets](https://github.com/external-secrets/external-secrets): Managed Kubernetes secrets using [1Password Connect](https://github.com/1Password/connect);
- [rook](https://github.com/rook/rook): Distributed block storage with Ceph for peristent storage;
- [sops](https://github.com/getsops/sops): Managed secrets for Kubernetes and Ansible which are commited to Git;
- [spegel](https://github.com/spegel-org/spegel): Stateless cluster local OCI registry mirror;
- [volsync](https://github.com/backube/volsync): Backup and recovery of persistent volume claims.

### GitOps

[Flux](https://github.com/fluxcd/flux2) watches the clusters in my [kubernetes](./kubernetes/) folder (see [Directories](#directories) below) and makes the changes to my clusters based on the state of my Git repository.

The way Flux works for me here is it will recursively search the `kubernetes/apps` folder until it finds the most top level `kustomization.yaml` per directory and then apply all the resources listed in it. That aforementioned `kustomization.yaml` will generally only have a namespace resource and one or many Flux kustomizations (`ks.yaml`). Under the control of those Flux kustomizations there will be a `HelmRelease` or other resources related to the application which will be applied.

[Renovate](https://github.com/renovatebot/renovate) watches my **entire** repository looking for dependency updates, when they are found a PR is automatically created. When some PRs are merged Flux applies the changes to my cluster.

### Directories

This Git repository contains the following directories under [Kubernetes](./kubernetes/).

```sh
📁 kubernetes
├── 📁 apps       # applications
├── 📁 components # re-useable kustomize components
└── 📁 flux       # flux system configuration
```

### Flux Workflow

This is a high-level look how Flux deploys my applications with dependencies. In most cases a `HelmRelease` will depend on other `HelmRelease`'s, in other cases a `Kustomization` will depend on other `Kustomization`'s, and in rare situations an app can depend on a `HelmRelease` and a `Kustomization`. The example below shows that `plex` won't be deployed or upgrade until the `rook-ceph-cluster` Helm release is installed or in a healthy state.

```mermaid
graph TD
    A>Kustomization: rook-ceph] -->|Creates| B[HelmRelease: rook-ceph]
    A>Kustomization: rook-ceph] -->|Creates| C[HelmRelease: rook-ceph-cluster]
    C>HelmRelease: rook-ceph-cluster] -->|Depends on| B>HelmRelease: rook-ceph]
    D>Kustomization: plex] -->|Creates| E(HelmRelease: plex)
    E>HelmRelease: plex] -->|Depends on| C>HelmRelease: rook-ceph-cluster]
```

---

## <img src="https://fonts.gstatic.com/s/e/notoemoji/latest/1f636_200d_1f32b_fe0f/512.gif" alt="😶" width="20" height="20"> Cloud Dependencies

While most of my infrastructure and workloads are self-hosted I do rely upon the cloud for certain key parts of my setup. This saves me from having to worry about three things. (1) Dealing with chicken/egg scenarios, (2) services I critically need whether my cluster is online or not and (3) The "hit by a bus factor" - what happens to critical apps (e.g. Email, Password Manager, Photos) that my family relies on when I no longer around.

Alternative solutions to the first two of these problems would be to host a Kubernetes cluster in the cloud and deploy applications like [HCVault](https://www.vaultproject.io/), [Vaultwarden](https://github.com/dani-garcia/vaultwarden), [ntfy](https://ntfy.sh/), and [Gatus](https://gatus.io/); however, maintaining another cluster and monitoring additional workloads would definitely be more work and more costly.

| Service                                         | Use                                                               
|-------------------------------------------------|-------------------------------------------------------------------
| [1Password](https://1password.com/)             | Secrets with [External Secrets](https://external-secrets.io/)     
| [Cloudflare](https://www.cloudflare.com/)       | External DNS and Argo tunnel                                                   
| [Fastmail](https://fastmail.com/)               | Email hosting   
| [GitHub](https://github.com/)                   | Hosting this repository and continuous integration/deployments                                                      
| [Pushover](https://pushover.net/)               | Kubernetes Alerts and application notifications 
| [StorJ](https://storj.io)                       | S3 object storage for applications and backups                  
| [UptimeRobot](https://uptimerobot.com/)         | Monitoring internet connectivity and external facing applications 
                                                           
---

## <img src="https://fonts.gstatic.com/s/e/notoemoji/latest/1f30e/512.gif" alt="🌎" width="20" height="20"> DNS

In my cluster there are two instances of [ExternalDNS](https://github.com/kubernetes-sigs/external-dns) running. One for syncing private DNS records to my `UDM Pro Max` using [ExternalDNS webhook provider for UniFi](https://github.com/kashalls/external-dns-unifi-webhook), while another instance syncs public DNS to `Cloudflare`. This setup is managed by creating ingresses with two specific classes: `internal` for private DNS and `external` for public DNS. The `external-dns` instances then syncs the DNS records to their respective platforms accordingly.

---

## <img src="https://fonts.gstatic.com/s/e/notoemoji/latest/2699_fe0f/512.gif" alt="⚙" width="20" height="20"> Hardware

| Device                      | Num | OS Disk Size | Data Disk Size                  | Ram  | OS            | Function                |
|-----------------------------|-----|--------------|---------------------------------|------|---------------|-------------------------|
| Lenovo M920q, i5-8500T      | 2   | 1TB SSD      |                                 | 64GB | Proxmox VE    | VM Host                 |
| Self-build 2U, i7-6700K     | 1   | 512MB SSD    | 1x1TB SSD, 5x14TB SATA (ZFS), 5x4TB SAS (ZFS) | 64GB | Proxmox VE    | VM Host, SMB/NFS + Backup Server |
| PiKVM V4 Plus               | 1   | 32GB eMMC    | -                               | 8GB  | PiKVM         | KVM                     |
| JetKVM                      | 3   | -            | -                               | -    | JetKVM        | KVM                     |
| UniFi UDM Pro Max           | 1   | -            | 8TB HDD                         | -    | -             | Router & NVR            |
| UniFi USW Pro HD 24 PoE     | 1   | -            | -                               | -    | -             | 2.5Gb/10Gb PoE Core Switch |
| UniFi USW Flex 2.5G 5       | 1   | -            | -                               | -    | -             | 2.5Gb Switch            |
| Home Assistant Yellow       | 1   | 8GB eMMC     | 256GB SSD                       | 4GB  | Home Asssitant OS | Home Automation         |
| Eaton Ellipse Pro 650 2U    | 1   | -            | -                               | -    | -             | UPS                     |

---

## <img src="https://fonts.gstatic.com/s/e/notoemoji/latest/1f64f/512.gif" alt="🙏" width="20" height="20"> Gratitude and Thanks

A lot of inspiration for my cluster comes from the people that have shared their clusters using the [k8s-at-home](https://github.com/topics/k8s-at-home) GitHub topic. Be sure to check out the awesome [Kubesearch](http://kubesearch.dev) tool for ideas on how to deploy applications or get ideas on what you can deploy.

---

## 🔏 License

See [LICENSE](https://github.com/bykaj/home-ops/blob/main/LICENSE). **TL;DR**: Do with it as you please, but if it becomes sentient, you're responsible for teaching it manners.
