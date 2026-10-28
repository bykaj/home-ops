---
description: An OCIRepository fails with DENIED because the charts mirror pruned the chart
---

# KB-019: Chart pull `DENIED` from the charts mirror

## Symptom

The `FluxOCIRepositoryOciartifactpullfailed` alert fires, and the
`OCIRepository` is not ready with:

```text
failed to determine artifact digest: GET https://ghcr.io/token?scope=repository%3Ahome-operations%2Fcharts-mirror%2F<chart>%3Apull&service=ghcr.io: DENIED: requested access to the resource is denied
```

The HelmRelease stays ready on the chart it already has, but can't be
upgraded.

## Cause

[home-operations/charts-mirror](https://github.com/home-operations/charts-mirror)
only republishes charts that have no official OCI release. Once upstream
publishes one, the mirror marks the chart deprecated and prunes it six months
later. The package is then gone, and ghcr.io answers `DENIED` instead of
`NOT_FOUND`.

## Fix

Find the deprecation commit in the mirror (`apps/<chart>/metadata.yaml`), then
the official OCI location in the upstream release workflow or README. Check
that it has the pinned tag, the same chart name and a Helm chart layer:

```bash
helm show chart oci://<registry>/<path>/<chart> --version <tag>
```

Switch the `url` in the app's `ocirepository.yaml` and keep the tag, so the
change is a source switch only. Renovate picks up newer versions from the new
location afterwards. With the same chart name, Flux upgrades the release in
place instead of reinstalling it.

To spot the next one early, check whether any chart still in use from the
mirror is deprecated:

```bash
grep -rho 'charts-mirror/[a-z0-9-]*' kubernetes | sort -u
```

## Seen

- 2026-10-16: Cilium, whose mirror copy stopped updating at 1.18.6 (no
  `DENIED` yet); moved to quay.io during the Cilium 1.20 upgrade.
- 2026-10-28: k8tz (deprecated 2026-03-07) and openebs (deprecated
  2025-11-22), moved to `ghcr.io/k8tz/k8tz/charts/k8tz` and
  `ghcr.io/openebs/charts/openebs`.
