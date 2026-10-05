# Cluster

Helmfiles and kustomize manifests used by `just bootstrap cluster`. Once Flux takes over, nothing
here is used again until the next rebuild.

```sh
just bootstrap cluster
```

See the [Bootstrap runbook](https://docs.bykaj.com/runbooks/bootstrap/#cluster)
([source](../../docs/runbooks/bootstrap.md)) for the stages, the helmfile single-source-of-truth
setup and how app data is restored.
