---
description: Renovate's artifacts check fails on a mise tool that uses a plugin backend
---

# KB-014: Renovate fails to update the mise lockfile

## Symptom

A Renovate PR that bumps a tool in `.mise/config.toml` fails the
`renovate/artifacts` check with:

```text
installing plugins is disabled in safe mode
```

## Cause

Renovate runs `mise lock` with `MISE_SAFE=1` on a fresh runner. Safe mode
refuses to install plugins, so any tool on a vfox or asdf backend fails. A
local `MISE_SAFE=1 mise lock` passes when the plugin is already installed, so
it doesn't reproduce the failure.

## Fix

Move the tool to an `aqua:` or `github:` backend. Renovate names the
dependency after the config key (for example `aqua:1password/cli`), so update
any `matchDepNames` rule to match.

Test like Renovate does, with empty data and cache directories:

```sh
MISE_SAFE=1 MISE_DATA_DIR="$(mktemp -d)" MISE_CACHE_DIR="$(mktemp -d)" mise lock
```

## Seen

2026-10-24: the 1Password CLI bump
([#3049](https://github.com/bykaj/home-ops/pull/3049), fixed in
[#3050](https://github.com/bykaj/home-ops/pull/3050)).
