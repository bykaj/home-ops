---
description: Repeatable operational procedures
icon: material/book-open-variant
---

# Runbooks

Step-by-step procedures for recurring and disaster-recovery operations.

- [Bootstrap](bootstrap.md): bring the cluster or the NAS up from scratch
- [Upgrades](upgrades.md): Talos and Kubernetes upgrades with tuppr, or by hand
- [New Database](new-database.md): first deploy of an app with a brand-new CNPG cluster
- [Adding an App](adding-an-app.md): scaffold a new cluster app

!!! tip "Prerequisites for every runbook"

    - `mise install` has been run, so every tool is on the pinned version.
    - `op` is signed in.
    - `talosconfig` and `kubeconfig` are at the repo root. mise sets
      `TALOSCONFIG` and `KUBECONFIG` to point at them.
