---
description: A minimumReleaseAge rule silently blocks every update for images outside Docker Hub
---

# KB-015: Renovate never updates an image with a release-age rule

## Symptom

An image covered by a `minimumReleaseAge` rule in `.renovaterc.json5` never
gets an update PR, and nothing in Renovate's PR list says why.

## Cause

Renovate's Docker datasource only gets release timestamps from Docker Hub.
ghcr.io, quay.io and other registries return none, and since Renovate 42
`minimumReleaseAgeBehaviour` defaults to `timestamp-required`, so the update
is held indefinitely.

## Fix

Before adding a release-age rule, check that the image comes from Docker Hub.
If upstream publishes it there too, switch the image (compare digests first).
Otherwise, set `minimumReleaseAgeBehaviour: "timestamp-optional"` on the rule;
updates then go through without the age check.

## Seen

2026-10-21: LiteLLM was switched to its Docker Hub image so the release-age
rule could work ([#2992](https://github.com/bykaj/home-ops/pull/2992)).
