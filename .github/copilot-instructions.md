# AI Agent Guidelines for Home-Ops Repository

This guide helps AI agents understand key aspects of this GitOps-managed Kubernetes cluster.

## Architecture Overview

This is a GitOps-managed Kubernetes cluster running on bare-metal Talos Linux nodes (3-node cluster, `k8s-01`/`k8s-02`/`k8s-03` — no hypervisor), with the following key components:

- **OS**: Talos Linux (immutable, minimal Kubernetes OS)
- **Container Runtime**: containerd
- **CNI**: Cilium (eBPF-based networking; announces LoadBalancer Service IPs to the UDM router over BGP)
- **Storage**:
  - Rook-Ceph for distributed block storage
  - OpenEBS for local container-attached storage
  - A separate physical TrueNAS server for NFS/SMB shares, bulk storage and backups
- **GitOps**: Flux v2 (cluster) + doco-cd (Docker Compose on the NAS), with Renovate opening dependency-update PRs across the whole repo
- **Secrets**: External Secrets Operator + 1Password Connect for runtime secrets
- **DNS**: Split-horizon DNS with two ExternalDNS instances (`internal` ingress class → UniFi UDM, `external` ingress class → Cloudflare)
- **Ingress**: Envoy Gateway (`envoy-internal`/`envoy-external` Gateways) with Cloudflare Tunnel for public exposure

## Repository Structure

```text
├── kubernetes/
│   ├── apps/          # Application deployments (organized by namespace)
│   ├── clusters/main/  # Top-level Flux Kustomization (cluster-apps) that applies apps/
│   ├── components/    # Reusable kustomize components (kopiur, postgres, dragonfly, ...)
│   └── talos/          # Talos machine-config templates (Jinja) and node definitions
├── bootstrap/           # Ansible + just recipes that bring up the cluster and NAS from scratch
├── docker/
│   └── nas/             # Docker Compose stacks deployed to the NAS via doco-cd (GitOps)
├── ansible/              # Playbooks/inventory used by bootstrap and NAS reconciliation
└── scripts/              # Utility scripts (VM management, Talos image download)
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

Nodes are addressed by hostname (`k8s-01`, `k8s-02`, `k8s-03`), matching the config templates under `kubernetes/talos/nodes/`:

```bash
# Apply config to a specific node
just talos apply-node k8s-01

# Upgrade Talos on a specific node
just talos upgrade-node k8s-01

# Upgrade Kubernetes version cluster-wide
just talos upgrade-k8s 1.34.0
```

Kubeconfig is fetched as part of `just bootstrap cluster`, not via a standalone Talos recipe.

## Application Patterns

### Flux Application Structure

Applications live at `kubernetes/apps/<namespace>/<app>/` and follow this standard pattern:

```text
<app>/
├── ks.yaml                   # Flux Kustomization
└── app/
    ├── kustomization.yaml    # Kustomize configuration
    ├── ocirepository.yaml    # Pins the app-template chart version
    ├── helmrelease.yaml      # Helm chart deployment (bjw-s-labs/app-template)
    ├── externalsecret.yaml   # Optional — 1Password-backed secrets
    └── resources/            # Optional — files wired in via configMapGenerator
```

Flux's top-level `cluster-apps` Kustomization (`kubernetes/clusters/main/apps.yaml`) applies `kubernetes/apps` recursively and patches shared defaults (retry/timeout, HelmRelease install/upgrade strategy) onto every Kustomization/HelmRelease it manages, so individual apps should not redeclare them.

### Application Dependencies

Flux handles dependencies between components with:

1. `dependsOn` in Flux Kustomizations
2. `dependsOn` in HelmReleases

Example from a Flux Kustomization:

```yaml
spec:
  dependsOn:
    - name: rook-ceph-cluster
```

### Secrets Management

Two independent layers, both backed by 1Password — never commit plaintext secrets:

1. **Kubernetes**: External Secrets Operator + 1Password Connect (`ClusterSecretStore: onepassword-connect`) populate Kubernetes Secrets from `ExternalSecret` resources.
2. **Docker Compose (NAS)**: doco-cd resolves `op://` references declared in `docker/<host>/.doco-cd.yaml` and injects them as env vars at deploy time.

## Environment Configuration

Tool versions and required environment variables (`KUBECONFIG`, `TALOSCONFIG`, `FLATE_PATH`, `MINIJINJA_CONFIG_FILE`) are managed by [mise](https://mise.jdx.dev) via `.mise/config.toml` — running `mise install`/activating mise in the shell sets these automatically; there's no need to export them manually.

## Prerequisites & Tools

Core tools used in this repository (full pinned list in `.mise/config.toml`, installed via `mise install`):

- `just`: Primary command runner
- `flux`: Flux CD CLI
- `kubectl` / `kustomize` / `kubeconform`: Kubernetes manifest tooling
- `talosctl`: Talos CLI
- `helm` / `helmfile`: Helm chart tooling
- `op`: 1Password CLI (secret resolution via `op inject`)
- `minijinja-cli`: Template rendering
- `yq` / `jq`: YAML/JSON processing
- `lefthook`: Git hooks (formatting/linting on commit)
- `ansible`: Bootstrap and NAS provisioning
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
