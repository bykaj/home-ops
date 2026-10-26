---
description: A compromised LiteLLM release ran in the cluster for about five hours
---

# LiteLLM 1.107.0 Compromise

!!! abstract "Summary"

    **2026-10-21.** Renovate proposed LiteLLM v1.107.0, and it was merged. That
    image contained a credential stealer and a remote code loader
    ([BerriAI/litellm#47826](https://github.com/BerriAI/litellm/issues/47826)).
    It ran for about 5 hours before it was found. The secrets the pod could
    read were treated as leaked and rotated the same day.

## Timeline

- **13:46 UTC.** [#2972](https://github.com/bykaj/home-ops/pull/2972), a
  Renovate PR for `ghcr.io/berriai/litellm:v1.107.0`, was merged.
- **Between 13:46 and 18:57 UTC.** Renovate's Dependency Dashboard warned that it "could not
  determine new digest": upstream had deleted the tag. Following that up led
  to the upstream advisory.
- **18:57 UTC.** Contained: the Flux Kustomization was suspended and the
  Deployment scaled to 0. The pod had the payload files and a detached Python
  process.
- **After 18:57 UTC.** The LiteLLM master key and the model provider key were
  rotated, the image was pinned back to v1.106.2
  ([#2991](https://github.com/bykaj/home-ops/pull/2991)), and the new pod was
  checked clean.

## Exposure

The pod could read the LiteLLM master key, the model provider API key and the
Dragonfly URL. It had no egress policy, its service account had no RBAC
bindings, and it had no database credentials. Nothing else was exposed.

## What changed

- **Egress allowlist**
  ([#2992](https://github.com/bykaj/home-ops/pull/2992)): the `litellm-egress`
  policy limits the proxy to DNS, its cache, the in-namespace inference pods
  and the provider APIs (see [Networking](../networking/index.md#cilium)).
  Its first version broke provider requests for about 5 minutes; that led to
  removing CoreDNS `autopath`
  ([#2993](https://github.com/bykaj/home-ops/pull/2993), see
  [KB-006](../troubleshooting/kb/006-tofqdns-timeouts.md)).
- **Release age:** LiteLLM updates wait 3 days, and the image moved to Docker
  Hub so that rule works (see
  [KB-015](../troubleshooting/kb/015-renovate-release-age-holds-forever.md)).
- **Detection** ([#2994](https://github.com/bykaj/home-ops/pull/2994)): the
  [Yanked Images](../architecture/gitops.md#yanked-images) workflow opens an
  issue when a pinned image disappears upstream, and `CiliumEgressPolicyDenied`
  alerts on any blocked egress (see [Alerting](../kubernetes/alerting.md)).

## What to watch

- Don't remove the release-age rule or the egress policy without a
  replacement. Treat new LiteLLM releases as untrusted until upstream has
  fixed its release pipeline.
- A model on a new provider host needs a `toFQDNs` rule in `litellm-egress`,
  or its requests time out and the egress alert fires.
- Not built yet: runtime detection (Tetragon) and diffing image contents on
  Renovate PRs.
