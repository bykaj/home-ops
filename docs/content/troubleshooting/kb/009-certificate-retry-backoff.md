---
description: A failed certificate waits an hour to retry, and deleting the request doesn't help
---

# KB-009: Certificate stuck after a failed issuance

## Symptom

A `Certificate` stays `Ready=False` after the cause is fixed. Deleting its
`CertificateRequest` creates a new one that doesn't progress. An order that
was stuck for days can fail with `404 No order for ID`.

## Cause

After a failed issuance, cert-manager waits about an hour before retrying
(`status.lastFailureTime` and `failedIssuanceAttempts` on the `Certificate`).
Deleting the `CertificateRequest` doesn't skip that wait. Separately, Let's
Encrypt drops the authorizations of an order that has been pending for days.

## Fix

Trigger a renewal, which skips the wait:

```sh
kubectl cert-manager renew -n <namespace> <certificate>
```

This needs the `kubectl` cert-manager plugin; `cmctl` does the same.

If the order failed with "no configured challenge solvers", check that the
domain is in the `dnsZones` selector of the `letsencrypt-production`
`ClusterIssuer`.

## Seen

2026-10-26: `bykaj.io` had dropped out of the issuer's `dnsZones`
([#3085](https://github.com/bykaj/home-ops/pull/3085)).
