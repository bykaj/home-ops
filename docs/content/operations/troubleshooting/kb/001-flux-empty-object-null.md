---
description: Flux sends an empty object as null, so object-typed CRD fields fail
---

# KB-001: Flux applies `{}` as `null`

## Symptom

A Flux Kustomization fails its dry run with an error like:

```text
spec.appConnector in body must be of type object: "null"
```

A local `kustomize build | kubectl apply --dry-run=server -f -` of the same
files passes.

## Cause

Flux turns a field written as `{}` (an empty map) into `null` before it sends
the object. `kubectl` keeps the `{}`, so a plain kubectl dry run doesn't
reproduce the error.

## Fix

Don't rely on `{}` for object-typed CRD fields. Give the field at least one
key, or leave it out if the CRD allows that. To check what Flux will actually
send, build through Flux and dry-run that:

```sh
flux build ks <name> --path <path> --kustomization-file <ks.yaml> --dry-run \
  | kubectl apply --dry-run=server -f -
```

## Seen

2026-10-19: `appConnector: {}` on a Tailscale `Connector`
([#2930](https://github.com/bykaj/home-ops/pull/2930)).
