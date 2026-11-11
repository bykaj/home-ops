---
description: A minimumReleaseAge rule silently blocks every update for images without Docker Hub timestamps
---

# KB-015: Renovate never updates an image with a release-age rule

## Symptom

An image covered by a `minimumReleaseAge` rule in `.renovaterc.json5` never
gets an update PR, and nothing in Renovate's PR list says why.

## Cause

Renovate's Docker datasource only gets release timestamps from Docker Hub.
ghcr.io, quay.io and other registries return none, and since Renovate 42
`minimumReleaseAgeBehaviour` defaults to `timestamp-required`, so the update
is held indefinitely. The dashboard issue lists it under "Pending Status
Checks".

Docker Hub images can hit this too: Docker Hub only pages through the first
1,000 tags of a repository for anonymous requests and answers `403 pagination
offset too large for anonymous requests` after that. Renovate then falls back
to the registry tag list, which has no timestamps. The Renovate workflow signs
in with a read-only Docker Hub access token (`op://Automation/docker-hub`) to
avoid this. The tags API doesn't accept that token directly, so the workflow
first exchanges it for a 15-minute JWT at `hub.docker.com/v2/auth/token`. If
the access token expires, that step fails and so does the Renovate run.

## Fix

Before adding a release-age rule, check that the image comes from Docker Hub.
If upstream publishes it there too, switch the image (compare digests first).
Otherwise, set `minimumReleaseAgeBehaviour: "timestamp-optional"` on the rule;
updates then go through without the age check.

To confirm the cause, look in the Renovate run log (debug level) for
`Marking N release(s) as pending, as they do not have a releaseTimestamp`. A
403 from `hub.docker.com` right before it means the Docker Hub token is
missing or expired.

## Seen

2026-10-21: LiteLLM was switched to its Docker Hub image so the release-age
rule could work ([#2992](https://github.com/bykaj/home-ops/pull/2992)).

2026-11-02: LiteLLM (about 2,300 tags on Docker Hub) had been held since
#2992 because of the anonymous pagination limit; fixed by signing Renovate in
to Docker Hub.
