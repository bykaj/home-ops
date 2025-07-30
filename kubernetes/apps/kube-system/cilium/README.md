# Cilium BGP

[Cilium](https://cilium.io/) is used as the CNI (Container Network Interface) for this Kubernetes cluster. This document contains configuration details for network integration.

**Status:** Not Implemented Yet

## UniFi Configuration
The following BGP configuration needs to be applied to the UniFi Gateway to establish BGP peering with Cilium in the Kubernetes cluster:
```sh
router bgp 64513
  bgp router-id 10.73.0.254
  no bgp ebgp-requires-policy

  neighbor k8s peer-group
  neighbor k8s remote-as 64514

  neighbor 10.73.10.110 peer-group k8s
  neighbor 10.73.10.111 peer-group k8s
  neighbor 10.73.10.112 peer-group k8s

  address-family ipv4 unicast
    neighbor k8s next-hop-self
    neighbor k8s soft-reconfiguration inbound
  exit-address-family
exit
```

This configuration establishes BGP peering between the UniFi Gateway (AS 64513) and the Kubernetes nodes (AS 64514), enabling dynamic route advertisement for Kubernetes services.

## Kubernetes Configuration
Add to [`networks.yaml`](https://github.com/bykaj/home-ops/blob/main/kubernetes/apps/kube-system/cilium/app/networks.yaml):
```yaml
---
# yaml-language-server: $schema=https://schemas.bykaj.io/cilium.io/ciliumbgpadvertisement_v2alpha1.json
apiVersion: cilium.io/v2alpha1
kind: CiliumBGPAdvertisement
metadata:
  name: l3-bgp-advertisement
  labels:
    advertise: bgp
spec:
  advertisements:
    - advertisementType: Service
      service:
        addresses: ["LoadBalancerIP"]
      selector:
        matchExpressions:
          - { key: somekey, operator: NotIn, values: ["never-used-value"] }
---
# yaml-language-server: $schema=https://schemas.bykaj.io/cilium.io/ciliumbgppeerconfig_v2alpha1.json
apiVersion: cilium.io/v2alpha1
kind: CiliumBGPPeerConfig
metadata:
  name: l3-bgp-peer-config
spec:
  families:
    - afi: ipv4
      safi: unicast
      advertisements:
        matchLabels:
          advertise: bgp
---
# yaml-language-server: $schema=https://schemas.bykaj.io/cilium.io/ciliumbgpclusterconfig_v2alpha1.json
apiVersion: cilium.io/v2alpha1
kind: CiliumBGPClusterConfig
metadata:
  name: l3-bgp-cluster-config
spec:
  nodeSelector:
    matchLabels:
      kubernetes.io/os: linux
  bgpInstances:
    - name: cilium
      localASN: 64514
      peers:
        - name: unifi
          peerASN: 64513
          peerAddress: 10.73.0.254
          peerConfigRef:
            name: l3-bgp-peer-config
```

Add/replace in [`values.yaml`](https://github.com/bykaj/home-ops/blob/main/kubernetes/apps/kube-system/cilium/app/helm/values.yaml):
```yaml
bpf:
  datapathMode: netkit
  masquerade: true
  preallocateMaps: true
bpfClockProbe: true
bgpControlPlane:
  enabled: true
# Only enable when running bare-metal
# devices: enp+
# enableIPv4BIGTCP: true
```