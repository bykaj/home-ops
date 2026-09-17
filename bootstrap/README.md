# Bootstrap

Takes freshly installed Talos nodes all the way to a fully self-managed Flux cluster, and provisions a fresh TrueNAS server with the supporting applications it needs, all handled by Doco-CD.

More information per area:

- [Kubernetes Cluster](./kubernetes/)
- [Docker Applications](./docker/)

## Prerequisites

- The [Mise](https://mise.jdx.dev/) CLI [installed](https://mise.jdx.dev/getting-started.html#installing-mise-cli) on your workstation and [activated](https://mise.jdx.dev/getting-started.html#activate-mise) in your shell.
- Tools pinned in `.mise/config.toml` installed via `mise install`. These are available for MacOS (arm64/amd64), Windows (x64) and Linux (arm64/amd64).
- A signed-in 1Password CLI (`op`). Machine secrets never live in this repo; every
  `op://` reference in the configs and bootstrap manifests is resolved at apply time with `op inject`.\
- A valid `talosconfig` at the repo root (mise points `TALOSCONFIG` there).
  The justfile derives the controller endpoint and node list from
  `talosctl config info`, so nothing is hardcoded here.
- The UDM configuration below. `k8s.internal` points at the Cilium
  LoadBalancer VIP, which exists only once Cilium is installed, so bootstrap
  talks to the controller's node IP directly until the `apps` stage brings
  Cilium up.

## UDM configuration

The Kubernetes API is fronted by a Cilium LoadBalancer Service (`kube-api`,
`10.73.20.100`, `externalTrafficPolicy: Local` so only nodes with a
healthy apiserver attract traffic). Cilium announces it to the UDM over BGP
along with every other LoadBalancer IP. See the [config](../../kubernetes/apps/kube-system/cilium/config/) folder.

```mermaid
graph LR
    client(Client) -->|hashed flow| udm("`**UDM**
    _ASN 64513_`")
    udm -->|ECMP| k1("`**k8s-01**
    10.73.20.10`")
    udm -->|ECMP| k2("`**k8s-02**
    10.73.20.20`")
    udm -->|ECMP| k3("`**k8s-03**
    10.73.20.30`")
    udm -->|ECMP| nas("`**nas**
    10.73.1.10`")
    k1 & k2 & k3 -. "`**BGP** _ASN 64514_
    VIPs from 10.73.20.0/24`" .-> udm
    nas -. "`**BGP** _ASN 64515_
    VIP 10.73.1.10/32`" .-> udm
    client@{ shape: browser}
    nas@{ shape: lin-cyl }
```

The VIPs the UDM learns this way:

| VIP            | Hostname             | Backs                          |
| -------------- | -------------------- | ------------------------------ |
| `10.73.20.100` | `k8s.internal`       | `kube-api` Service (apiserver) |
| `10.73.20.110` | `internal.bykaj.app` | `envoy-internal` Gateway       |
| `10.73.20.120` | `external.bykaj.app` | `envoy-external` Gateway       |

Static A records in UniFi (under Settings → Policy Table → DNS, or wherever Ubiquiti decides to put
it this time after a new Network release) points the API hostname at the VIP and the reverse-proxy
at the Traefik gateway:

```text
k8s.internal → 10.73.20.100
proxy.bykaj.app → 10.73.2.100
```

Cilium (ASN 64514) peers from the node IPs on the SERVERS subnet
(`10.73.20.10-30`) and announces LoadBalancer Service IPs from the
`10.73.20.0/24` pool. UniFi accepts a single FRR config upload per device
(Settings → Routing Table → BGP):

<details>
<summary>FRR config</summary>

```text
router bgp 64513
  bgp router-id 10.73.0.254
  no bgp ebgp-requires-policy

  neighbor k8s peer-group
  neighbor k8s remote-as 64514

  neighbor 10.73.20.10 peer-group k8s
  neighbor 10.73.20.20 peer-group k8s
  neighbor 10.73.20.30 peer-group k8s

  neighbor nas peer-group
  neighbor nas remote-as 64515

  neighbor 10.73.1.10 peer-group nas

  address-family ipv4 unicast
    maximum-paths 3
    neighbor k8s next-hop-self
    neighbor k8s soft-reconfiguration inbound
    neighbor nas next-hop-self
    neighbor nas soft-reconfiguration inbound
  exit-address-family
exit
```

</details>

The `maximum-paths 3` gives true ECMP across the control plane nodes for the
`kube-api` VIP (FRR's eBGP default is a single best path).

> [!WARNING]
> Re-uploading the FRR config briefly bounces established BGP sessions.

To verify: `vtysh -c "show bgp summary"` on the UDM, `10.73.20.100/32`
showing an ECMP path per healthy apiserver in `vtysh -c "show ip route"`,
and `curl -k https://k8s.internal:6443/livez`. In
`vtysh -c "show ip bgp 10.73.20.100"` every path should carry the
`multipath` tag; `ip route show 10.73.20.100` should list one `nexthop`
line per node (a single flat line means multipath is not installed in the
kernel).

> [!NOTE]
> `k8s.internal` rides the Cilium `kube-api` LoadBalancer, so the named API
> endpoint depends on Cilium being healthy. If the CNI is ever down, reach
> the API directly at `https://10.73.20.10-30:6443` and the Talos API at
> the same node addresses; neither depends on the CNI.

## UDM boot scripts

The UDM root filesystem is an overlay: writes to `/etc` survive reboots but
are wiped by firmware upgrades, and `/run` is tmpfs. `/data` is a real
partition that survives both, so anything custom lives there as a boot
script, run by the `udm-boot` service from
[unifi-utilities/unifi-common](https://github.com/unifi-utilities/unifi-common)
(UniFi OS 4.x+):

> [!WARNING]
> Never pipe a remote script directly into your shell (bash, sh, zsh, etc.).
> Download it, read it, and only then execute it. Always. No exceptions.

```sh
curl -fsL "https://raw.githubusercontent.com/unifi-utilities/unifi-common/HEAD/remote_install.sh" | /bin/bash
```

> [!NOTE]
> The service unit itself sits on the overlay, so a firmware upgrade can
> remove it while the scripts in `/data/on_boot.d` remain.
> After an upgrade, check `systemctl is-enabled udm-boot` and rerun the
> installer if needed.

## ECMP flow hashing

The kernel default (`fib_multipath_hash_policy=0`) hashes on source and
destination IP only, so a given client always lands on the same node.
Policy `1` adds ports to the hash and spreads individual connections
across the ECMP next-hops.

<details>
<summary><code>/data/on_boot.d/30-ecmp-l4-hash.sh</code></summary>

```sh
#!/bin/sh
echo "net.ipv4.fib_multipath_hash_policy = 1" > /etc/sysctl.d/30-ecmp-l4-hash.conf
sysctl -w net.ipv4.fib_multipath_hash_policy=1
```

</details>

The `sysctl.d` drop-in covers reboots on its own; the boot script recreates
it after firmware upgrades.

> [!TIP]
> To verify spreading, run this a few times from one machine and expect the
> node in the SAN to vary:
>
> ```sh
> openssl s_client -connect k8s.internal:6443 </dev/null 2>/dev/null \
>   | openssl x509 -noout -ext subjectAltName
> ```

## HTTP/3 discovery

Envoy Gateway serves HTTP/3 (`http3: {}` in the `ClientTrafficPolicy`, UDP
443 on both LoadBalancer Services), but browsers only discover it after a
first TCP visit via `Alt-Svc` unless DNS advertises it. dnsmasq on the UDM
can publish HTTPS (type 65) records for the gateway hostnames; the hex
payload decodes to priority 1, target `.`, `alpn="h3,h2"`. Lookups follow
CNAMEs, so app hostnames the UDM resolves to the gateways itself need no
records of their own.

> [!IMPORTANT]
> Externally published apps (`plex`, anything else behind the Cloudflare
> tunnel) are CNAMEs to `external.bykaj.app` in public DNS, and the UDM has
> no HTTPS record for those names. The browser's HTTPS query is forwarded
> upstream, where Cloudflare answers with its own HTTPS record, and
> browsers then use that record and connect through Cloudflare, even
> though the A/AAAA answer is the internal gateway IP. LAN traffic to
> those apps rides the tunnel instead of the local path.

The main dnsmasq instance loads `--conf-dir=/run/dnsmasq.dhcp.conf.d/`,
which is tmpfs and regenerated by `ubios-udapi-server`, hence another boot
script.

<details>
<summary><code>/data/on_boot.d/40-dnsmasq-https-rr.sh</code></summary>

```sh
#!/bin/sh
CONF_DIR=/run/dnsmasq.dhcp.conf.d
for i in $(seq 1 30); do [ -d "$CONF_DIR" ] && break; sleep 2; done
[ -d "$CONF_DIR" ] || exit 0
cat > "$CONF_DIR/custom.conf" <<RR
dns-rr=external.bykaj.app,65,00010000010006026833026832
dns-rr=internal.bykaj.app,65,00010000010006026833026832
RR
[ -f /run/dnsmasq-main.pid ] && kill "$(cat /run/dnsmasq-main.pid)" 2>/dev/null
exit 0
```

</details>

Killing the main dnsmasq is safe; `ubios-udapi-server` respawns
it with the new config.

> [!NOTE]
> A provisioning event in the Network app can regenerate the conf dir and
> drop `custom.conf` until the next reboot; rerunning the script puts it
> back.

To verify:

```sh
dig +short @10.73.0.254 internal.bykaj.app HTTPS   # expect: 1 . alpn="h3,h2"
curl --http3-only -sk -o /dev/null -w '%{http_version}\n' https://internal.bykaj.app/
```
