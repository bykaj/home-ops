---
description: CephNodeNetworkPacketDrops fires because the X520 RX ring overflows
---

# KB-018: Packet drop alerts from NIC RX ring overflows

## Symptom

`CephNodeNetworkPacketDrops` fires for a Kubernetes node on `bond0` and
`enp1s0f0`, then resolves within minutes. The rule has no `for:` and uses a
1-minute rate, so a single burst of 10 or more drops per second fires it.

## Cause

The X520 ports (`ixgbe`) drop frames when their RX ring is full. `ethtool -S
enp1s0f0` shows every drop as `rx_missed_errors`, while `rx_dropped`,
`rx_no_dma_resources` and the softnet drop counters stay at zero. The ring
was at the 512-slot default, out of a hardware maximum of 8192, which is too
small for short traffic bursts.

## Fix

Each node's `nodes/<role>/<node>.yaml.j2` raises the ring on its X520 port
with an `EthernetConfig` document:

```yaml
apiVersion: v1alpha1
kind: EthernetConfig
name: enp1s0f0
rings:
  rx: 4096
```

It applies without a reboot, but resizing the ring resets the NIC, so the
node briefly loses its network. Apply it one node at a time and wait for Ceph
to be healthy between nodes. To check the counters on a node, start a debug
pod with `ethtool`:

```bash
kubectl debug node/<node> -n default --profile=sysadmin \
  --image=docker.io/nicolaka/netshoot:latest -- sleep 300
kubectl -n default exec <pod> -- ethtool -S enp1s0f0 | grep -E 'missed|dropped'
kubectl -n default exec <pod> -- ethtool -g enp1s0f0
```

Delete the debug pod by its exact name afterwards.

## Seen

2026-10-28: k8s-02 dropped about 30,000 frames in one minute at 09:11 UTC and
23,000 at 12:11 UTC, which fired the alert twice. Since boot, the nodes had
missed 2.6 million (k8s-01), 541,000 (k8s-02) and 51,000 (k8s-03) frames.
