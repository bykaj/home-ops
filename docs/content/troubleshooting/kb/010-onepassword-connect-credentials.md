---
description: 1Password Connect can't read its credentials file, which also takes ESO down
---

# KB-010: 1Password Connect can't parse its credentials

## Symptom

1Password Connect fails with:

```text
failed to Unmarshal credentials file data into map
```

ExternalSecrets everywhere stop syncing, including the one that manages
Connect's own credentials.

## Cause

The Connect chart mounts key `1password-credentials.json` of Secret
`onepassword-secret` as a file, and the file must contain raw JSON. The
1Password field holds the JSON **base64-encoded**, so the ExternalSecret
decodes it with `b64dec` and the bootstrap Secret puts it under `data:`, not
`stringData:`.

External Secrets fetches through Connect, so once Connect's credentials are
broken, it can't repair them either: a deadlock.

## Fix

Re-apply the bootstrap Secret to break the deadlock, the same way
`just bootstrap` does (`just template` resolves the `op://` reference):

```sh
kustomize build bootstrap/kubernetes/kustomize/manifests/external-secrets \
  | just template - | kubectl apply --server-side --force-conflicts -f -
```

Before changing how Connect reads its credentials (key name, format), pre-seed
the new key on the live Secret with a separate field manager
(`kubectl apply --server-side --field-manager=<name>`), and release that field
manager after the merge by applying an empty object with the same manager.

## Seen

2026-10-24, when Connect moved to the official chart
([#3046](https://github.com/bykaj/home-ops/pull/3046),
[#3047](https://github.com/bykaj/home-ops/pull/3047)).
