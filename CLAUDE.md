# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a GitOps-managed Kubernetes cluster repository using Flux v2 for continuous deployment. The cluster runs on Talos Linux VMs hosted on Proxmox VE infrastructure. The repository follows Infrastructure as Code (IaC) principles with enterprise-grade tooling.

## Development Commands

### Core Task Runner
This repository uses [Task](https://taskfile.dev) as the main task runner. All commands are defined in `Taskfile.yaml`:

```bash
# List all available tasks
task

# Force Flux to reconcile changes from Git
task reconcile

# Bootstrap Talos cluster (creates cluster from scratch)
task bootstrap:talos

# Bootstrap applications into existing cluster
task bootstrap:apps
```

### Talos Operations
Talos-specific commands are in `.taskfiles/talos/Taskfile.yaml`:

```bash
# Generate Talos configuration files
task talos:generate-config

# Apply config to specific node (requires IP variable)
task talos:apply-node IP=10.73.10.110

# Upgrade Talos on specific node
task talos:upgrade-node IP=10.73.10.110

# Upgrade Kubernetes version
task talos:upgrade-k8s

# Reset cluster (destructive operation)
task talos:reset
```

### Manual Commands
- **Flux reconciliation**: `flux --namespace flux-system reconcile kustomization flux-system --with-source`
- **Bootstrap script**: `bash scripts/bootstrap-apps.sh` (applies namespaces, SOPS secrets, CRDs, and Helm releases)

## Architecture Overview

### Infrastructure Stack
- **OS**: Talos Linux (immutable, minimal Kubernetes OS)
- **Container Runtime**: containerd
- **CNI**: Cilium (eBPF-based networking with Gateway API)
- **Storage**:
  - Rook-Ceph for distributed block storage
  - OpenEBS for local container-attached storage
  - CSI drivers for NFS and SMB shares
- **GitOps**: Flux v2 with SOPS encryption using Flux Operator
- **DNS**: CoreDNS with external-dns for Cloudflare and UniFi
- **Ingress**: Envoy Gateway with HTTPRoute/TLSRoute and Cloudflare Tunnel
- **Monitoring**: Prometheus stack with Grafana, Loki, and Alloy

### Cluster Configuration
- **3-node control plane**: All nodes are control plane (HA setup)
- **Network**: 10.73.10.0/20 subnet with VIP at 10.73.10.10
- **Pod CIDR**: 10.42.0.0/16
- **Service CIDR**: 10.43.0.0/16

### Secrets Management
- **SOPS** for encrypting secrets in Git using AGE encryption
- **External Secrets Operator** with 1Password Connect for secret injection
- **Age key** stored in `age.key` (not in Git)

## Directory Structure

```
├── kubernetes/
│   ├── apps/           # Application deployments (organized by namespace)
│   ├── components/     # Reusable Kustomize components
│   └── flux/           # Flux system configuration
├── talos/              # Talos cluster configuration (with Jinja2 templates)
├── bootstrap/          # Initial cluster bootstrap (Helmfile with Justfile)
├── scripts/            # Utility scripts
└── archive/            # Archived configurations
```

### Kubernetes Apps Organization
Applications are organized by namespace under `kubernetes/apps/`:
- `actions-runner-system/` - GitHub Actions self-hosted runners
- `cert-manager/` - SSL certificate management
- `database/` - Database services (CloudNative-PG, Dragonfly, Meilisearch)
- `default/` - General applications (homepage, paperless, etc.)
- `development/` - Development tools (Coder)
- `downloads/` - *arr applications (Sonarr, Radarr, Prowlarr, etc.)
- `external-secrets/` - External secret management with 1Password Connect
- `flux-system/` - Flux GitOps operator and instance
- `infrastructure/` - Infrastructure services (EMQX broker)
- `jobs/` - Scheduled jobs (mail backup, schema publishing)
- `kube-system/` - Core Kubernetes components (Cilium, CoreDNS, metrics-server)
- `media/` - Media services (Plex, Jellyfin, Audiobookshelf, etc.)
- `network/` - Networking (Envoy Gateway, Cloudflare Tunnel, external-dns, etc.)
- `observability/` - Monitoring stack (Prometheus, Grafana, Loki, Alloy, etc.)
- `rook-ceph/` - Distributed storage operator and tools
- `security/` - Authentication and security (Authentik, OIDC debugger)
- `system-upgrade/` - Automated system upgrades (Tuppr)
- `system/` - System services (CSI drivers, KEDA, OpenEBS, etc.)

Each app follows the pattern:
```
app-name/
├── app/
│   ├── helmrelease.yaml      # Helm chart deployment
│   ├── kustomization.yaml    # Kustomize configuration
│   ├── ocirepository.yaml    # OCI repository (replaces Helm repos)
│   └── externalsecret.yaml   # External secret configuration
└── ks.yaml                   # Flux Kustomization
```

## Flux Workflow

Flux watches the `kubernetes/` directory and applies changes through a single main Kustomization:
- **cluster-apps**: Applies all application workloads with dependency management and SOPS decryption

### Key Files
- `kubernetes/flux/cluster/ks.yaml`: Main Flux Kustomization with SOPS patches and postBuild substitutions
- `kubernetes/components/common/cluster-secrets.sops.yaml`: SOPS encrypted cluster secrets
- `kubernetes/external-secrets/external-secrets/cluster-secrets/`: External secrets configuration

## Working with the Repository

### Adding New Applications
1. Create directory structure under `kubernetes/apps/namespace/app-name/`
2. Add `ks.yaml` (Flux Kustomization)
3. Add `app/` directory with:
   - `helmrelease.yaml` (Helm chart configuration)
   - `kustomization.yaml` (Kustomize resources)
   - `ocirepository.yaml` (OCI registry source)
   - `externalsecret.yaml` (if secrets needed)
4. Update parent namespace `kustomization.yaml` to include new app

### Secrets
- Use External Secrets for runtime secrets (1Password integration)
- Use SOPS for GitOps secrets (cluster configuration, certificates)
- Never commit plaintext secrets

### Dependencies
Applications can depend on other Flux resources using `dependsOn` in Kustomizations. The cluster uses a single main Kustomization for all apps with automatic dependency resolution.

## Environment Variables
- `KUBECONFIG`: Points to cluster kubeconfig file
- `TALOSCONFIG`: Points to Talos configuration
- `SOPS_AGE_KEY_FILE`: Points to AGE encryption key

## Repository Status

### Recent Changes
The repository has moved from Helm repositories to OCI repositories for most charts, improving security and reliability. The Goldilocks application recently switched from the deprecated Fairwinds Helm repository to using HelmRepository resources.

### Current State
- Flux meta configuration has been simplified (deleted legacy meta directory structure)
- Applications now primarily use OCI repositories for Helm charts
- Goldilocks VPA (Vertical Pod Autoscaler) and dashboard are configured
- All major applications have monitoring and observability configured

## Prerequisites
Required tools:
- `task` - Task runner
- `flux` - Flux CLI
- `kubectl` - Kubernetes CLI
- `talosctl` - Talos CLI
- `just` - Command runner (for Justfiles)
- `helmfile` - Helm deployment tool
- `sops` - Secret encryption
- `yq` - YAML processor
- `jinja2` - Template engine for Talos configs
