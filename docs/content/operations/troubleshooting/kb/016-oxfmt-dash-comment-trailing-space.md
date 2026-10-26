---
description: The pre-commit formatter leaves a trailing space after a list dash
---

# KB-016: yamllint fails on a trailing space after `- `

## Symptom

yamllint reports `trailing-spaces` on a line that is just `- `. Removing the
space doesn't help, because the pre-commit hook adds it back.

## Cause

oxfmt keeps a comment on the `- ` line only when there is one comment line.
With two or more comment lines after the dash, it moves them all to their own
lines and leaves `- ` with a trailing space.

## Fix

Use a one-line `- # comment`, or put a multi-line comment above the `-` line.

## Seen

2026-10-04: the CNPG `initdb` patch in `kubernetes/clusters/main/apps.yaml`
([#2711](https://github.com/bykaj/home-ops/pull/2711)).
