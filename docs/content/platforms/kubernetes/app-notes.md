---
description: Per-app setup choices and gotchas that aren't obvious from the manifests
---

# App Notes

Notes on apps where the manifests don't tell the whole story: settings that
live in the app's own UI, decisions not to change something, and gotchas
found the hard way. Apps that behave as their manifests say aren't listed.
For the full catalog, see [Applications](applications.md). NAS stacks have
their notes on the [Docker](../docker/index.md#stacks) page.

## Identity

### Pocket ID

- SMTP and app settings live in Pocket ID's own UI and database, not in Git,
  so the Kopiur backup of its volume is the only copy.
- It downloads the GeoLite2 City database with `MAXMIND_LICENSE_KEY`. Only the
  license key is needed, no MaxMind account ID.
- `ICON_LIBRARY_URL` points at the selfh.st icons on GitHub directly. jsDelivr
  serves only some files from that repository, because it exceeds jsDelivr's
  50 MB package limit.
- Background: [Authentik to Pocket ID](../../operations/history/2026-10-pocket-id.md).

### Apps with their own OIDC

These apps use their native OIDC support.

- **Immich, Wallos and Audiobookshelf** are configured in their own UI, not in
  the repository.
- **Audiobookshelf** has an empty group claim, because it only accepts groups
  named exactly `admin`, `user` and `guest`. Its local password login is off.
- **Karakeep** stores the profile picture only when a user is created. An
  account from a previous identity provider has no picture until it is set in
  the database.
- **pgAdmin** skips its login page (`OAUTH2_AUTO_LOGIN`); use
  `/login?no_auto_login` to see it. Logging out also ends the Pocket ID session
  (`OAUTH2_LOGOUT_URL`), so the pgAdmin URL must be in the client's logout
  callback URLs in Pocket ID.
- **LiteLLM** uses native OIDC for its Admin UI only, so the API and `/mcp/`
  keep working with keys. The Pocket ID client has callback URL
  `https://litellm.bykaj.app/sso/callback`, uses PKCE, and its credentials are
  `OIDC_CLIENT_ID` and `OIDC_CLIENT_SECRET` in the `litellm` 1Password item.
  The UI role comes from a `litellm_role` custom claim (`proxy_admin` for
  admins). The free tier allows up to 5 SSO users. The login page redirects
  straight to Pocket ID (`auto_redirect_ui_login_to_sso`), and the master key
  no longer works as a UI password (`disable_env_credential_login`). Password
  login remains only for database users with a password, and SSO users have
  none.

### Apps behind `gateway-oidc`

Sonarr, Radarr, Prowlarr, Whisparr, Bazarr, SABnzbd and Stash sign in through
[`gateway-oidc`](components.md#gateway-oidc).

- **Sonarr** stays here, because its native OIDC allows only one user.
- **Sonarr and Radarr** have `/signalr` on their `api` rule, so Bazarr can
  follow them over SignalR with an API key.
- **Stash** gets its API key from an `HTTPRouteFilter` after the Pocket ID
  login, so there is no second login. Its `api` rule matches the `ApiKey`
  header (Whisparr) or the `apikey` query parameter (Homepage, external
  players). Keep Stash's form login on: the API key only exists while
  credentials are set.

### Not on single sign-on

- **Jellyfin.** The SSO plugin is archived and only worked in the browser.
- **Observability tools** (Prometheus, Alertmanager, VictoriaLogs, Grafana,
  the Flux UI, Goldilocks, kguardian) deliberately have no login, so they stay
  reachable when something is broken.

## AI

### LiteLLM

- Updates wait 3 days in Renovate, and the image comes from Docker Hub so that
  rule works ([KB-015](../../operations/troubleshooting/kb/015-renovate-release-age-holds-forever.md)).
- The `litellm-egress` policy allows model providers by FQDN. A provider on a
  new host needs a rule there, or its requests time out.
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
  setting every UI page load froze the whole proxy for 5 seconds. The UI's
  GitHub release check also times out (5 seconds, once per 5 minutes), but
  it's async and harmless.
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

## Media

### Plex

`PLEX_NO_AUTH_NETWORKS` covers the LAN and the pod and Service networks. The
Tailscale range was removed with the Tailscale ingresses, so don't add it
back.

## Platform

### 1Password Connect

Its credentials file must contain raw JSON while the 1Password field holds
base64; a mistake here also stops External Secrets from fixing it. See
[KB-010](../../operations/troubleshooting/kb/010-onepassword-connect-credentials.md) before
changing how Connect reads its credentials.

### Rook-Ceph

The active mgr leaks memory slowly; see
[Known Noise](../../operations/troubleshooting/known-noise.md#ceph).
