---
description: A HelmRelease with no successful revision stalls and is skipped by a normal sync
---

# KB-002: HelmRelease stalled with `MissingRollbackTarget`

## Symptom

A HelmRelease shows `Stalled=True` with reason `MissingRollbackTarget`, and
`just k8s sync hr` doesn't change anything.

## Cause

The release's Helm history has no successful revision, typically because the
first install happened while something else was broken. When the next upgrade
fails, Flux has nothing to roll back to, so it stalls the release. A normal
reconcile skips stalled releases.

## Fix

Force a one-off upgrade with the same values:

```sh
flux -n <namespace> reconcile hr <name> --force
```

If the workload is healthy, this records a `deployed` revision and the release
behaves normally afterwards.

## Seen

2026-10-04: two apps that were first installed during the Ceph rebuild a few
days earlier.
