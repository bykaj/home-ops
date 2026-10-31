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

Immich, Wallos and Audiobookshelf use their native OIDC support, configured
in each app's UI, not in the repository. Audiobookshelf's group claim is left
empty, because it only accepts groups named exactly `admin`, `user` and
`guest`, and its local password login is disabled.

Karakeep only stores the OIDC profile picture when a user is first created
(it doesn't refresh the profile on sign-in). An account created under a
previous identity provider keeps an empty picture until it is set in its
database.

pgAdmin's OIDC is configured in the repository. `OAUTH2_AUTO_LOGIN` skips its
login page and goes straight to Pocket ID; append `?no_auto_login` to `/login`
to see the page anyway. Logging out also ends the Pocket ID session through
`OAUTH2_LOGOUT_URL`, so the pgAdmin URL must be listed under the client's
logout callback URLs in Pocket ID.

### Apps behind `gateway-oidc`

Sonarr, Radarr, Prowlarr, Whisparr, Bazarr, SABnzbd and Stash sign in through
[`gateway-oidc`](components.md#gateway-oidc).

- **Sonarr stays on `gateway-oidc`.** Its native OIDC allows exactly one
  user.
- **Sonarr and Radarr** have `/signalr` on their `api` rule, because Bazarr
  follows them over SignalR with an API key.
- **Stash** gets its API key injected by an `HTTPRouteFilter` after the
  Pocket ID login, so there is no second login. Its `api` rule matches the
  `ApiKey` header (Whisparr) or the `apikey` query parameter (Homepage,
  external players) instead of a path. Keep Stash's own form login on: the
  API key only exists while credentials are set.

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
