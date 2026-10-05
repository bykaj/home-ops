---
description: Talos machine configuration, schematics and node operations
---

# Talos

Declarative [Talos Linux](https://www.talos.dev) machine configuration, built
from composable multi-document patches (requires Talos 1.14 or later). Nothing
in [`kubernetes/talos/`](https://github.com/bykaj/home-ops/tree/main/kubernetes/talos)
is applied automatically. Configs are rendered on demand and pushed with
`talosctl`. Version upgrades are the exception: tuppr handles those (see
[Upgrades](../runbooks/upgrades.md)).

## Layout

| Path | Purpose |
| --- | --- |
| `cluster.yaml.j2` | Documents applied to every node |
| `controlplane.yaml.j2` | Control-plane-only documents, including `machine.type` |
| `workers.yaml.j2` | Worker-only documents (not created yet; added with the first worker) |
| `nodes/<role>/<node>.yaml.j2` | Per-node documents: hostname, NIC alias, bond, install disk, volumes |
| `nodes/<role>/<node>.schematic.yaml.j2` | Optional per-node schematic override |
| `schematic.yaml.j2` | Shared [Image Factory](https://factory.talos.dev) schematic |
| `version.yaml` | Pinned Talos and Kubernetes versions (updated by Renovate) |
| `mod.just` | `just talos …` recipes |

## What's in the config

Applied to every node from `cluster.yaml.j2`:

- DHCP on `bond0`, with the UDM as resolver
- Filesystem trim and scrub schedules, and a hardware watchdog
- Kernel modules for DRBD, `dm_thin_pool` and `nbd`
- Sysctl tuning: BBR with `fq`, large TCP buffers for QUIC, NFS RPC slot limits, raised inotify limits, IPv6 disabled
- `nfsmount.conf` with tuned NFS mount defaults
- Registry mirrors for `docker.io`, `ghcr.io`, `quay.io` and `registry.k8s.io`,
  pointing at the [Zot](../docker/index.md#06-zot) pull-through cache on the NAS
  (`registry.bykaj.app`), falling back to upstream
- KubePrism, and kubelet node IPs restricted to `10.73.20.0/24`

The shared schematic adds the Intel `i915`, `intel-ucode` and `mei` extensions
for iGPU transcoding, `nfsrahead`, and `drbd`. It also sets kernel arguments
that trade some hardening for performance (`mitigations=off`, no
`init_on_alloc`/`init_on_free`, auditd disabled).

## Rendering

`just talos render-config <node>` builds the final machine config in three
layers:

```sh
talosctl machineconfig patch <(cluster.yaml.j2) \
    -p @<(controlplane.yaml.j2 | workers.yaml.j2) \
    -p @<(nodes/<role>/<node>.yaml.j2)
```

Each layer passes through `minijinja-cli` (strict Jinja; the schematic ID
arrives as a `-D` define) and `op inject` (1Password) before `talosctl` merges
them. Later patches merge strategically into earlier ones: documents with the
same kind and name are deep-merged, and new documents are appended.

Two conventions keep the layers honest:

- **Directory placement is the single source of truth for a node's role.** The
  role patch is chosen by which `nodes/<role>/` directory holds the node file,
  and `machine.type` is set by the role patch, not by the node file.
- **Secrets never live in the repo.** Sensitive values are
  `op://Homelab/talos/...` references resolved at render time.

## Schematics

`just talos schematic-id` POSTs the schematic to the Image Factory and gets
back a content-addressed ID. That ID is templated into the
`UnattendedInstallConfig` installer image and used by `download-image` and
`upgrade-node`.

Resolution is per node: `nodes/<role>/<node>.schematic.yaml.j2` wins when
present, otherwise the shared `schematic.yaml.j2` applies. Overrides are
complete files, not deltas. None exist today.

## Gotchas

- `machine.ca` and `cluster.ca` merge as a cert+key **unit**: a patch that
  supplies only `key` blanks `crt`. That is why `controlplane.yaml.j2` repeats
  the `crt` references alongside the keys.
- Rendering a worker before `workers.yaml.j2` and `nodes/workers/` exist fails
  loudly. Adding the first worker means creating `workers.yaml.j2` (with
  `machine: { type: worker }` and a `ca` block carrying `crt` only) plus
  `nodes/workers/<node>.yaml.j2`.
- Kernel names for the two NVMe drives can swap across reboots. Disks are
  selected by model and links by MAC, so this is harmless, but match by model
  or serial when reading `talosctl` output.

## Common tasks

```sh
just talos render-config <node>        # render a node's full machine config to stdout
just talos apply-node <node>           # render and apply (talosctl apply-config)
just talos upgrade-node <node>         # upgrade Talos using the node's schematic image
just talos upgrade-k8s <version>       # upgrade Kubernetes across the cluster
just talos download-image <version>    # fetch a metal ISO from the Image Factory
just talos reboot-node <node>          # reboot (asks for confirmation)
```

Verify a template refactor by diffing rendered output before and after, then
confirming this reports "No changes." on every node:

```sh
just talos render-config <node> | talosctl -n <node> apply-config -f /dev/stdin --dry-run
```
