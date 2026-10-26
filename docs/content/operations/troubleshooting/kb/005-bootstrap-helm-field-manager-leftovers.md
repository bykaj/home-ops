---
description: Fields a newer chart stops rendering stay on objects first installed by bootstrap
---

# KB-005: Leftover fields on bootstrap-installed releases

## Symptom

A chart bump for a release that `just bootstrap` installs (Cilium, CoreDNS,
Spegel, …) removes a field, but the field is still on the live object.

## Cause

The bootstrap helmfile applied these objects with field manager `helm`. Once
Flux takes over, helm-controller applies as `helm-controller`, so fields it no
longer renders stay on the object, still owned by `helm`.

## Fix

Find the leftovers and remove them by hand:

```sh
kubectl -n <namespace> get <kind> <name> --show-managed-fields -o yaml
```

Look for fields under `manager: helm` that the current chart no longer
renders, then remove them, for example an annotation:

```sh
kubectl -n <namespace> annotate <kind> <name> <annotation-key>-
```

## Seen

2026-10-16: Spegel 0.8.0 dropped `service.kubernetes.io/topology-mode: auto`
from the `spegel-registry` Service, but the annotation stayed. It takes
precedence over `trafficDistribution: PreferSameNode`, so the EndpointSlices
got no hints and image pulls weren't served node-locally.
