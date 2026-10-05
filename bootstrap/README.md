# Bootstrap

Takes freshly installed Talos nodes all the way to a self-managing Flux cluster, and provisions a
fresh TrueNAS server with the supporting applications it needs.

```sh
just bootstrap cluster   # Talos → Kubernetes → base CRDs/secrets → helmfile apps → Flux takes over
just bootstrap nas       # Ansible provisioning of TrueNAS, then doco-cd takes over
```

Documentation:

- [Bootstrap runbook](https://docs.bykaj.com/runbooks/bootstrap/): prerequisites, stages, data
  restore ([source](../docs/runbooks/bootstrap.md))
- [BGP & Load Balancing](https://docs.bykaj.com/networking/bgp/): the UDM FRR config the cluster
  needs ([source](../docs/networking/bgp.md))
- [DNS](https://docs.bykaj.com/networking/dns/): the manual UniFi records
  ([source](../docs/networking/dns.md))
- [UDM Boot Scripts](https://docs.bykaj.com/networking/udm-boot-scripts/): ECMP hashing and
  HTTP/3 records ([source](../docs/networking/udm-boot-scripts.md))
