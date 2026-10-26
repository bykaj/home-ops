---
description: A Gatus check on an envoy-external route can't resolve an internal hostname
---

# KB-017: Gatus check fails with `no such host`

## Symptom

A Gatus check for an HTTPRoute fails with an error like:

```text
lookup nas.internal on 10.43.0.10:53: no such host
```

## Cause

gatus-sidecar merges the parent Gateway's `gatus.home-operations.com/endpoint`
annotation into each route's check. The `envoy-external` Gateway sets
`client.dns-resolver: tcp://1.1.1.1:53`, so a route on it whose check `url`
points at an internal name is resolved publicly. Go prints the pod's
`resolv.conf` server in the error, even though it asked 1.1.1.1.

## Fix

For a public route, point the check at the public URL, so it tests the whole
path. If it must check an internal name, override the resolver on the route,
as `kubernetes/apps/database/meilisearch/app/gatus.yaml` does:

```yaml
client:
  dns-resolver: tcp://10.43.0.10:53
```

To inspect results, port-forward Gatus (`svc/gatus` in `observability`, port
8080) and query `/api/v1/endpoints/statuses`. The containers are distroless,
so `kubectl exec` doesn't work.

## Seen

2026-10-05: the doco-cd webhook route
([#2734](https://github.com/bykaj/home-ops/pull/2734)).
