---
description: Per-app setup choices, sign-in methods and gotchas that aren't obvious from the manifests
---

# App Notes

Notes on apps where the manifests don't tell the whole story: settings that
live in the app's own UI, decisions not to change something, and gotchas
found the hard way, grouped by namespace. Each namespace starts with how its
apps sign in. For the full catalog, see [Applications](applications.md). NAS
stacks have their notes on the [Docker](../docker/index.md#stacks) page.

Sign-in methods:

- **Native OIDC**: the app's own OpenID Connect support, with its own client
  in [Pocket ID](#pocket-id).
- **gateway-oidc**: Envoy logs the user in to Pocket ID before the request
  reaches the app ([`gateway-oidc`](components.md#gateway-oidc)), for apps
  without usable OIDC of their own.
- **Own login**: the app's own accounts, not on single sign-on.
- **No login**: deliberately open, so it stays reachable when something is
  broken.

## `ai`

| App | Sign-in |
| --- | --- |
| [LiteLLM](#litellm) | Native OIDC for the Admin UI; the API and `/mcp/` use keys |

### LiteLLM

How the gateway, models, keys and MCP servers fit together is on the
[AI](ai.md) page; these are the gotchas.

- **Sign-in.** Native OIDC covers the Admin UI only, so the API and `/mcp/`
  keep working with keys. The Pocket ID client has callback URL
  `https://litellm.bykaj.app/sso/callback`, uses PKCE, and its credentials are
  `OIDC_CLIENT_ID` and `OIDC_CLIENT_SECRET` in the `litellm` 1Password item.
  The UI role comes from a `litellm_role` custom claim (`proxy_admin` for
  admins). The free tier allows up to 5 SSO users. The login page redirects
  straight to Pocket ID (`auto_redirect_ui_login_to_sso`), and the master key
  no longer works as a UI password (`disable_env_credential_login`). Password
  login remains only for database users with a password, and SSO users have
  none.
- Updates wait 3 days in Renovate, and the image comes from Docker Hub so that
  rule works ([KB-015](../../operations/troubleshooting/kb/015-renovate-release-age-holds-forever.md)).
- The `litellm-egress` policy allows model providers by FQDN. A provider on a
  new host needs a rule there, or its requests time out.
- The ChatGPT token PVC is `ReadWriteOnce`, and the operator's Deployment
  rolls out with a surge pod and has no `strategy` field. A required
  `podAffinity` on the proxy's own labels keeps the new pod on the old pod's
  node, where the volume can attach; elsewhere it would wait on a Multi-Attach
  error forever. With no other proxy pod (first start, drain) the scheduler
  lets it go anywhere. The proxy runs as root, so the Kopiur mover does too
  (`KOPIUR_MOVER_UID`/`GID` `"0"`).
- Email (alerts and the UI's test email) goes through the
  [SMTP relay](../../infrastructure/networking/index.md#smtp-relay), which
  `litellm-egress` allows on port 25. The relay offers no STARTTLS, so
  `SMTP_TLS` is `"False"`; without it every send fails. The sender is
  `MAIL_FROM` from the `smtp` 1Password item. LiteLLM only sends email with
  `email` in `general_settings.alerting`.
- Anything else LiteLLM fetches from the internet times out against that
  policy, so it uses bundled copies instead: the model cost map
  (`LITELLM_LOCAL_MODEL_COST_MAP`) and the Admin UI blog posts
  (`LITELLM_LOCAL_BLOG_POSTS`). The blog fetch is synchronous, so without that
  setting every UI page load froze the whole proxy for 5 seconds.
- The Prisma CLI that LiteLLM runs at startup for its database contacts
  `checkpoint.prisma.io` (version check and telemetry). `litellm-egress`
  blocks it and `CiliumEgressPolicyDenied` fired, so `CHECKPOINT_DISABLE=1`
  turns it off.
- The Admin UI checks GitHub for the latest release every 5 minutes while it's
  open, and the check can't be turned off. `litellm-egress` allows
  `api.github.com` for it, because blocked attempts set off
  `CiliumEgressPolicyDenied`.
- MCP servers are `LiteLLMMCPServer` resources in `litellm/mcp/servers` (Flux
  Kustomization `litellm-mcp`); the operator runs each one and registers it
  with the proxy. `litellm-egress` allows them by the operator's
  `app.kubernetes.io/component: mcp-server` label on port 3000, so a server on
  another port needs that port added. Each server has its own policy that
  admits only the proxy.
- The kubesearch MCP server (kubesearch.dev search plus repo clones) may only
  reach GitHub, and keeps the reference repos permanently cloned through
  `KUBESEARCH_POOL_REPOS`. Clients reach it through the proxy with a LiteLLM
  key.
- The Context7 MCP server (upstream library docs by version) is Context7's
  hosted server at `mcp.context7.com`, not run by the operator: the proxy
  sends `CONTEXT7_API_KEY` from the `litellm` 1Password item as a bearer
  token, and `litellm-egress` allows that host on port 443. Agents use it
  only as a fallback after kubesearch (see `AGENTS.md`).
- The kguardian MCP server isn't run by the operator: `kguardian-mcp` points
  the proxy at the `/mcp` endpoint kguardian's llm-bridge already serves
  (port 8080, no authentication). `litellm-egress` allows that port
  separately, and the `kguardian-llm-bridge` policy admits only the proxy and
  the kguardian frontend. Its `generate_network_policy` output is a starting
  point, not a finished policy: it selects on `pod-template-hash`, only knows
  flows seen since the pods started, and attributes kubelet probes to
  whichever host-network pod shares the node.
- The Home Assistant MCP server (ha-mcp) has no route of its own: only the
  proxy may call it, and it may only reach `homeassistant.home.cetana.net` on
  port 443. It acts as a dedicated Home Assistant user through a long-lived
  access token (`HOMEASSISTANT_TOKEN` in the `litellm` 1Password item);
  revoking that token in Home Assistant cuts it off. Its settings page is
  disabled, so configuration only comes from Git.
- The UniFi MCP server (unifi-network-mcp) logs in to the gateway as the
  dedicated local account (password in the `unifi` 1Password item)
  and may only reach `gateway.home.cetana.net`. Its tools load on demand
  (`UNIFI_TOOL_REGISTRATION_MODE=lazy`), and changes still go through its
  preview-then-confirm flow.
- The proxy runs in DB mode on the `litellm-postgres` CNPG cluster, so every
  client gets its own key: a `LiteLLMVirtualKey` next to the app, which the
  operator creates through the proxy's admin API and writes to a Secret in
  the app's namespace. Limit each key to the models the app uses; an empty
  `models` list allows all of them, so a key that needs none (MCP only) gets
  `models: [no-default-models]`. The master key is only for the operator;
  don't hand it to apps.
- Virtual keys get no MCP servers unless their team grants them
  (`LiteLLMTeam.spec.mcpServers`), like the `claude-code` team in
  `litellm/mcp/teams/claude-code`.
- Models and MCP servers stay file-backed (`applyMode` at its default, and
  `store_model_in_db: false`); only keys, teams and spend live in the
  database.
- The proxy reaches Pocket ID for SSO through the envoy-external pods
  (`cyrannus.id` resolves to that LoadBalancer IP in the cluster), which
  `litellm-egress` allows on port 10443.
- The proxy takes the client IP from the rightmost `X-Forwarded-For` entry,
  which Envoy appends (`use_x_forwarded_for`, one trusted hop, pod network as
  trusted proxies). That only holds while the route is on envoy-internal:
  behind cloudflared there is one more hop.
- `LITELLM_SALT_KEY` encrypts credentials stored in the database. It must
  never change once the database holds data.
- Windshift's key is in the `windshift-litellm` Secret and is pasted into its
  AI Connection by hand, so a new key needs a manual update there.
- Background: [LiteLLM 1.107.0 compromise](../../operations/history/2026-10-litellm-compromise.md).

## `default`

| App | Sign-in |
| --- | --- |
| [Karakeep](#karakeep) | Native OIDC |
| [Paperless](#paperless) | Native OIDC, no password login |
| [pgAdmin](#pgadmin) | Native OIDC |
| [Seafile](#seafile) | Native OIDC (OAuth), no password login |
| Wallos | Native OIDC, configured in its own UI |

### Karakeep

- It stores the profile picture only when a user is created. An account from
  a previous identity provider has no picture until it is set in the
  database.

### Paperless

- AI suggestions and document chat go through LiteLLM with the `paperless`
  virtual key (`PAPERLESS_AI_LLM_*`): `chatgpt/gpt-6-luna` for suggestions and
  chat, `openai/text-embedding-3-small` for the chat's embeddings. Suggestions
  always ask for a tool call, so a replacement model must support forced tool
  calls through LiteLLM.
- The embeddings are a SQLite file (`llmindex.db`) on the data PVC, rebuilt
  daily at 02:10 (`PAPERLESS_LLM_INDEX_TASK_CRON` default), so it is backed up
  with the rest of the PVC but can be regenerated.
- `paperless-egress` (`networkpolicy.yaml`) allows Postgres, Dragonfly,
  LiteLLM, envoy-external (Pocket ID), the SMTP relay, `deb.debian.org` on
  port 80 and `api.github.com`. The image has no Dutch OCR data, so its
  `init-tesseract-langs` step apt-installs `tesseract-ocr-nld` on every start;
  without the Debian rule the package is skipped and Dutch OCR is missing. The GitHub rule is for the
  dashboard's update check, which users switch on in their UI settings.
- No mail accounts are configured. Adding one needs an egress rule for its
  IMAP server.

### pgAdmin

- It skips its login page (`OAUTH2_AUTO_LOGIN`); use `/login?no_auto_login` to
  see it.
- Logging out also ends the Pocket ID session (`OAUTH2_LOGOUT_URL`), so the
  pgAdmin URL must be in the client's logout callback URLs in Pocket ID.

### Seafile

Seafile Pro serves `files.bykaj.app` (`APP_SUBDOMAIN: files`) and replaced
[OpenCloud](#opencloud). Pro is needed to store libraries in S3, and is free
for up to three active users.

#### Sign-in and roles

- Pocket ID is configured in `resources/local_settings.py`: Seahub only reads
  OAuth, email and role settings from Python, so the container command links
  the file into its install directory. The client is confidential, with
  callback URL `https://files.bykaj.app/oauth/callback/`. Accounts are keyed on
  the `sub` claim; the desktop and mobile apps sign in through the system
  browser.
- Every Pocket ID login creates an account, so the Pocket ID client only allows
  the `admins`, `family` and `friends` groups.
- Pocket ID accounts can't use or set a password
  (`DISABLE_SSO_USER_LOCAL_PWD_LOGIN`). Seafile exempts system admins, and the
  login page keeps showing the password form; Seahub can't hide it.
- The role follows the `groups` claim on every login: the highest group wins
  (`resources/seahub_custom_functions.py`), and `ENABLED_ROLE_PERMISSIONS` in
  `local_settings.py` sets the limits:

| Role | Disk | AI credits per month |
| --- | --- | --- |
| `admins` | 100 GB | unlimited |
| `family` | 100 GB | 500 |
| `friends` | 50 GB | 200 |
| `default` | 1 GB | none |

- 100 credits are USD 1, counted at OpenAI's list prices (`price` in
  `LLM_MODELS` and `EMBEDDING_MODEL`); the ChatGPT route itself is
  subscription. `default` is explicit because Seahub's own default is
  unlimited; it also applies to an account until its next login.
- A role set by hand is overwritten at the next login; a per-user quota still
  wins over the role quota. System admin rights are separate from the
  `admins` role.
- With an empty `groups` claim Seahub skips the update and the user keeps
  their last role. The client's allowed groups prevent that, so keep them in
  sync with the roles.
- The local admin from the `seafile` 1Password item is deactivated. A Pocket ID
  account can't be linked to it, so it only served to make the first Pocket ID
  account an admin. Inactive accounts don't count toward the three users.

#### Storage and database

- Libraries are in the `seafile-commits`, `seafile-fs` and `seafile-blocks`
  Garage buckets; the PVC (Kopiur) holds the generated config, avatars,
  thumbnails and logs.
- The database comes from the
  [mariadb component](../../infrastructure/storage/mariadb.md) (user
  `seafile`, database `seafile_db`); `mariadb.yaml` adds `ccnet_db` and
  `seahub_db`, so the first start uses existing databases (`USE_EXISTING_DB`)
  and needs no root password.

#### Extensions

They run as their own Deployments, because the PVC can only be mounted on one
node. The metadata server and Seafile AI read the libraries straight from S3
(`resources/seafile.env`).

| Deployment | Purpose | Notes |
| --- | --- | --- |
| `seafile-seadoc` | SeaDoc editor | Routed under `/sdoc-server/` (prefix stripped) and `/socket.io` |
| `seafile-metadata` | Metadata server | Data in the `seafile-metadata` bucket |
| `seafile-ai` | Seafile AI | Needs the metadata server; calls LiteLLM with the `seafile` virtual key |
| `seafile-seasearch` | Full-text search | Index on its own `ceph-block` PVC without backup, since it can be rebuilt |
| `seafile-notification` | Pushes library, lock and permission changes to clients | Websocket on `/notification`; Seafile posts events to `/events` internally (JWT) |

- The AI models are the `LLM_MODELS` and `EMBEDDING_MODEL` env vars on Seahub
  and Seafile AI, which override `seafile_ai_config.yaml`. The kubelet expands
  `$(AI_API_KEY)` in them, which only works because `AI_API_KEY` sorts first in
  the rendered env.
- SeaSearch's admin is `seafile` with `SEASEARCH_PASSWORD` from the `seafile`
  item, created on its first start; Seafile and Seafile AI send
  base64(`seafile:<password>`) as `SEASEARCH_TOKEN`.

#### Egress policy

`networkpolicy.yaml` gives every pod its own egress allowlist, besides DNS.
All but SeaSearch get the shared secrets and settings through `envFrom`, so
being internal-only is no reason to leave one open.

| Policy | Allows |
| --- | --- |
| `seafile-egress` | The extensions' ports, MariaDB, Dragonfly, LiteLLM, envoy-external (Pocket ID and Seafile's own public URLs for SeaDoc and notifications), the SMTP relay, Garage |
| `seafile-seadoc-egress` | MariaDB, Seahub on port 80 (`SEAHUB_SERVICE_URL`) |
| `seafile-ai-egress` | MariaDB, Dragonfly, Garage, LiteLLM, Seahub, the metadata server, SeaSearch |
| `seafile-metadata-egress` | MariaDB, Dragonfly, Garage |
| `seafile-notification-egress` | MariaDB |
| `seafile-seasearch-egress` | Nothing (index on disk) |

- Nothing on the internet is allowed. A new feature or upgrade that calls out
  raises `CiliumEgressPolicyDenied`; add a rule only if the destination is
  expected.
- A new extension needs its own policy, and a new port on one needs adding to
  the policies of the pods that call it.

#### WebDAV

- SeafDAV serves `https://files.bykaj.app/seafdav`. The username is the contact
  email, the password the WebDAV password each user sets under Settings.
- Libraries show up as their name plus `-` and the first six characters of
  their ID.
- `ENABLE_SEAFDAV` only adds the WebDAV setting to Seahub; the server starts
  from `enabled` in `seafdav.conf` on the PVC, which the `shared-permissions`
  init container switches on at every start (on a fresh volume from the second
  start).
- The NAS reaches it on the envoy-external LoadBalancer directly, so uploads
  have no size limit; see
  [Document sync](../../infrastructure/storage/backups.md#document-sync).

#### Running as non-root

- The image starts as root; `NON_ROOT` runs the Seafile processes as uid 8000,
  which is also the Kopiur mover UID.
- The entrypoint refuses to start unless `/shared/seafile` has mode exactly
  `777`, but the image's boot script creates it as 755, and it inherits the
  setgid bit of the PVC root. The `shared-permissions` init container creates
  it with 777 and clears setgid first.
- SeaDoc runs without `NON_ROOT`: its boot script creates `/shared/logs` as
  root, after which its converter can't write its log. It only keeps logs, in
  an emptyDir.

## `downloads`

| App | Sign-in |
| --- | --- |
| Bazarr | gateway-oidc |
| Prowlarr | gateway-oidc |
| [Radarr](#radarr) | gateway-oidc |
| SABnzbd | gateway-oidc |
| [Sonarr](#sonarr) | gateway-oidc |
| Whisparr | gateway-oidc |

Each app has its own Pocket ID client; an `api` rule on the route stays open
for app-to-app calls that carry an API key.

### Sonarr

- It stays on gateway-oidc, because its native OIDC allows only one user.
- Its `api` rule includes `/signalr`, so Bazarr can follow it over SignalR
  with an API key.

### Radarr

- Like Sonarr, its `api` rule includes `/signalr` for Bazarr.

## `external-secrets`

| App | Sign-in |
| --- | --- |
| [1Password Connect](#1password-connect) | No UI; External Secrets uses its API token |

### 1Password Connect

Its credentials file must contain raw JSON while the 1Password field holds
base64; a mistake here also stops External Secrets from fixing it. See
[KB-010](../../operations/troubleshooting/kb/010-onepassword-connect-credentials.md) before
changing how Connect reads its credentials.

## `media`

| App | Sign-in |
| --- | --- |
| [Audiobookshelf](#audiobookshelf) | Native OIDC, configured in its own UI |
| Immich | Native OIDC, configured in its own UI |
| [Jellyfin](#jellyfin) | Own login |
| [Plex](#plex) | Plex account; no login from the LAN and cluster networks |
| [Stash](#stash) | gateway-oidc, with its API key injected |

### Audiobookshelf

- Its group claim is empty, because it only accepts groups named exactly
  `admin`, `user` and `guest`.
- Its local password login is off.

### Jellyfin

- Not on single sign-on: the SSO plugin is archived and only worked in the
  browser.

### Plex

`PLEX_NO_AUTH_NETWORKS` covers the LAN and the pod and Service networks. The
Tailscale range was removed with the Tailscale ingresses, so don't add it
back.

### Stash

- It gets its API key from an `HTTPRouteFilter` after the Pocket ID login, so
  there is no second login.
- Its `api` rule matches the `ApiKey` header (Whisparr) or the `apikey` query
  parameter (Homepage, external players).
- Keep Stash's form login on: the API key only exists while credentials are
  set.

## `observability`

| App | Sign-in |
| --- | --- |
| Prometheus, Alertmanager, VictoriaLogs, Grafana (anonymous), Goldilocks, kguardian | No login |

The Flux UI (`flux-system`) has no login either. These tools deliberately stay
open, so they are reachable when something is broken.

## `rook-ceph`

| App | Sign-in |
| --- | --- |
| [Rook-Ceph](#rook-ceph) dashboard | Own login (Ceph dashboard) |

### Rook-Ceph

The active mgr leaks memory slowly; see
[Known Noise](../../operations/troubleshooting/known-noise.md#ceph).

## `security`

| App | Sign-in |
| --- | --- |
| [Pocket ID](#pocket-id) | Passkeys; it is the identity provider for everything above |

### Pocket ID

- SMTP and app settings live in Pocket ID's own UI and database, not in Git,
  so the Kopiur backup of its volume is the only copy.
- It downloads the GeoLite2 City database with `MAXMIND_LICENSE_KEY`. Only the
  license key is needed, no MaxMind account ID.
- `ICON_LIBRARY_URL` points at the selfh.st icons on GitHub directly. jsDelivr
  serves only some files from that repository, because it exceeds jsDelivr's
  50 MB package limit.
- Background: [Authentik to Pocket ID](../../operations/history/2026-10-pocket-id.md).

## Disabled apps

Notes for apps whose `ks.yaml` is commented out (see
[Applications](applications.md#disabled)), kept for when they come back.

### OpenCloud

- **Disabled** since Seafile took over `files.bykaj.app`. Enabling it again
  needs another hostname, or Seafile moved off `files`. Its PVC comes back from
  the newest Kopiur snapshot, and its files are still in the `opencloud` Garage
  bucket (`decomposeds3`); the PVC holds the metadata, so a restore needs both.
- **Sign-in.** Pocket ID replaces its built-in IdP, and accounts are created on
  first login, keyed on the `sub` claim. It has four public PKCE clients in
  Pocket ID, with fixed client IDs:

    | Client ID          | Callback URLs                                                                                                                 |
    | ------------------ | ----------------------------------------------------------------------------------------------------------------------------- |
    | `opencloud-web`    | `https://files.bykaj.app/`, `https://files.bykaj.app/oidc-callback.html`, `https://files.bykaj.app/oidc-silent-redirect.html` |
    | `OpenCloudDesktop` | `http://127.0.0.1`, `http://localhost` (any port is accepted)                                                                 |
    | `OpenCloudIOS`     | `oc://ios.opencloud.eu`                                                                                                       |
    | `OpenCloudAndroid` | `oc://android.opencloud.eu`                                                                                                   |

- **Roles** come from the `groups` claim on every login
  (`resources/proxy.yaml`): `admins` → Admin, `family` → User, `friends` →
  Guest, highest first. A user in none of these groups can't sign in. Pocket ID
  only sends `groups` for the `groups` scope, so the web and app scopes include
  it.
- **CSP** (`resources/csp.yaml`) is OpenCloud's default plus
  `https://cyrannus.id/`.
- **Email.** The optional `notifications` service is on (`OC_ADD_RUN_SERVICES`)
  and sends share and space emails through the
  [SMTP relay](../../infrastructure/networking/index.md#smtp-relay); users can
  turn them off under Preferences. Sharing with an email address uses guest
  links (`OC_ENABLE_GUEST_LINKS`): a one-time link, valid for 30 minutes and
  without an account, renewable with a PIN.
- **Web extensions** (only Pastebin so far) are mounted from their
  `opencloudeu/web-extensions` images as image volumes under `/opt/web-apps`
  (`WEB_ASSET_APPS_PATH`); the built-in apps stay available. To add one, add
  another image volume at `/opt/web-apps/<name>` with subPath
  `web/apps/<name>`. A Renovate rule treats the `<extension>-` tag prefix as a
  separate line per extension.
