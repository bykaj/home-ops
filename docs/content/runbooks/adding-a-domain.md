---
description: Serve a new domain from the cluster, with DNS, routing and a wildcard certificate
---

# Adding a Domain

A domain served by the cluster needs to be in six places: cert-manager,
both external-dns instances, the certificates `export` and `import`
directories, cloudflared, and both Gateways. Copy an existing domain (for
example `cetana.id`) in each file. In the steps below, `example.com` is the new
domain and `example-com` is its dashed form, used in resource names.

It takes **two PRs**. The certificate import reads an item from 1Password that
only exists after the certificate has been issued once (see
[why](#why-two-prs)).

## Before you start

1. **Move the zone to Cloudflare.** Add the zone in Cloudflare and point the
   registrar's nameservers at it. Every domain the cluster serves is
   managed in Cloudflare, so cert-manager can solve DNS01 challenges and
   external-dns can write public records there.
2. **Check that the API tokens cover the zone.** cert-manager
   (`cert-manager/cert-manager-secret`) and external-dns
   (`network/external-dns-cloudflare-secret`) each have a `CF_API_TOKEN`.
   Both need DNS edit access to the zone:

    ```sh
    for s in cert-manager/cert-manager-secret network/external-dns-cloudflare-secret; do
      kubectl -n "${s%/*}" get secret "${s#*/}" -o jsonpath='{.data.CF_API_TOKEN}' | base64 -d \
        | xargs -I{} curl -s -H "Authorization: Bearer {}" \
            "https://api.cloudflare.com/client/v4/zones?name=example.com" \
        | jq -c '[.result[] | {name, status}]'
    done
    # expect: [{"name":"example.com","status":"active"}] twice
    ```

3. **Wait for public DNS** to show the Cloudflare nameservers:
   `dig +short NS example.com @1.1.1.1`. Your local resolver and the UDM may
   cache the old nameservers for a while. That doesn't matter: cert-manager
   checks DNS01 through 1.1.1.1 only (`dns01RecursiveNameserversOnly`).

## PR 1: serve the domain

| File | Change |
| --- | --- |
| [`cert-manager/cert-manager/app/clusterissuer.yaml`](https://github.com/bykaj/home-ops/blob/main/kubernetes/apps/cert-manager/cert-manager/app/clusterissuer.yaml) | Add `example.com` to `letsencrypt-production`'s `dnsZones` |
| [`network/external-dns/unifi/helmrelease.yaml`](https://github.com/bykaj/home-ops/blob/main/kubernetes/apps/network/external-dns/unifi/helmrelease.yaml) | Add `example.com` to `domainFilters` (LAN records) |
| [`network/external-dns/cloudflare/helmrelease.yaml`](https://github.com/bykaj/home-ops/blob/main/kubernetes/apps/network/external-dns/cloudflare/helmrelease.yaml) | Add `example.com` to `domainFilters` (public records) |
| [`network/certificates/export/certificates.yaml`](https://github.com/bykaj/home-ops/blob/main/kubernetes/apps/network/certificates/export/certificates.yaml) | Add a `Certificate` named `example-com` for `example.com` and `*.example.com`, `secretName: example-com-tls` |
| [`network/certificates/export/pushsecrets.yaml`](https://github.com/bykaj/home-ops/blob/main/kubernetes/apps/network/certificates/export/pushsecrets.yaml) | Add a `PushSecret` named `example-com-tls` that copies the secret to 1Password |
| [`network/cloudflare-tunnel/app/resources/config.yaml`](https://github.com/bykaj/home-ops/blob/main/kubernetes/apps/network/cloudflare-tunnel/app/resources/config.yaml) | Add `example.com` and `*.example.com` ingress entries |
| [`network/envoy-gateway/config/gateway.yaml`](https://github.com/bykaj/home-ops/blob/main/kubernetes/apps/network/envoy-gateway/config/gateway.yaml) | Add `example-com-tls` to `certificateRefs` on **both** `envoy-external` and `envoy-internal` |
| [`networking/dns.md`](../networking/dns.md) | Add the zone to the list and update the zone count |

Leave `network/certificates/import` alone for now. The app that uses the
domain can ship in the same PR: set its route hostname to `example.com` or
`<app>.example.com` (see [Adding an App](adding-an-app.md)).

Validate:

```sh
for d in cert-manager/cert-manager/app network/certificates/export \
         network/cloudflare-tunnel/app network/envoy-gateway/config; do
  kustomize build "kubernetes/apps/$d" >/dev/null || echo "FAIL $d"
done
yamllint --config-file .yamllint.yaml kubernetes/apps/network kubernetes/apps/cert-manager
just docs build
```

## After merging PR 1

1. **Wait for the certificate.** Issuing it takes a minute or two:

    ```sh
    kubectl -n network get certificate example-com
    kubectl -n network get challenge   # while it is still pending
    ```

2. **Push it to 1Password.** The `PushSecret` usually runs before the
   certificate's secret exists. It then fails with `could not get source
   secret` and won't retry until its 1h `refreshInterval`. Force a sync
   instead of waiting:

    ```sh
    kubectl -n network annotate pushsecret example-com-tls force-sync="$(date +%s)" --overwrite
    kubectl -n network get pushsecret example-com-tls   # expect Ready=True, Synced
    op item get example-com-tls --vault Homelab --fields label=tls.crt >/dev/null && echo pushed
    ```

    Renewals don't need this. The secret already exists by then.

3. **Check the gateways and routing.** The HTTPS listeners should resolve the
   new certificate, and a route on the domain should answer both publicly and
   on the LAN:

    ```sh
    kubectl -n network get gateway envoy-external envoy-internal \
      -o jsonpath='{range .items[*]}{.metadata.name}: {.status.listeners[?(@.name=="https")].conditions[?(@.type=="ResolvedRefs")].status}{"\n"}{end}'
    dig +short example.com @1.1.1.1        # Cloudflare proxy IPs (envoy-external routes only)
    dig +short example.com @10.73.0.254    # internal.bykaj.app or external.bykaj.app
    curl -sv -o /dev/null --resolve example.com:443:10.73.20.120 https://example.com/ 2>&1 \
      | grep -E 'subject:|issuer:'
    ```

## PR 2: import the certificate

Add an `ExternalSecret` named `example-com-tls` to
[`network/certificates/import/externalsecrets.yaml`](https://github.com/bykaj/home-ops/blob/main/kubernetes/apps/network/certificates/import/externalsecrets.yaml).
Copy an existing one and update the name, the 1Password key and the
`cert-manager.io/*` annotations (`alt-names`, `certificate-name`,
`common-name`).

After a cluster rebuild, the certificate then comes back from 1Password
(`refreshPolicy: CreatedOnce`), and cert-manager treats it as already issued.
That avoids a burst of new Let's Encrypt orders, which are rate-limited.

## Why two PRs?

`certificates-import` runs with `wait: true`, and `certificates-export`
depends on it. If the import `ExternalSecret` points at a 1Password item that
doesn't exist yet, it never becomes ready. `certificates-import` then never
becomes healthy, so the export side, with the new `Certificate` and
`PushSecret`, is never applied, and the item never gets created. Shipping the
import only after the first push breaks that loop.
