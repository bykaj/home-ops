---
description: Resuming a HelmRelease doesn't restore replicas that were scaled down by hand
---

# KB-004: Resumed HelmRelease stays scaled to zero

## Symptom

An app was suspended (`flux suspend hr`) and scaled to 0 by hand, for example
to contain a vulnerability. After `flux resume hr <name>` the Helm upgrade
succeeds and the pod spec has the new image, but the Deployment stays at
`0/0`.

## Cause

Helm only patches what changed between the old and the new chart output.
`replicas` didn't change there, so the manual scale-down survives the
upgrade.

## Fix

Scale it back yourself after resuming:

```sh
kubectl -n <namespace> scale deploy <name> --replicas=1
```

Check `kubectl get deploy` after resuming any release that was scaled down by
hand.

## Seen

2026-10-21: Wallos, after the patched image was merged
([#2989](https://github.com/bykaj/home-ops/pull/2989)).
