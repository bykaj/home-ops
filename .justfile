#!/usr/bin/env -S just --justfile

set minimum-version := '1.55.0'

set default-list
set default-script
set lazy
set quiet
set script-interpreter := ['bash', '-euo', 'pipefail']
set shell := ['bash', '-euo', 'pipefail', '-c']

# Bootstrap workstation, cluster and NAS recipes
[group('bootstrap')]
mod bootstrap "bootstrap"

[doc('Serve the docs site locally with live reload')]
[group('docs')]
docs:
    zensical serve

[doc('Regenerate the app tables in the docs (--check to verify only)')]
[group('docs')]
docs-apps *args:
    uv run --script scripts/docs-applications.py {{ args }}

# Specific Docker recipes
[group('docker')]
mod docker "docker"

# Specific Kubernetes recipes
[group('k8s')]
mod k8s "kubernetes"

# Specific Talos recipes
[group('talos')]
mod talos "kubernetes/talos"

[private]
log lvl msg *args:
    gum log -t rfc3339 -s -l "{{ lvl }}" "{{ msg }}" {{ args }}

[private]
template file *args:
    minijinja-cli "{{ file }}" {{ args }} | op inject
