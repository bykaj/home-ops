---
description: Replacing Authentik with Pocket ID, and putting a gateway login in front of apps without OIDC
---

# Authentik to Pocket ID

!!! abstract "Summary"

    **2026-10-18 and 2026-10-19.** Every OIDC app moved from Authentik to
    [Pocket ID](https://pocket-id.org) at `cyrannus.id`. Authentik and the
    `cetana.id` domain it used were removed. Apps without their own OIDC
    support got a login at the gateway instead.

## Why

Pocket ID is much simpler to run than Authentik: one container with SQLite,
backed up by Kopiur. Removing Authentik also exposed a gap: the *arr apps,
set to external authentication, served their API key to the whole LAN. That
needed a replacement login in front of them.

## What changed

- **Pocket ID** runs in the `security` namespace. SMTP and app settings live
  in its own UI and database, not in Git. It downloads GeoLite2 for sign-in
  locations ([#2934](https://github.com/bykaj/home-ops/pull/2934)), and its
  icon library points at GitHub directly, because jsDelivr won't serve the
  icon repository ([#2927](https://github.com/bykaj/home-ops/pull/2927)).
- **[`gateway-oidc`](../../platforms/kubernetes/components.md#gateway-oidc)**
  ([#2916](https://github.com/bykaj/home-ops/pull/2916)) puts an Envoy OIDC
  login on an app's `app` route rule, with one Pocket ID client per app,
  while an `api` rule stays open for calls that carry an API key. It covers
  Sonarr, Radarr, Prowlarr, Whisparr, Bazarr and SABnzbd. Sonarr and Radarr
  also need `/signalr` on the `api` rule, because Bazarr follows them over
  SignalR ([#2926](https://github.com/bykaj/home-ops/pull/2926)).
- **Stash** uses `gateway-oidc` plus a credential-injection filter that adds
  its API key after the Pocket ID login, so there's no second login
  ([#2932](https://github.com/bykaj/home-ops/pull/2932)).
- **Native OIDC**, configured in each app's own UI: Immich, Wallos and
  Audiobookshelf. Audiobookshelf is also public now
  ([#2933](https://github.com/bykaj/home-ops/pull/2933)).
- **Tailscale:** the ingresses and the app connector were removed
  ([#2928](https://github.com/bykaj/home-ops/pull/2928),
  [#2931](https://github.com/bykaj/home-ops/pull/2931)). Only the exit node
  remains, so nothing in the cluster is published on the tailnet.

## Decisions

- **Observability tools stay without a login** (Prometheus, Alertmanager,
  VictoriaLogs, Grafana, the Flux UI), so they're reachable when something is
  broken.
- **Sonarr stays on `gateway-oidc`.** Its native OIDC allows only one user,
  while the gateway lets in everyone in the client's allowed groups. Check how
  many users an app's native OIDC supports before switching to it.
- **Jellyfin isn't on Pocket ID.** The SSO plugin was archived, its forks are
  fragmented, and it only works in the browser.

## What to watch

Before putting a new app behind `gateway-oidc`, check the `envoy-internal`
access log for paths other apps call on it, and add them to the `api` rule.
