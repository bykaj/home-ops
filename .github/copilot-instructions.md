# AI Agent Guidelines for Home-Ops Repository

This guide helps AI agents understand key aspects of this GitOps-managed Kubernetes cluster.

## Architecture Overview

This is a GitOps-managed Kubernetes cluster running on Talos Linux VMs hosted on Proxmox VE infrastructure, with the following key components:

- **OS**: Talos Linux (immutable, minimal Kubernetes OS)
- **Container Runtime**: containerd
- **CNI**: Cilium (eBPF-based networking)
- **Storage**:
  - Rook-Ceph for distributed block storage
  - OpenEBS for local container-attached storage
  - TrueNAS for NFS/SMB shares (virtualized separately)
- **GitOps**: Flux v2 with SOPS encryption for secrets
- **DNS**: Split-horizon DNS with ExternalDNS for internal/external resolution
- **Ingress**: Cilium Gateway API with Cloudflare Tunnel

## Repository Structure

```
├── kubernetes/
│   ├── apps/          # Application deployments (organized by namespace)
│   ├── components/    # Reusable kustomize components
│   └── flux/          # Flux system configuration
├── talos/             # Talos cluster configuration
├── bootstrap/         # Initial cluster bootstrap (Helmfile)
└── scripts/           # Utility scripts
```

## Critical Workflows

### Cluster Management Commands (Task)

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

```bash
# Generate Talos configuration files
task talos:generate-config

# Apply config to specific node (replace IP)
task talos:apply-node IP=10.73.10.110

# Upgrade Talos on specific node
task talos:upgrade-node IP=10.73.10.110

# Upgrade Kubernetes version
task talos:upgrade-k8s
```

### Just File Commands

Just files are an alternative command interface for some operations:

```bash
# Apply Talos config to a node
just talos apply-node kube-node-01

# Upgrade Kubernetes
just talos upgrade-k8s 1.30.0
```

## Application Patterns

### Flux Application Structure

Applications follow this standard pattern:
```
app-name/
├── app/
│   ├── helmrelease.yaml      # Helm chart deployment
│   ├── kustomization.yaml    # Kustomize configuration
│   └── other resources...
└── ks.yaml                   # Flux Kustomization
```

### Application Dependencies

Flux handles dependencies between components with:

1. `dependsOn` in Flux Kustomizations
2. `needs` in Helmfile releases

Example from a HelmRelease:
```yaml
spec:
  dependsOn:
    - name: rook-ceph-cluster
      namespace: rook-ceph
```

### Secrets Management

Three layers of secrets management:
1. **SOPS** for encrypting secrets in Git using AGE encryption
2. **External Secrets Operator** with 1Password Connect for runtime secrets
3. **Age key** stored in `age.key` (not in Git)

Never commit plaintext secrets. Always use SOPS or External Secrets.

## Environment Configuration

Required environment variables:
- `KUBECONFIG`: Points to cluster kubeconfig file
- `TALOSCONFIG`: Points to Talos configuration
- `SOPS_AGE_KEY_FILE`: Points to AGE encryption key

## Prerequisites & Tools

Core tools used in this repository:
- `task`: Primary task runner
- `flux`: Flux CD CLI
- `kubectl`: Kubernetes CLI
- `talosctl`: Talos CLI
- `talhelper`: Talos configuration helper
- `helmfile`: Helm deployment tool
- `sops`: Secret encryption
- `op`: 1Password CLI
- `just`: Command runner alternative
