---
name: add-docker-app
description: Use when deploying or changing an application on the NAS (TrueNAS) — docker-compose stacks under docker/nas/, doco-cd deployments, "deploy X to the NAS", secrets, Traefik/DNS wiring or storage for a compose app
---

# Add an App to the NAS

Apps live in `docker/nas/NN-<app>/docker-compose.yaml`, deployed GitOps-style by [doco-cd](https://github.com/kimdre/doco-cd) (config: `docker/nas/.doco-cd.yaml`). It deploys on every push to `main` (GitHub webhook) with an hourly poll as fallback, auto-discovers stacks one directory deep, and **`delete: true` means removing (or renaming) a directory deletes the running stack**. doco-cd also manages itself (`00-doco-cd`, `SELF_UPDATE_ENABLED`). Mirror an existing app rather than inventing structure:

| Pattern                                    | Reference                                                        |
| ------------------------------------------ | ---------------------------------------------------------------- |
| Web UI behind Traefik, OIDC, secrets       | `07-zot` (`configs:` from secrets), `05-garage` (env secrets)    |
| Bind-mount storage on the pool             | `05-garage`, `07-zot` (named volume + `driver_opts`)             |
| Non-HTTP ports through Traefik entrypoints | `06-bootimus` (TCP on `web-alt`, UDP on `tftp`)                  |
| Host network, no proxy                     | `01-frr`, `04-exporters`                                         |
| Config files in `config/`                  | `01-frr`, `05-garage`, `07-zot` (read-only bind of `./config/…`) |

## Steps

1. **Directory**: next free `NN-` prefix (`ls docker/nas/`); `00-doco-cd` is reserved. The number is ordering only; keep it stable. doco-cd names the compose project after the directory (overriding top-level `name:`), so renaming deletes and recreates the stack, and unpinned named volumes come back empty.

2. **Compose file**, following existing apps:
   - Top-level `name: <app>`, `container_name: <app>`, `restart: unless-stopped`.
   - Registry-qualified image with a pinned version tag (digest optional, see `06-bootimus`). **Never write a tag from memory**: look up the upstream project's current release first. Renovate handles updates.
   - Set `user:` where the image supports it (garage runs as `4000:4000`).
   - Config files: `config/` subdirectory, bind-mounted read-only (`./config/<file>:/path:ro`). A single-file bind mount isn't refreshed in a running container; note in the docs if the app needs a restart after config changes (see `07-zot`).
   - Persistent data on the pool under `/mnt/vault/Applications/<app>/<vol>`: either a named volume with `driver: local` + `driver_opts` (`device`, `o: bind`, `type: none`) like garage/zot, or a direct host-path bind like bootimus. Ask the user to create the dataset/directory first; doco-cd won't.
   - Keep the YAML keys sorted per `.agents/instructions/sorting.instructions.md`.

3. **Secrets**: add `VAR_NAME: op://Homelab/<item>/<field>` under `external_secrets` in `docker/nas/.doco-cd.yaml` (keep it sorted) and reference it as `${VAR_NAME}` in the compose file. For secrets the app reads from files, build them with a top-level `configs:` block (`environment:` or `content:` with `${VAR}`) like `07-zot`. Use the item's **real field names** (ask the user, never guess).

4. **Expose it** (HTTP):
   - Join the shared network: `networks: apps: {name: apps, external: true}` and `networks: [apps]` on the service. Ansible creates it (`just bootstrap nas`); every stack, Traefik included, declares it external.
   - Labels:

     ```yaml
     labels:
       dexd.enabled: "true" # CNAME <host> -> docker.bykaj.app in UniFi
       traefik.enable: "true"
       traefik.http.routers.<app>.rule: Host(`<app>.bykaj.app`)
       traefik.http.services.<app>.loadbalancer.server.port: "<port>"
     ```

   - Traefik terminates TLS on `websecure` with the `*.bykaj.app` / `*.bykaj.io` wildcards and redirects HTTP. NAS services are LAN-only; use `bykaj.app` unless the user says otherwise.
   - Don't publish HTTP `ports:`. Non-HTTP traffic goes through a Traefik entrypoint (`tftp` 69/udp, `web-alt` 8080, `smb` 445) or, failing that, a published port or `network_mode: host`.
   - OIDC apps use Authentik at `https://auth.cetana.id/application/o/<app>/`; the user creates the provider and stores the client ID/secret in 1Password.

5. **Docs**: add a `### NN-<app>` section under "Stacks" in `docs/docker/index.md` (in directory order), and update any other page that describes what the stack touches (DNS, storage/backups, networking). Validate with `zensical build --strict`.

6. **Verify**: `docker compose -f docker/nas/NN-<app>/docker-compose.yaml config --quiet` (unset `${VAR}` warnings are expected) and `yamllint --config-file .yamllint.yaml docker/nas/NN-<app>`. Show the user the files before committing. Commit style: `feat(<app>): <what>` (e.g. `feat(zot): add zot OCI registry with pull-through cache to NAS`). Pushing to `main` deploys; `just docker sync-stacks` forces a run.

## Common mistakes

- **Inventing an image tag**: check the upstream release; a made-up tag deploys nothing or the wrong thing.
- **Secret in compose but not in `.doco-cd.yaml`**: the `${VAR}` silently resolves empty.
- **Publishing HTTP ports**: everything HTTP goes through Traefik on `apps`; published ports bypass TLS.
- **Forgetting `dexd.enabled`**: the Traefik route works but the hostname never resolves.
- **Declaring `apps` without `external: true`**: the stack tries to own the shared network.
- **Renaming/renumbering an existing app directory casually**: `delete: true` tears the old stack down; anonymous and unpinned named volumes start empty.
- **Editing `00-doco-cd` casually**: a merge redeploys doco-cd itself. Keep the `doco-cd_data` volume external, and remember its API and webhook go through Traefik (`doco-cd.bykaj.app`); `container_name` forces the `applier` strategy.
