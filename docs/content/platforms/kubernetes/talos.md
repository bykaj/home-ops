---
description: Talos machine configuration, schematics and node operations
---

# Talos

Declarative [Talos Linux](https://www.talos.dev) machine configuration, built
from composable multi-document patches (requires Talos 1.14 or later). Nothing
in [`kubernetes/talos/`](https://github.com/bykaj/home-ops/tree/main/kubernetes/talos)
is applied automatically. Configs are rendered on demand and pushed with
`talosctl`. Version upgrades are the exception: tuppr handles those (see
[Upgrades](../../operations/runbooks/upgrades.md)).

## Layout

| Path | Purpose |
| --- | --- |
| `cluster.yaml.j2` | Documents applied to every node |
| `controlplane.yaml.j2` | Control-plane-only documents, including `machine.type` |
| `workers.yaml.j2` | Worker-only documents (not created yet; added with the first worker) |
| `nodes/<role>/<node>.yaml.j2` | Per-node documents: hostname, NIC alias, bond, install disk, volumes |
| `nodes/<role>/<node>.schematic.yaml.j2` | Optional per-node schematic override |
| `schematic.yaml.j2` | Shared [Image Factory](https://factory.talos.dev) schematic |
| `secrets.yaml.j2` | Talos secrets bundle as `op://` references, used to generate `talosconfig` |
| `version.yaml` | Pinned Talos and Kubernetes versions (updated by Renovate) |
| `mod.just` | `just talos …` recipes |

## What's in the config

Applied to every node from `cluster.yaml.j2`:

- DHCP on `bond0`, with the UDM as resolver
- Filesystem trim and scrub schedules, and a hardware watchdog
- Kernel modules for DRBD, `dm_thin_pool` and `nbd`
- Sysctl tuning: BBR with `fq`, large TCP buffers for QUIC, NFS RPC slot limits, raised inotify limits, IPv6 disabled
- `nfsmount.conf` with tuned NFS mount defaults (including `noresvport`, so
  reconnects can use any source port), and an `nfs.conf` that sets the
  `nfsrahead` read-ahead to 16 MiB for NFSv4 mounts
- Registry mirrors for `docker.io`, `ghcr.io`, `quay.io` and `registry.k8s.io`,
  pointing at the [Zot](../docker.md#07-zot) pull-through cache on the NAS
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

## Client configs

Both client configs at the repo root carry a client certificate that expires
after a year. The recipes below renew them and store the result, with its
expiry date, in 1Password (see
[Bootstrap → Client configs](../../operations/runbooks/bootstrap.md#client-configs)).

### talosconfig

`just talos gen-talosconfig` generates the repo-root `talosconfig` from the
cluster's secrets in 1Password, so it works before the cluster exists and
does not need a still-valid client certificate:

1. `secrets.yaml.j2` is rendered through `op inject` into a Talos secrets
   bundle, built from the same `op://Homelab/talos/...` fields the machine
   configs use. It is only ever passed to `talosctl` through a pipe, never
   written to disk.
2. `talosctl gen config --output-types talosconfig` signs a new `os:admin`
   client certificate with the machine CA. It is valid for one year.
3. Node names come from the `nodes/<role>/<node>.yaml.j2` files, skipping
   `<node>.schematic.yaml.j2` overrides. Endpoints are set to the
   control-plane nodes, and nodes to every node of any role.
4. The certificate is checked against the first control-plane node. If that
   fails (for example, nodes still in maintenance mode), it asks before
   keeping the file.
5. The file replaces `./talosconfig` (mode `0600`) and is uploaded to
   1Password with `just bootstrap store-configs talosconfig`, which also works
   on a new cluster that has no `kubeconfig` yet.

Run it for a brand-new cluster, and before the client certificate expires
(`talosctl config info` shows the date). If you keep a copy in
`~/.talos/config`, update that too.

### kubeconfig

`just talos gen-kubeconfig` fetches a kubeconfig with a new admin client
certificate from the first control-plane endpoint (`talosctl kubeconfig`,
context `admin@main`), checks it against the API server's `/livez`
(asking before keeping it if that fails), replaces `./kubeconfig` (mode
`0600`) and runs `just bootstrap store-configs kubeconfig`. It needs a working
`talosconfig`. `just bootstrap cluster` fetches its own kubeconfig, so this is
for renewals.

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
- Applying a change to `KubeAPIServerConfig` or `KubeControllerManagerConfig`
  restarts those static pods even though the dry run says "without a reboot".
  All three nodes are control planes, so apply one node at a time and wait for
  `kubectl get --raw /readyz` before the next, or the API goes down.
- etcd's database file never shrinks on its own, and Talos doesn't defragment
  it. The [`etcd-defrag`](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/kube-system/etcd-defrag)
  CronJob runs every Sunday at 04:00 and defragments members with more than
  100 MiB free, one at a time, moving the leader first. To do it by hand: run
  `talosctl -n <node> etcd defrag` on the followers, then
  `talosctl -n <leader> etcd forfeit-leadership` and defrag the old leader.
- Kernel names for the two NVMe drives can swap across reboots. Disks are
  selected by model and links by MAC, so this is harmless, but match by model
  or serial when reading `talosctl` output.
- Node IPs are UniFi DHCP reservations on `bond0`'s MAC, which is the MAC of
  the `net0` link. Moving `net0` to another NIC changes the MAC, and UniFi
  refuses to move the reservation while the old NIC is still online with that
  IP. Intel onboard NICs stay online while the node is powered off. To switch
  NICs with the same IP: stage the new `net0` selector with
  `just talos apply-node <node> --mode=staged`, shut the node down, unplug the
  old NIC, forget its client in UniFi, set the fixed IP and local DNS record on
  the new NIC's MAC, then power the node on.

## Common tasks

```sh
just talos apply-node <node>           # render and apply (talosctl apply-config)
just talos download-image <version>    # fetch a metal ISO from the Image Factory
just talos gen-kubeconfig              # new kubeconfig (new client cert), stored in 1Password
just talos gen-talosconfig             # new talosconfig from 1Password, stored back in 1Password
just talos reboot-node <node>          # reboot (asks for confirmation)
just talos render-config <node>        # render a node's full machine config to stdout
just talos upgrade-k8s <version>       # upgrade Kubernetes across the cluster
just talos upgrade-node <node>         # upgrade Talos using the node's schematic image
```

Verify a template refactor by diffing rendered output before and after, then
confirming this reports "No changes." on every node:

```sh
just talos render-config <node> | talosctl -n <node> apply-config -f /dev/stdin --dry-run
```
