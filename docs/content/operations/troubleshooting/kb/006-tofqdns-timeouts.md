---
description: A Cilium toFQDNs egress rule silently drops traffic to a host it should allow
---

# KB-006: `toFQDNs` egress rule times out

## Symptom

After adding a `CiliumNetworkPolicy` with `toFQDNs: matchName: <host>`,
requests to that host hang until they time out. There is no connection reset,
and a DNS lookup from another pod looks fine.

## Cause

With CoreDNS `autopath`, a pod's first search-path query
(`<host>.<namespace>.svc.cluster.local`) gets back a CNAME to the real host.
Cilium's FQDN cache then ties the IPs to that query name instead of `<host>`,
so `matchName: <host>` never matches.

`autopath` was removed from CoreDNS for this reason
([#2993](https://github.com/bykaj/home-ops/pull/2993)). Don't add it back.
Without it, pods walk their search domains themselves (`ndots:5`), and CoreDNS
answers those lookups with NXDOMAIN from its own zone and caches them.

## Fix

Check which name the IPs are tied to, in the `cilium-agent` on the pod's node:

```sh
kubectl -n kube-system exec <cilium-pod> -c cilium-agent -- cilium-dbg fqdn cache list
```

Hubble shows the dropped flows with pod and destination names, from inside the
agent on the pod's node:

```bash
kubectl -n kube-system exec <cilium-pod> -c cilium-agent -- hubble observe --verdict DROPPED --last 50
```

After merging an egress policy, send a real request through it. A server-side
dry run doesn't test this.

## Seen

2026-10-21: the LiteLLM egress policy
([#2992](https://github.com/bykaj/home-ops/pull/2992)) blocked every request
to the model provider until it was patched live.
