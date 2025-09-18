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
- **CNI**: Cilium (eBPF-based networking)
- **Storage**:
  - Rook-Ceph for distributed block storage
  - OpenEBS for local container-attached storage
  - TrueNAS for NFS/SMB shares (virtualized separately)
- **GitOps**: Flux v2 with SOPS encryption
- **DNS**: CoreDNS with k8s-gateway for internal services
- **Ingress**: Cilium Gateway API with Cloudflare Tunnel

### Cluster Configuration
- **3-node control plane**: All nodes are control plane (HA setup)
- **Network**: 10.73.10.0/20 subnet with VIP at 10.73.10.1
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
├── talos/              # Talos cluster configuration
├── bootstrap/          # Initial cluster bootstrap (Helmfile)
└── scripts/            # Utility scripts
```

### Kubernetes Apps Organization
Applications are organized by namespace under `kubernetes/apps/`:
- `cert-manager/` - SSL certificate management
- `kube-system/` - Core Kubernetes components (Cilium, CoreDNS, etc.)
- `flux-system/` - Flux GitOps operator
- `external-secrets/` - External secret management
- `rook-ceph/` - Distributed storage
- `monitoring/` - Prometheus, Grafana, Loki stack
- `media/` - Plex, Jellyfin, etc.
- `downloads/` - *arr applications (Sonarr, Radarr, etc.)
- `tools/` - Self-hosted applications

Each app follows the pattern:
```
app-name/
├── app/
│   ├── helmrelease.yaml      # Helm chart deployment
│   ├── kustomization.yaml    # Kustomize configuration
│   └── helm/
│       └── values.yaml       # Helm chart values
└── ks.yaml                   # Flux Kustomization
```

## Flux Workflow

Flux watches the `kubernetes/` directory and applies changes through two main Kustomizations:
1. **cluster-meta**: Applies Flux repositories and common resources
2. **cluster-apps**: Applies all application workloads with dependency management

### Key Files
- `kubernetes/flux/cluster/ks.yaml`: Main Flux Kustomizations
- `kubernetes/components/common/cluster-settings.yaml`: Global configuration (timezone, etc.)
- `kubernetes/components/common/sops/`: SOPS encrypted secrets

## Working with the Repository

### Adding New Applications
1. Create directory structure under `kubernetes/apps/namespace/app-name/`
2. Add `ks.yaml` (Flux Kustomization)
3. Add `app/` directory with `helmrelease.yaml` and `kustomization.yaml`
4. Update parent namespace `kustomization.yaml`

### Secrets
- Use External Secrets for runtime secrets (1Password integration)
- Use SOPS for GitOps secrets (cluster configuration, certificates)
- Never commit plaintext secrets

### Dependencies
Applications can depend on other Flux resources using `dependsOn` in Kustomizations or `needs` in Helmfile.

## Environment Variables
- `KUBECONFIG`: Points to cluster kubeconfig file
- `TALOSCONFIG`: Points to Talos configuration
- `SOPS_AGE_KEY_FILE`: Points to AGE encryption key

## Prerequisites
Required tools:
- `task` - Task runner
- `flux` - Flux CLI
- `kubectl` - Kubernetes CLI
- `talosctl` - Talos CLI
- `talhelper` - Talos configuration helper
- `helmfile` - Helm deployment tool
- `sops` - Secret encryption
- `yq` - YAML processor