---
description: Split-horizon DNS with two external-dns instances, plus HTTP/3 discovery
---

# DNS

## Split horizon

Two [external-dns](https://github.com/kubernetes-sigs/external-dns) instances
manage different views of the same zones (`bykaj.app`, `bykaj.dev`,
`bykaj.io`). Both watch Gateway API routes (`HTTPRoute`, `GRPCRoute`,
`TLSRoute`) and `DNSEndpoint` CRDs.

| Instance | Provider | Watches | Records |
| --- | --- | --- | --- |
| `external-dns-unifi` | UniFi UDM, via the [UniFi webhook provider](https://github.com/home-operations/external-dns-unifi-webhook) | Routes on all Gateways | LAN records for every app, resolving to the gateway it is attached to |
| `external-dns-cloudflare` | Cloudflare | Routes on `envoy-external` only | Public CNAMEs to `external.bykaj.app`, served through the tunnel |

The Gateways carry an `external-dns.kubernetes.io/target` annotation
(`internal.bykaj.app` / `external.bykaj.app`), so app records are CNAMEs to the
gateway hostname instead of hard-coded IPs.

## Static records

These live in UniFi (Settings → Policy Table → DNS) because they must exist
before or outside the cluster:

```text
k8s.internal    → 10.73.20.100   # kube-api LoadBalancer
proxy.bykaj.app → 10.73.2.100    # Traefik on the NAS
```

## NAS services

Compose stacks on the NAS get DNS records from
[dexd](https://github.com/ishioni/dexd), which watches Docker labels
(`dexd.enabled: "true"`) and writes records to the UDM pointing at the NAS
reverse proxy. See [Docker](../docker/index.md).

## HTTP/3 discovery

Envoy Gateway serves HTTP/3 (`http3: {}` in the `ClientTrafficPolicy`, UDP 443
on both LoadBalancer Services). Browsers only discover it after a first TCP
visit via `Alt-Svc`, unless DNS advertises it. dnsmasq on the UDM publishes
HTTPS (type 65) records for the gateway hostnames. The hex payload decodes to
priority 1, target `.`, `alpn="h3,h2"`. Lookups follow CNAMEs, so app hostnames
that the UDM resolves to the gateways need no records of their own.

The records are written by a [UDM boot script](udm-boot-scripts.md#http3-https-records).

!!! important "Externally published apps take the tunnel on the LAN"

    Externally published apps (Plex, and anything else behind the Cloudflare
    tunnel) are CNAMEs to `external.bykaj.app` in public DNS, and the UDM has no
    HTTPS record for those names. The browser's HTTPS query goes upstream,
    Cloudflare answers with its own HTTPS record, and the browser connects
    through Cloudflare even though the A/AAAA answer is the internal gateway
    IP. LAN traffic to those apps rides the tunnel instead of the local path.

Verify with:

```sh
dig +short @10.73.0.254 internal.bykaj.app HTTPS   # expect: 1 . alpn="h3,h2"
curl --http3-only -sk -o /dev/null -w '%{http_version}\n' https://internal.bykaj.app/
```
