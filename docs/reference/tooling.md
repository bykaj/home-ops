---
description: Pinned tooling, pre-commit hooks, CI workflows and local validation
---

# Tooling & Validation

This is an infrastructure repository, not an application. "Correct" means the
manifests render and lint cleanly.

## mise

[mise](https://mise.jdx.dev) pins every tool in
[`.mise/config.toml`](https://github.com/bykaj/home-ops/blob/main/.mise/config.toml)
(`just`, `flux2`, `kubectl`, `kustomize`, `helm`, `helmfile`, `talos`,
`1password-cli`, `yq`, `flate`, `minijinja`, `zensical`, and more) and sets
the environment:

| Variable | Points at |
| --- | --- |
| `KUBECONFIG` | `./kubeconfig` |
| `TALOSCONFIG` | `./talosconfig` |
| `FLATE_PATH` | `./kubernetes/clusters/main` |
| `MINIJINJA_CONFIG_FILE` | `./.minijinja.toml` |

`mise install` provisions everything. Its `postinstall` hook runs
`lefthook install` and installs the Ansible Galaxy requirements.

## Pre-commit hooks

[lefthook](https://lefthook.dev) runs these on staged files at commit time
([`.lefthook.toml`](https://github.com/bykaj/home-ops/blob/main/.lefthook.toml)):

| Hook | Files |
| --- | --- |
| `oxfmt` | JSON, Markdown, YAML (not `*.sops.yaml`) |
| `just --fmt` | Justfiles |
| `mise fmt`, `mise lock` | mise config and lockfile |
| `actionlint`, `zizmor` | GitHub Actions workflows and actions |
| `shellcheck` | `*.sh` |
| `just docs-apps --check` | `kubernetes/apps/**`: the [Applications](../kubernetes/applications.md) page is up to date |
| `gofmt`, `cargo fmt` | Go, Rust |

## Validating by hand

```sh
# A Kubernetes app
kustomize build kubernetes/apps/<namespace>/<app>/app
yamllint --config-file .yamllint.yaml kubernetes/apps/<namespace>/<app>

# A Docker stack
docker compose -f docker/nas/NN-<app>/docker-compose.yaml config --quiet

# These docs
just docs                 # live preview on http://localhost:8000
zensical build --strict   # what CI runs
```

## GitHub Actions

| Workflow | Does |
| --- | --- |
| `docs` | Builds this site on PRs, and deploys it to GitHub Pages on `main` |
| `renovate` | Runs Renovate hourly |
| `image-pull` | Pre-pulls images changed in a PR onto the nodes, so rollouts after merge don't wait on downloads |
| `labeler`, `label-sync` | PR labels by path, and label definitions from `.github/labels.yaml` |
| `tag` | Monthly release tag |

## Writing these docs

Pages live in [`docs/`](https://github.com/bykaj/home-ops/tree/main/docs). The
navigation is set explicitly in
[`zensical.toml`](https://github.com/bykaj/home-ops/blob/main/zensical.toml),
so add every new page there. [Zensical](https://zensical.org) supports
admonitions (`!!! note`), content tabs, Mermaid diagrams, code annotations and
grid cards. See the [authoring docs](https://zensical.org/docs/authoring/markdown/).
