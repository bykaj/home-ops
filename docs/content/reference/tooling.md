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
| `just docs apps --check` | `kubernetes/apps/**`: the [Applications](../platforms/kubernetes/applications.md) page is up to date |
| `gofmt`, `cargo fmt` | Go, Rust |

## Validating by hand

```sh
# A Kubernetes app
kustomize build kubernetes/apps/<namespace>/<app>/app
yamllint --config-file .yamllint.yaml kubernetes/apps/<namespace>/<app>

# A Docker stack
docker compose -f docker/nas/NN-<app>/docker-compose.yaml config --quiet

# These docs
just docs build           # strict build, what CI runs
just docs serve           # live preview on http://localhost:8000
```

## GitHub Actions

| Workflow | Does |
| --- | --- |
| `docs` | Builds this site on PRs, and deploys it to GitHub Pages on `main` |
| `docs-apps` | Fails a PR when the [Applications](../platforms/kubernetes/applications.md) tables don't match `kubernetes/apps` in the committed tree |
| `renovate` | Runs Renovate hourly |
| `claude-review` | Claude (Opus 5.5) reviews every PR, including Renovate's: when it's opened as ready, when a draft is marked ready, and when Renovate pushes to its own PR (a new version or a conflict rebase). It researches version bumps against upstream changelogs and the config here, checks other changes for breakage, and posts one verdict comment plus inline findings. Other pushes don't trigger a review: answer the findings inline, then comment `/bot-review` on the open PR (repo owner only) for a fresh review that also takes the replies into account |
| `image-pull` | Pre-pulls images changed in a PR, warming the cache in [Zot](../platforms/docker/index.md#07-zot) and on the node the runner is on, which Spegel then serves to the other nodes, so rollouts after merge don't wait on downloads |
| `labeler`, `label-sync` | PR labels by path, and label definitions from `.github/labels.yaml` |
| `tag` | Monthly release tag |

## Writing these docs

Pages live in [`docs/content/`](https://github.com/bykaj/home-ops/tree/main/docs/content). The
navigation is set explicitly in
[`zensical.toml`](https://github.com/bykaj/home-ops/blob/main/docs/zensical.toml),
so add every new page there. [Zensical](https://zensical.org) supports
admonitions (`!!! note`), content tabs, Mermaid diagrams, code annotations and
grid cards. See the [authoring docs](https://zensical.org/docs/authoring/markdown/).

The privacy plugin downloads external assets at build time, such as the Google
Fonts and the theme's CDN scripts (Mermaid, lightbox). It serves them from
`assets/external/` on this site, so readers' browsers never contact third-party
CDNs. Its download cache in `docs/.cache/` is gitignored. A build needs network
access to those CDNs, and the plugin skips the theme's video-ad SDK on purpose.
