---
description: Renamed or removed objects under flux-instance stay in the cluster
---

# KB-003: Old objects left behind in `flux-instance`

## Symptom

After renaming or removing an object under
`kubernetes/apps/flux-system/flux-instance/app` (an HTTPRoute, `Receiver`,
ExternalSecret, PrometheusRule, …), the old object is still in the cluster
next to the new one.

## Cause

The `flux-instance` Kustomization sets `prune: false`, so Flux can never
delete its own `FluxInstance`. The side effect is that nothing else in that
Kustomization is pruned either.

## Fix

Delete the old object by hand, by exact name, after the change is merged:

```sh
kubectl -n flux-system delete <kind> <old-name>
```

For any other Kustomization, check `spec.prune` before assuming Flux removed
something.

## Seen

2026-10-05: renaming the HTTPRoute `github-webhook` to `flux-webhook`
([#2735](https://github.com/bykaj/home-ops/pull/2735)) left the old route
behind.
