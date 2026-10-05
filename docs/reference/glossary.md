---
description: Terms and acronyms used in these docs
---

# Glossary

app-template
:   The [bjw-s Helm chart](https://bjw-s-labs.github.io/helm-charts/docs/app-template/)
    almost every app is deployed with.

ASN
:   Autonomous System Number, the identifier of a BGP speaker. The UDM is
    64513, Cilium 64514 and the NAS 64515.

BGP
:   Border Gateway Protocol. Used here to announce LoadBalancer VIPs from
    the nodes and the NAS to the UDM.

CNPG
:   [CloudNative-PG](https://cloudnative-pg.io), the PostgreSQL operator.

DRA
:   Dynamic Resource Allocation, the Kubernetes API the Intel GPU driver uses
    to hand iGPUs to pods.

DSR
:   Direct Server Return. Cilium's load-balancing mode, where replies go
    straight from the backend to the client.

ECMP
:   Equal-Cost Multi-Path routing. The UDM spreads traffic for a VIP across
    every node that announces it.

doco-cd
:   [Docker Compose continuous deployment](https://github.com/kimdre/doco-cd).
    It is GitOps for the NAS stacks.

flate
:   [home-operations/flate](https://github.com/home-operations/flate). It
    renders a Flux Kustomization locally, with components and substitutions,
    exactly as Flux would.

Kopiur
:   [home-operations/kopiur](https://github.com/home-operations/kopiur), a
    Kopia-based PVC backup operator with volume-populator restores.

konflate
:   A Flux PR previewer that posts rendered diffs as comments and status checks.

OSD
:   Object Storage Daemon. One Ceph OSD runs per Micron NVMe drive.

RBD
:   RADOS Block Device, Ceph's block storage. It backs the `ceph-block`
    StorageClass.

schematic
:   A Talos [Image Factory](https://factory.talos.dev) definition (system
    extensions and kernel arguments). Its content hash selects the installer
    image.

tuppr
:   [home-operations/tuppr](https://github.com/home-operations/tuppr), the
    Talos and Kubernetes upgrade controller.

UDM
:   UniFi Dream Machine (Pro Max), the router and firewall.

VIP
:   Virtual IP. An address announced over BGP rather than bound to one host.
