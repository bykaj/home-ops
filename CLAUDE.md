# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

@AGENTS.md

## Repository overview

This is a personal home infrastructure monorepo, not an application. It manages a bare-metal Talos/Kubernetes cluster (GitOps via Flux), Docker Compose stacks on a TrueNAS host (GitOps via doco-cd), and the Ansible/Talos/just tooling used to bootstrap and operate all of it. There is no app to build or test in the traditional sense — "correctness" means manifests render and lint cleanly; validation happens via `kustomize build`, `yamllint`, `kubeconform`, `actionlint`, `zizmor`, and `shellcheck`, mostly wired into pre-commit hooks.

Tool versions are pinned via mise (`.mise/config.toml`); `mise install` provisions `just`, `flux2`, `kubectl`, `kustomize`, `helm`, `helmfile`, `talosctl`, `1password-cli`, `yq`, etc. `mise`'s `postinstall` hook runs `lefthook install`.

## Commands

`just` (from `.justfile`) is the command runner; it imports modules as `mod`s, so most recipes are namespaced:

```bash
just                          # list all recipes/groups
just k8s <recipe>              # kubernetes/mod.just — day-2 cluster operations
just talos <recipe>             # kubernetes/talos/mod.just — Talos node operations
just bootstrap <recipe>         # bootstrap/mod.just — end-to-end bring-up
just docker <recipe>             # docker/mod.just — NAS doco-cd operations
```

Frequently used `just k8s` recipes: `sync ks|hr|gitrepo|ocirepo|es` (force Flux/ExternalSecrets reconciliation), `sync-hr`/`sync-ks`/`sync-es <ns> <name>` (single resource), `apply-ks`/`delete-ks <ns> <ks>` (render+apply/delete a Flux Kustomization locally via `flate`), `toolbox` (shell into rook-ceph-tools), `view-secret <ns> <secret>`, `browse-pvc <ns> <claim>`, `debug-node <node>`, `db-backup <ns> <app>` (manual CNPG backup), `prune-pods`.

`just bootstrap cluster` runs the full sequence: apply Talos config to nodes → bootstrap Kubernetes → fetch kubeconfig → apply base manifests/CRDs (kustomize + helmfile) → sync apps helmfile → fetch kubeconfig again. `just bootstrap nas` runs the Ansible playbook that bootstraps TrueNAS. `just docker reconcile-nas` restarts doco-cd on the NAS via Ansible.

### Validating a single Kubernetes app

```bash
kustomize build kubernetes/apps/<namespace>/<app>/app     # must render (${APP}-style vars staying literal is expected)
yamllint --config-file .yamllint.yaml kubernetes/apps/<namespace>/<app>
```

### Validating a single Docker Compose stack

```bash
docker compose -f docker/nas/NN-<app>/docker-compose.yaml config --quiet   # unset ${VAR} warnings are expected
```

### Pre-commit hooks (lefthook, `.lefthook.toml`)

Run automatically on `git commit`, staged-file-scoped: `gofmt`/`cargo fmt` for Go/Rust, `just --fmt` for justfiles, `mise fmt`, `oxfmt` for JSON/Markdown/YAML (`*.sops.yaml` excluded), `mise lock` (regenerates lockfiles for `linux-x64,linux-arm64,macos-x64,macos-arm64,windows-x64`), `actionlint` and `zizmor` for GitHub Actions workflows/actions, `shellcheck` for `*.sh`.

## Architecture

### `kubernetes/` — Flux-managed cluster state

Flux's top-level `Kustomization` (`kubernetes/clusters/main/apps.yaml`, name `cluster-apps`) points at `./kubernetes/apps` and recurses: it finds the top-most `kustomization.yaml` in each app directory and applies everything it references. `cluster-apps` also injects cluster-wide defaults via Kustomize patches onto _every_ Kustomization/HelmRelease it manages — default `retryInterval`/`timeout`, HelmRelease install/upgrade `CreateReplace`/`RetryOnFailure`/`RemediateOnFailure` strategy — so individual apps don't repeat that boilerplate (see the "common mistakes" notes in the add-app skill about not adding `wait`, `commonMetadata`, `timeout`). It also has a label-driven patch: a Flux Kustomization tagged `components.postgres/cnpg=init` gets its CNPG `Cluster` rewritten to a plain `initdb` bootstrap instead of Barman recovery, for brand-new databases with no prior backup.

