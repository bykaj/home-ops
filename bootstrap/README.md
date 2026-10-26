# Bootstrap

Takes freshly installed Talos nodes all the way to a self-managing Flux cluster, and provisions a
fresh Docker host (such as the TrueNAS server) with the supporting applications it needs.

```sh
just bootstrap cluster           # Talos → Kubernetes → base CRDs/secrets → helmfile apps → Flux takes over
just bootstrap docker <host>     # Ansible provisioning of docker/<host>, then doco-cd takes over
just bootstrap restore-configs   # existing cluster: restore kubeconfig and talosconfig from 1Password
just bootstrap store-configs     # upload kubeconfig and talosconfig (and their expiry dates) to 1Password
```

Documentation:

- [Bootstrap runbook](https://docs.bykaj.com/operations/runbooks/bootstrap/): prerequisites, stages, data
  restore ([source](../docs/content/operations/runbooks/bootstrap.md))
- [BGP & Load Balancing](https://docs.bykaj.com/infrastructure/networking/bgp/): the UDM FRR config the cluster
  needs ([source](../docs/content/infrastructure/networking/bgp.md))
- [DNS](https://docs.bykaj.com/infrastructure/networking/dns/): the manual UniFi records
  ([source](../docs/content/infrastructure/networking/dns.md))
- [UDM Boot Scripts](https://docs.bykaj.com/infrastructure/networking/udm-boot-scripts/): ECMP hashing and
  HTTP/3 records ([source](../docs/content/infrastructure/networking/udm-boot-scripts.md))
