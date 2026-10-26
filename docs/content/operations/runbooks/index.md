---
description: Repeatable operational procedures
icon: material/book-open-variant
---

# Runbooks

Step-by-step procedures for recurring and disaster-recovery operations.

- [Bootstrap](bootstrap.md): bring the cluster or the NAS up from scratch
- [Upgrades](upgrades.md): Talos and Kubernetes upgrades with tuppr, or by hand
- [Health Check](health-check.md): checks to run after an upgrade or a risky change
- [New Database](new-database.md): first deploy of an app with a brand-new CNPG cluster
- [Adding an App](adding-an-app.md): scaffold a new cluster app
- [Retiring an App](retiring-an-app.md): remove an app or a domain, and clean up what stays behind
- [Adding a Domain](adding-a-domain.md): serve a new domain with DNS, routing and a wildcard certificate

!!! tip "Prerequisites for every runbook"

    - `mise install` has been run, so every tool is on the pinned version.
    - `op` is signed in.
    - `talosconfig` and `kubeconfig` are at the repo root. mise sets
      `TALOSCONFIG` and `KUBECONFIG` to point at them. On a new machine,
      `just bootstrap restore-configs` restores both from 1Password.