Each app lives at `kubernetes/apps/<namespace>/<app>/`:

```text
<app>/
├── ks.yaml                # Flux Kustomization — path, targetNamespace, dependsOn, optional kopiur backup component
└── app/
    ├── kustomization.yaml
    ├── ocirepository.yaml     # pins the app-template chart version (oci://ghcr.io/bjw-s-labs/helm/app-template)
    ├── helmrelease.yaml       # values: controllers/service/route/persistence, built on bjw-s-labs/app-template
    ├── externalsecret.yaml    # optional — pulls 1Password fields via the onepassword-connect ClusterSecretStore
    └── resources/              # optional — files wired in via configMapGenerator
```

`kubernetes/components/` holds reusable kustomize components consumed by apps via `postBuild.substitute` (e.g. `kopiur/backup` for PVC backups, `kopiur/secret`, `postgres` for CNPG clusters, `dragonfly`, `gpu`, `zeroscaler`, `alerts`). `kubernetes/talos/` holds Talos machine-config Jinja templates (rendered with `minijinja-cli` + 1Password `op inject`, see `.justfile`'s `template` recipe) and `version.yaml` (pinned Talos/Kubernetes versions used by `kubernetes/talos/mod.just`).

Scaffolding a new cluster app should follow the `add-app` skill (`.agents/skills/add-app/SKILL.md`), which encodes current conventions (probes, resources, securityContext, route/persistence/secret blocks) — mirror a recent real app (it names good references) rather than inventing structure.

### `docker/` — Compose stacks on non-Kubernetes hosts

Deployed GitOps-style by [doco-cd](https://github.com/kimdre/doco-cd), which polls this repo's `main` hourly and auto-discovers one-directory-deep stacks under `docker/<host>/`. Each stack is `docker/<host>/NN-<app>/docker-compose.yaml`; the `NN-` prefix is ordering only — renaming/renumbering a directory triggers delete+recreate of the stack (including anonymous volumes), so it's kept stable. Currently the only deployed host is `nas` (TrueNAS); its doco-cd config (`docker/nas/.doco-cd/docker-compose.app.yaml`) polls `bykaj/home-ops` `main` and injects secrets from 1Password. Compose-level secrets are declared under `external_secrets` in `docker/<host>/.doco-cd.yaml` as `op://<vault>/<item>/<field>` references and consumed as `${VAR_NAME}` in the compose file. New apps should follow the `add-docker-app` skill (`.agents/skills/add-docker-app/SKILL.md`) for host-specific proxy/network/secret conventions.

### `bootstrap/` and `ansible/` — initial provisioning

`bootstrap/mod.just` orchestrates cluster bring-up end to end (Talos config → K8s bootstrap → kubeconfig → base CRDs/manifests → apps via helmfile) and NAS bootstrap (Ansible playbook using `ansible/inventory.yaml`). `bootstrap/README.md` documents the manual bootstrap process this automates.

### `.agents/` — shared agent conventions

`AGENTS.md` imports `.agents/instructions/sorting.instructions.md`, which defines the repo-wide YAML key-ordering rules (alphabetical by default, with specific overrides for `apiVersion`/`kind`/`metadata`/`spec`, `metadata.*`, and — in detail — app-template-based `HelmRelease` value blocks). These rules apply whenever YAML in this repo is written or reordered. `.agents/skills/` holds the `add-app` and `add-docker-app` skills described above; they're exposed to Claude Code through the `.claude/skills` symlink.

### GitOps flow

Renovate watches the entire repository for dependency updates (chart versions, image tags, Talos/K8s versions, tool versions in `.mise/config.toml`, GitHub Actions, etc.) and opens PRs (`.renovaterc.json5`, extends `home-operations/renovate-presets`). Merging a PR to `main` is what actually changes cluster/NAS state: Flux reconciles `kubernetes/apps` on its own interval, and doco-cd polls and redeploys `docker/nas` stacks hourly. There is no separate "deploy" step — pushing to `main` is the deploy.

### Secrets

Runtime secrets never live in Git. In Kubernetes, External Secrets Operator + 1Password Connect (`ClusterSecretStore: onepassword-connect`) inject them as Kubernetes Secrets from `ExternalSecret` resources. In Docker Compose land, doco-cd resolves `op://` references declared in `docker/<host>/.doco-cd.yaml` at deploy time. `op` (1Password CLI) is also used locally for `just template`/bootstrap flows via `op inject`.
