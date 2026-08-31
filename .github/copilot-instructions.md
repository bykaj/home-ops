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
- **Ingress**: Envoy Gateway with Cloudflare Tunnel

## Repository Structure

```
├── kubernetes/
│   ├── apps/          # Application deployments (organized by namespace)
│   ├── bootstrap/     # Initial cluster bootstrap (Helmfile)
│   ├── components/    # Reusable kustomize components
│   ├── flux/          # Flux system configuration
│   └── talos/         # Talos cluster configuration
├── bootstrap/
│   └── workstation/   # Workstation tooling (Brewfile)
├── docker/
│   └── truenas/       # Docker Compose stacks for TrueNAS
└── scripts/           # Utility scripts
```

## Critical Workflows

### Cluster Management Commands (Just)

```bash
# List all available commands
just

# Bootstrap the full cluster end-to-end
just bootstrap cluster

# Sync all Flux Kustomizations
just k8s sync ks

# Sync all Flux HelmReleases
just k8s sync hr
```

### Talos Operations

```bash
# Apply config to a specific node
just talos apply-node 10.73.10.110

# Upgrade Talos on a specific node
just talos upgrade-node 10.73.10.110

# Upgrade Kubernetes version
just talos upgrade-k8s 1.30.0

# Generate kubeconfig
just talos gen-kubeconfig
```

## Application Patterns

### Flux Application Structure

Applications follow this standard pattern:

```
app-name/
├── ks.yaml                   # Flux Kustomization
└── app/
    ├── kustomization.yaml    # Kustomize configuration
    ├── ocirepository.yaml    # OCI repository reference for the chart
    ├── helmrelease.yaml      # Helm chart deployment
    └── other resources...
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

- `just`: Primary command runner
- `flux`: Flux CD CLI
- `kubectl`: Kubernetes CLI
- `talosctl`: Talos CLI
- `helmfile`: Helm deployment tool
- `sops`: Secret encryption
- `op`: 1Password CLI
- `minijinja-cli`: Template rendering
- `gum`: Interactive prompts

## YAML Sorting Rules

### Default rule

All fields and properties should be sorted alphabetically at every level of the YAML structure, regardless of how deeply nested they are, unless a specific override rule applies.

### Kubernetes resource field order

When present at the same level, these fields must be ordered as:

1. `apiVersion`
2. `kind`
3. `metadata`
4. `spec`

Fields within `metadata` must be ordered as:

1. `name`
2. `namespace`
3. `annotations`
4. `labels`

### HelmReleases based on app-template

Applies to HelmReleases identified by a sidecar `ocirepository.yaml` referencing `oci://ghcr.io/bjw-s-labs/helm/app-template`.

- `enabled` fields are always first within their section (unless a more specific rule overrides this).
- Do NOT sort arbitrary YAML content embedded in string fields (e.g. `configMap.data.*` values).

**`spec` field order:**

1. `chartRef`
2. `interval`
3. `dependsOn`
4. `install`
5. `upgrade`
6. `values`

**`spec.values` field order:**

1. `defaultPodOptions` (if present)
2. All other sibling keys sorted alphabetically (e.g. `controllers`, `persistence`, `route`, `service`)

Note: Sibling keys within `persistence.*`, `service.*`, `route.*`, `configMaps.*`, etc. are NOT required to be sorted relative to each other — only the keys _within_ each individual item.

**`spec.values.controllers.*` field order:**

1. `type` (if present)
2. `annotations` (if present)
3. `labels` (if present)
4. Controller-specific fields (e.g. `cronjob`, `statefulset`) (if present)
5. `pod`
6. All other fields alphabetically
7. `initContainers` (last but one, if present)
8. `containers` (last, if present)

**`spec.values.controllers.*.containers.*` field order:**

1. `image`
2. All other fields alphabetically

**`resources` sections:** `requests` before `limits`

**`spec.values.service.*` field order:**

1. `type` (if present)
2. `annotations` (if present)
3. `labels` (if present)
4. All other fields alphabetically

**`persistence.*` item field order:**

1. `type` (if present)
2. `annotations` (if present)
3. `labels` (if present)
4. All other fields alphabetically
5. `globalMounts` (second to last, if present)
6. `advancedMounts` (last, if present)
