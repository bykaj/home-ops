---
description: Prometheus alert rules, Alertmanager routing and silences
---

# Alerting

Prometheus (kube-prometheus-stack) evaluates the alert rules and Alertmanager
sends them to Pushover. Two other detections, Flux reconciliation alerts and the
[Yanked Images](../architecture/gitops.md#yanked-images) workflow, don't use
Prometheus rules; see [Outside Prometheus](#outside-prometheus).

## Routing

The routing is defined in the
[`AlertmanagerConfig`](https://github.com/bykaj/home-ops/blob/main/kubernetes/apps/observability/kube-prometheus-stack/app/alertmanagerconfig.yaml)
(UI at `alertmanager.bykaj.app`):

- Every alert goes to **Pushover**, critical and warning alike. Firing alerts
  are sent with priority 1, resolved ones with priority 0.
- `Watchdog` and `InfoInhibitor` go to the `null` receiver.
- A critical alert inhibits the warning alert with the same `alertname` and
  `namespace`.
- Alerts are grouped by `alertname`, `cluster` and `job` (wait 1m, interval
  10m) and repeat every 24h while firing.

The message is the alert's `description`, or its `summary` if there is none,
followed by its labels. Put what to do in `description`.

## Rule sources

| Source | Alerts | Where |
| --- | --- | --- |
| kube-prometheus-stack defaults | ~150 | Upstream kubernetes-mixin and node-exporter rules (`defaultRules` left at chart defaults) |
| Rook Ceph | 88 | `createPrometheusRules` in the [cluster HelmRelease](https://github.com/bykaj/home-ops/blob/main/kubernetes/apps/rook-ceph/rook-ceph/cluster/helmrelease.yaml); `CephNodeInconsistentMTU` is disabled |
| kopiur | 13 | Chart `prometheusRule` in [kopiur](https://github.com/bykaj/home-ops/blob/main/kubernetes/apps/system/kopiur/app/helmrelease.yaml) (backup failures, stale backups, repository health) |
| crd-schema-publisher | 2 | Chart rules |
| Custom rules | 29 | Below |

Upstream rule sets change with chart upgrades. To see what is loaded, run
`kubectl get prometheusrules -A` or open the Prometheus *Alerts* page.

## Custom rules

Rules for one app live in that app's `prometheusrule.yaml` (or its chart's
`prometheusRule` values). Rules that aren't tied to an app go in
`additionalPrometheusRulesMap` in the
[kube-prometheus-stack HelmRelease](https://github.com/bykaj/home-ops/blob/main/kubernetes/apps/observability/kube-prometheus-stack/app/helmrelease.yaml).

### Cluster-wide (`additionalPrometheusRulesMap`)

| Alert | Severity | Fires when |
| --- | --- | --- |
| `CiliumEgressPolicyDenied` | critical | An egress policy dropped a packet on a node in the last 10 minutes; see [Cilium](../networking/index.md#cilium) |
| `DockerhubRateLimitRisk` | critical | More than 100 running containers use `docker.io` images |
| `NvmeTemperatureHigh` | warning | An NVMe drive is within 2 °C of its warning threshold for 5 minutes |
| `NvmeTemperatureCritical` | critical | An NVMe drive is at or above its warning threshold for 1 minute |
| `OomKilled` | critical | A container restarted because of an OOM kill in the last 10 minutes |
| `ZfsUnexpectedPoolState` | critical | A NAS ZFS pool is not `online` |

### Per app

| Alert | Severity | Fires when | App |
| --- | --- | --- | --- |
| `AutobrrNetworkUnmonitored` | critical | An enabled IRC channel is not monitored, for 1 hour | [autobrr](https://github.com/bykaj/home-ops/blob/main/kubernetes/apps/downloads/autobrr/app/prometheusrule.yaml) |
| `BlackboxProbeFailed` | critical | A blackbox probe fails for 15 minutes | [blackbox-exporter](https://github.com/bykaj/home-ops/blob/main/kubernetes/apps/observability/blackbox-exporter/app/helmrelease.yaml) |
| `CertManagerAbsent` | critical | cert-manager is missing from Prometheus for 5 minutes | [cert-manager](https://github.com/bykaj/home-ops/blob/main/kubernetes/apps/cert-manager/cert-manager/app/prometheusrule.yaml) |
| `CertManagerCertExpirySoon` | critical | A certificate expires within 21 days | cert-manager |
| `CertManagerCertNotReady` | critical | A certificate is not ready for 5 minutes | cert-manager |
| `CertManagerHittingRateLimits` | critical | Let's Encrypt answers with HTTP 429 | cert-manager |
| `LongRunningTransaction` | warning | A PostgreSQL transaction runs longer than 5 minutes | [cloudnative-pg](https://github.com/bykaj/home-ops/blob/main/kubernetes/apps/database/cloudnative-pg/app/prometheusrule.yaml) |
| `BackendsWaiting` | warning | More than 300 backends are waiting on locks held by other queries | cloudnative-pg |
| `PGDatabase` | warning | A database's transaction ID age exceeds 300 million (wraparound risk) | cloudnative-pg |
| `PGReplication` | warning | A standby lags more than 5 minutes behind the primary | cloudnative-pg |
| `LastFailedArchiveTime` | warning | WAL archiving failed after the last successful archive | cloudnative-pg |
| `DatabaseDeadlockConflicts` | warning | A database has had more than 10 deadlocks since its statistics were last reset | cloudnative-pg |
| `ReplicaFailingReplication` | warning | A replica is in recovery but its WAL receiver is down | cloudnative-pg |
| `ExternalDNSStale` | critical | ExternalDNS has not synced for 90 seconds, for 15 minutes | [external-dns](https://github.com/bykaj/home-ops/blob/main/kubernetes/apps/network/external-dns/cloudflare/prometheusrule.yaml) |
| `FluxInstanceAbsent` | critical | The Flux instance metric is missing for 5 minutes | [flux-instance](https://github.com/bykaj/home-ops/blob/main/kubernetes/apps/flux-system/flux-instance/app/prometheusrule.yaml) |
| `FluxInstanceNotReady` | critical | The Flux instance is not ready for 5 minutes | flux-instance |
| `GatusEndpointDown` | critical | An external or infrastructure endpoint in Gatus fails for 5 minutes | [gatus](https://github.com/bykaj/home-ops/blob/main/kubernetes/apps/observability/gatus/app/prometheusrule.yaml) |
| `GatusEndpointExposed` | critical | An internal-only hostname has a public DNS record; see [Gatus](../networking/dns.md) | gatus |
| `NutExporterAbsent` | critical | The NUT exporter is down for 5 minutes | [nut-exporter](https://github.com/bykaj/home-ops/blob/main/kubernetes/apps/observability/nut-exporter/app/prometheusrule.yaml) |
| `UpsOnBattery` | warning | The UPS runs on battery | nut-exporter |
| `UpsLowRuntime` | critical | The UPS is on battery with less than 10 minutes of runtime left | nut-exporter |
| `UpsLowBattery` | warning | The UPS battery charge is below 50% | nut-exporter |
| `UpsBatteryReplace` | warning | The UPS reports that its battery needs replacing | nut-exporter |

Coder (`development/coder`, 14 rules under `app/rules/`) and LLMKube are
disabled, so their rules are not loaded.

## Silences

Permanent silences are `Silence` resources managed by the
[silence-operator](https://github.com/bykaj/home-ops/tree/main/kubernetes/apps/observability/silence-operator/silences),
so they live in Git like everything else:

| Silence | Mutes |
| --- | --- |
| `ceph-node-local-diskspace-warning` | `CephNodeDiskspaceWarning` for `/dev/nvme*` devices |
| `ceph-node-nfsmount-diskspace-warning` | `CephNodeDiskspaceWarning` for the `/etc/nfsmount.conf` mount |
| `cpu-throttling` | `CPUThrottlingHigh` (small CPUs throttle, mostly during bootstrap) |
| `hpa-maxed-out` | `KubeHpaMaxedOut` |
| `nas-memory-high-utilization` | `NodeMemoryHighUtilization` on the NAS (`nas.internal:9100`) |

Use the Alertmanager UI for temporary silences, such as during maintenance.

## Adding a rule

1. Put it in the app's `prometheusrule.yaml` if it is about one app, or in
   `additionalPrometheusRulesMap` if it isn't.
2. Use `severity: critical` for anything that needs action and `warning` for
   anything that can wait. A critical alert inhibits a warning with the same
   name in the same namespace.
3. Write a `description` that says what to do; it is the Pushover message.
4. Check the expression against live data in Prometheus first, including a
   period when it should have fired.
5. Add it to the tables above.

## Outside Prometheus

- **Flux:** the [`alerts` component](components.md#alerts) sends Kustomization
  and HelmRelease reconciliation failures to Alertmanager and posts commit
  statuses to GitHub.
- **Yanked images:** a GitHub workflow opens a `type/security` issue when a
  pinned image disappears from its registry; see
  [Yanked images](../architecture/gitops.md#yanked-images).
- **Gatus:** endpoint checks feed the `GatusEndpoint*` rules above.
