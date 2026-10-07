---
description: How Cilium and the NAS announce VIPs to the UDM over BGP, with ECMP
---

# BGP & Load Balancing

Every LoadBalancer IP in the cluster, including the Kubernetes API, is
announced to the UniFi UDM over BGP. The NAS announces its own address the
same way, using FRR in a container.

```mermaid
graph LR
    client(Client) -->|hashed flow| udm("`**UDM**
    _ASN 64513_`")
    udm -->|ECMP| k1("`**k8s-01**
    10.73.20.10`")
    udm -->|ECMP| k2("`**k8s-02**
    10.73.20.20`")
    udm -->|ECMP| k3("`**k8s-03**
    10.73.20.30`")
    udm -->|ECMP| nas("`**nas**
    10.73.1.10`")
    k1 & k2 & k3 -. "`**BGP** _ASN 64514_
    VIPs from 10.73.20.0/24`" .-> udm
    nas -. "`**BGP** _ASN 64515_
    VIP 10.73.1.10/32`" .-> udm
    client@{ shape: browser}
    nas@{ shape: lin-cyl }
```

| ASN | Speaker | Announces |
| --- | --- | --- |
| 64513 | UDM Pro Max | (peer) |
| 64514 | Cilium on each node | LoadBalancer IPs from `10.73.20.0/24` |
| 64515 | FRR on the NAS ([`docker/nas/01-frr`](https://github.com/bykaj/home-ops/tree/main/docker/nas/01-frr)) | `10.73.1.10/32` |

The Cilium side is configured in
[`kubernetes/apps/kube-system/cilium/config/`](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/kube-system/cilium/config)
(`CiliumBGPClusterConfig`, `CiliumBGPPeerConfig`, `CiliumBGPAdvertisement`).

## Kubernetes API VIP

The Kubernetes API is fronted by the Cilium LoadBalancer Service `kube-api`
(`10.73.20.100`) with `externalTrafficPolicy: Local`, so only nodes with a
healthy apiserver announce the route. Static DNS in UniFi points
`k8s.internal` at it.

!!! note "When the CNI is down"

    `k8s.internal` depends on Cilium being healthy. If it isn't, reach the
    API directly at `https://10.73.20.{10,20,30}:6443`, and the Talos API at the
    same node addresses. Neither depends on the CNI. Bootstrap uses the node IP
    for the same reason.

## UDM FRR config

UniFi accepts one FRR config upload per device (Settings → Routing Table →
BGP):

```text
router bgp 64513
  bgp router-id 10.73.0.254
  no bgp ebgp-requires-policy

  neighbor k8s peer-group
  neighbor k8s remote-as 64514

  neighbor 10.73.20.10 peer-group k8s
  neighbor 10.73.20.20 peer-group k8s
  neighbor 10.73.20.30 peer-group k8s

  neighbor nas peer-group
  neighbor nas remote-as 64515

  neighbor 10.73.1.10 peer-group nas

  address-family ipv4 unicast
    maximum-paths 3
    neighbor k8s next-hop-self
    neighbor k8s soft-reconfiguration inbound
    neighbor nas next-hop-self
    neighbor nas soft-reconfiguration inbound
  exit-address-family
exit
```

`maximum-paths 3` enables true ECMP across the three nodes. FRR's eBGP default
is a single best path.

!!! warning

    Re-uploading the FRR config briefly bounces established BGP sessions.

## ECMP flow hashing

The kernel default (`fib_multipath_hash_policy=0`) hashes on source and
destination IP only, so a given client always lands on the same node. Policy
`1` adds ports to the hash and spreads individual connections across the ECMP
next-hops. This is persisted with a [UDM boot script](udm-boot-scripts.md#ecmp-flow-hashing).

## Verifying

On the UDM:

```sh
vtysh -c "show bgp summary"            # all sessions Established
vtysh -c "show ip bgp 10.73.20.100"    # every path tagged "multipath"
vtysh -c "show ip route"               # 10.73.20.100/32 with one path per healthy apiserver
ip route show 10.73.20.100             # one "nexthop" line per node
```

A single flat line in `ip route` means multipath is not installed in the
kernel.

To check that flows are spread, run this a few times from one machine and
expect the node name in the certificate SAN to vary:

```sh
openssl s_client -connect k8s.internal:6443 </dev/null 2>/dev/null \
  | openssl x509 -noout -ext subjectAltName
```

From a workstation: `curl -k https://k8s.internal:6443/livez`.
