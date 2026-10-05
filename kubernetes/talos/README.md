# Talos

Declarative Talos Linux machine configuration for the cluster nodes, built from composable
multi-document patches and rendered on demand.

```sh
just talos render-config <node>   # render a node's full machine config
just talos apply-node <node>      # render and apply
```

See [Talos](https://docs.bykaj.com/kubernetes/talos/) ([source](../../docs/kubernetes/talos.md))
for the layout, rendering layers, schematics and gotchas, and
[Upgrades](https://docs.bykaj.com/runbooks/upgrades/) ([source](../../docs/runbooks/upgrades.md))
for Talos and Kubernetes upgrades.
