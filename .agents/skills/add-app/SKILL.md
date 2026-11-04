---
name: add-app
description: Use when deploying a new application to the cluster — scaffolding a Flux Kustomization plus app-template HelmRelease under kubernetes/apps/ (new app, new service, "add X to the cluster")
---

# Add a New Application

Scaffolds `kubernetes/apps/<namespace>/<app>/` with a Flux Kustomization (`ks.yaml`) and an app-template HelmRelease. Every value below comes from current repo conventions — when in doubt, mirror a recent real app instead of inventing structure:

| Reference app                               | Shows                                                                      |
| ------------------------------------------- | -------------------------------------------------------------------------- |
| `kubernetes/apps/network/echo-server`       | Minimal stateless app + route                                              |
| `kubernetes/apps/network/cloudflare-tunnel` | Secrets, config file via configMapGenerator                                |
| `kubernetes/apps/default/paperless`         | Custom probes, dragonfly dependency, kopiur-backed persistence, PostgreSQL |

## Step 1: Gather details

Ask the user (AskUserQuestion) for anything not already given:

1. **App name** and **namespace** (existing dirs: `ls kubernetes/apps/`)
2. **Image** repository + tag (upstream's current release)
3. **Port** the app listens on, and whether it gets a **route** (hostname); internal (`envoy-internal`, default) or public (`envoy-external`)
4. **Persistence** — does the app store state? (→ kopiur backup component)
5. **Database** — does the app need PostgreSQL (→ `database/postgres` component) or MySQL/MariaDB (→ `database/mariadb` component)? If so, is it a brand-new database, or does a backup of it already exist?
6. **Cache** — does the app need Redis (or a Redis-compatible store for queues, sessions or websockets)? (→ dragonfly component)
7. **Secrets** — env vars from 1Password? (→ ExternalSecret). Get the 1Password item name AND its exact field names — never guess field names
8. **Config files** — mounted config? (→ configMapGenerator + `resources/`)
9. **Dependencies** — other Flux Kustomizations this app needs
10. **Outbound connections** — what the app itself connects to: its database and cache, LiteLLM, Pocket ID (OIDC), the SMTP relay, Garage (S3), other in-cluster services, and which internet hosts (or "any URL", for crawlers and media servers). Needed for the egress policy, which every `envoy-external` app gets

## Step 2: Create the files

Layout:

```
kubernetes/apps/<namespace>/<app>/
├── ks.yaml
└── app/
    ├── kustomization.yaml
    ├── ocirepository.yaml
    ├── helmrelease.yaml
    ├── externalsecret.yaml      # only if secrets
    ├── networkpolicy.yaml       # every envoy-external app; also internal apps holding secrets or data
    └── resources/               # only if config files
```

### ks.yaml

```yaml
---
# yaml-language-server: $schema=https://schemas.bykaj.io/kustomize.toolkit.fluxcd.io/kustomization_v1.json
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: <app>
spec:
  interval: 1h
  path: "./kubernetes/apps/<namespace>/<app>/app"
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
    namespace: flux-system
  targetNamespace: <namespace>
```

**`wait`:** omit it for a normal leaf app — it defaults to `false`, and explicit `wait: false` is redundant boilerplate we no longer keep. Only add `wait: true` when _another_ Kustomization will `dependsOn` this one AND this Kustomization defines no `healthChecks`/`healthCheckExprs` — that is what gives the dependent a real readiness gate. If this Kustomization does define `healthChecks`, leave `wait` unset (setting `wait: true` would make Flux ignore those checks). Depending on another app (e.g. `kopiur` for persistence) does not by itself call for `wait`.

Do not add `commonMetadata` or `timeout` — both were dropped as boilerplate; the app-template chart sets `app.kubernetes.io/*` labels on the workloads, and `timeout` falls back to the Flux default.

**If the app has persistence**, add these to `spec` (components use `${APP}` and `${KOPIUR_*}` substitutions — see `kubernetes/components/kopiur/` for all knobs and their defaults):

```yaml
components:
  - ../../../../components/kopiur
postBuild:
  substitute:
    APP: <app>
    # Optional overrides, only when defaults don't fit:
    # KOPIUR_CLAIM: <app>-data      # PVC name (default: <app>)
    # KOPIUR_CAPACITY: 15Gi         # default: 5Gi
    # KOPIUR_MOVER_UID: "1000"      # default: 4000
    # KOPIUR_MOVER_GID: "1000"      # default: 4000
```

**If the app needs PostgreSQL**, it gets its own CNPG cluster from the postgres component. Add the component, its health check and the backup schedule (see `docs/content/infrastructure/storage/postgres.md` for all knobs):

```yaml
metadata:
  name: <app>
  labels:
    components.database/postgres: init # only for a brand-new database, see below
spec:
  components:
    - ../../../../components/database/postgres
  healthCheckExprs:
    - apiVersion: postgresql.cnpg.io/v1
      kind: Cluster
      current: has(status.conditions) && status.conditions.exists(e, e.type == 'Ready' && e.status == 'True')
  healthChecks:
    - apiVersion: postgresql.cnpg.io/v1
      kind: Cluster
      name: <app>-postgres
      namespace: <namespace>
  postBuild:
    substitute:
      APP: <app>
      POSTGRES_BACKUP_SCHEDULE: "<minute> 0 * * *"
```

- `healthCheckExprs` alone does nothing: Flux only evaluates it for resources listed in `healthChecks` (or with `wait: true`, which this skill avoids). List the app's own database resources there by name. Keep the expressions `current`-only and guarded with `has()`, so a database that is still starting counts as in progress, not failed.
- `<minute>` is the output of `just k8s cron-minute <app>`. Every app gets its own stable minute in the 00:xx hour, so the nightly dumps don't all start at once; don't leave the `23 0 * * *` default.
- The `components.database/postgres: init` label is only for a database that has never been backed up: it makes the cluster start with a plain `initdb` instead of recovering from Barman, which would fail without a backup. Leave it out when a backup already exists. After the first deploy, the label has to be removed in a follow-up commit once the first backup has run (`docs/content/operations/runbooks/new-database.md`); tell the user.

**If the app needs MySQL or MariaDB**, it gets its own replicated MariaDB from the `database/mariadb` component instead. Same pattern: `../../../../components/database/mariadb`, the `MariaDB` health check (`current: has(status.conditions) && status.conditions.exists(e, e.type == 'Ready' && e.status == 'True')`, plus a `healthChecks` entry for `<app>-mariadb`), `MARIADB_BACKUP_SCHEDULE` from `just k8s cron-minute <app>`, `dependsOn: []` in the HelmRelease, and the `components.database/mariadb: init` label for a brand-new database (remove it after the first base backup, then run `just k8s mariadb-mark-initialized <ns> <app>`, or the operator goes into an init error; tell the user). The app connects to `${APP}-mariadb-primary:3306` as `${APP}` with the password in the `${APP}-mariadb-app` Secret (key `password`). All knobs, and the timeline bump a rebuild needs, are in `docs/content/infrastructure/storage/mariadb.md`.

**If the app needs Redis**, it gets its own [Dragonfly](https://www.dragonflydb.io) instance (Redis-compatible) from the dragonfly component, named `<app>-dragonfly` (see the `database/dragonfly` section of `docs/content/platforms/kubernetes/components.md`):

```yaml
spec:
  components:
    - ../../../../components/database/dragonfly
  postBuild:
    substitute:
      APP: <app>
```

- Health check: add a `Dragonfly` entry to `healthCheckExprs` (`current: has(status.phase) && status.phase == 'Ready'`; the operator reports `Ready` with a capital R) and `<app>-dragonfly` to `healthChecks`.
- No password by default: the instance only accepts connections from its own namespace (and Prometheus). `components/database/dragonfly/authentication` is an optional sub-component that adds password auth from `${DRAGONFLY_PASSWORD_SECRET}`; no app uses it yet.

**Postgres or dragonfly → the HelmRelease needs `dependsOn: []`.** Both components append their operator (`cloudnative-pg`, `dragonfly-operator`) to the HelmRelease's `spec.dependsOn` with a JSON patch (`op: add`, `path: /spec/dependsOn/-`), and that patch fails the Flux Kustomization build when the list doesn't exist. See "Components that patch the HelmRelease" in the HelmRelease section.

Add user-specified dependencies to the Kustomization's `dependsOn`. Include `postBuild.substitute.APP` whenever any component is used; omit `components`/`postBuild` entirely otherwise.

### app/kustomization.yaml

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./externalsecret.yaml # only if secrets
  - ./networkpolicy.yaml # every envoy-external app
  - ./ocirepository.yaml
  - ./helmrelease.yaml
```

**If the app mounts config files**, put them in `resources/` and append:

```yaml
configMapGenerator:
  - name: <app>-configmap
    files:
      - config.yaml=./resources/config.yaml
generatorOptions:
  disableNameSuffixHash: true
  annotations:
    kustomize.toolkit.fluxcd.io/substitute: disabled
```

### app/ocirepository.yaml

```yaml
---
# yaml-language-server: $schema=https://schemas.bykaj.io/source.toolkit.fluxcd.io/ocirepository_v1.json
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata:
  name: <app>
spec:
  interval: 15m
  layerSelector:
    mediaType: application/vnd.cncf.helm.chart.content.v1.tar+gzip
    operation: copy
  ref:
    tag: <version>
  url: oci://ghcr.io/bjw-s-labs/helm/app-template
```

**Never hardcode `<version>` from memory** — use the version the rest of the repo is on:

```bash
/usr/bin/grep -h "tag:" kubernetes/apps/*/*/app/ocirepository.yaml | sort | uniq -c | sort -rn | head -1
```

### app/helmrelease.yaml

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/bjw-s-labs/helm-charts/main/charts/other/app-template/schemas/helmrelease-helm-v2.schema.json
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: <app>
spec:
  chartRef:
    kind: OCIRepository
    name: <app>
  interval: 1h
  values:
    controllers:
      <app>:
        annotations:
          reloader.stakater.com/auto: "true"
        pod:
          securityContext:
            runAsGroup: 4000
            runAsNonRoot: true
            runAsUser: 4000
        containers:
          app:
            image:
              repository: <image-repo>
              tag: <image-tag>@sha256:<index-digest>
            probes:
              liveness:
                enabled: true
              readiness:
                enabled: true
            resources:
              requests:
                cpu: 10m
              limits:
                memory: 256Mi
            securityContext:
              allowPrivilegeEscalation: false
              readOnlyRootFilesystem: true
              capabilities:
                drop:
                  - ALL
    service:
      app:
        ports:
          http:
            port: <port>
```

Adjust `runAsUser`/`runAsGroup` (and capabilities) to what the image requires; drop the pod `securityContext` only if the image genuinely can't run non-root.

Pin the image by digest (`<tag>@sha256:<digest>`), like the other HelmReleases; Renovate then keeps tag and digest up to date. Use the multi-arch index digest, not a single-platform one, and look it up from the registry instead of copying it from another repo:

```bash
crane digest <image-repo>:<image-tag>
```

`crane` comes from mise and prints the index digest for multi-arch images.

**Optional value blocks** (top-level under `values`, alphabetical: `controllers`, `persistence`, `route`, `service`):

Route (web UI/API):

```yaml
route:
  app:
    hostnames:
      - <app>.bykaj.app
    parentRefs:
      - name: envoy-internal # envoy-external for public apps
        namespace: network
```

Persistence (pairs with the kopiur block in ks.yaml; also add `fsGroup: 4000` + `fsGroupChangePolicy: OnRootMismatch` to the pod securityContext):

```yaml
persistence:
  data:
    existingClaim: <app> # must match KOPIUR_CLAIM if overridden
    globalMounts:
      - path: /data
  tmpfs: # writable /tmp for readOnlyRootFilesystem
    type: emptyDir
    globalMounts:
      - path: /tmp
```

Config file mount (pairs with configMapGenerator):

```yaml
persistence:
  config:
    type: configMap
    name: <app>-configmap
    globalMounts:
      - path: /config/config.yaml
        subPath: config.yaml
        readOnly: true
```

Secrets: add to the container:

```yaml
envFrom:
  - secretRef:
      name: <app>-secret
```

Components that patch the HelmRelease (postgres, mariadb, dragonfly): add an empty `dependsOn` list to the HelmRelease `spec`, after `interval` (see the sorting rules), so the components can append their operator to it. Keep it even when the app has no dependencies of its own:

```yaml
spec:
  chartRef:
    kind: OCIRepository
    name: <app>
  interval: 1h
  dependsOn: []
  values:
```

Database connection (pairs with the postgres component): CNPG generates a `<app>-postgres-app` Secret with the keys `uri`, `jdbc-uri`, `username`, `password`, `host`, `port`, `dbname` and `pgpass`. Use `uri` when the app takes a connection URL, or the individual keys otherwise:

```yaml
env:
  DATABASE_URL:
    valueFrom:
      secretKeyRef:
        name: "${APP}-postgres-app"
        key: uri
```

Redis connection (pairs with the dragonfly component): the Service is `<app>-dragonfly` on port 6379:

```yaml
env:
  REDIS_URL: "redis://${APP}-dragonfly:6379"
```

Use the variable name and format the app expects (some take a host and port instead, e.g. Immich's `REDIS_HOSTNAME: immich-dragonfly`).

### app/externalsecret.yaml (only if secrets)

```yaml
---
# yaml-language-server: $schema=https://schemas.bykaj.io/external-secrets.io/externalsecret_v1.json
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: <app>
spec:
  refreshInterval: 12h
  secretStoreRef:
    kind: ClusterSecretStore
    name: onepassword
  target:
    name: <app>-secret
    creationPolicy: Owner
    template:
      data:
        SOME_ENV_VAR: "{{ .<app>_field_name }}"
  dataFrom:
    - extract:
        key: <1password-item>
      rewrite:
        - regexp:
            source: "(.*)"
            target: "<app>_$1"
```

Convention: `metadata.name` is `<app>`, the generated Secret is `<app>-secret`, and `dataFrom.extract` + `rewrite` prefixes 1Password fields for use in `template.data` (see wotcher for a multi-item example). The `.<prefix>_<field>` references must use the item's real field names (from Step 1) — a wrong field name renders an empty value with no error. If the field names weren't provided and you can't ask, insert `<FIXME: 1password field name>` placeholders and call them out.

### app/networkpolicy.yaml (every envoy-external app)

Every app behind `envoy-external` gets an egress-only `CiliumNetworkPolicy`, and so does an internal app that holds secrets or data. Egress-only means ingress (envoy, Prometheus scrapes) keeps working without rules. One policy per pod (controller); name it `<app>-egress` (`<app>-<controller>-egress` for extra controllers). Mirror a real one: `security/pocket-id` (FQDN allowlist), `default/windshift` (database, Garage, LiteLLM, GitHub), `media/immich` (one per pod), `default/karakeep` (open internet for a crawler), `default/it-tools` (DNS only).

```yaml
---
# yaml-language-server: $schema=https://schemas.bykaj.io/cilium.io/ciliumnetworkpolicy_v2.json
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: <app>-egress
spec:
  # Egress only: <why this app is worth locking down: public, which secrets or
  # data it holds>, so it may reach <list> and nothing else
  egress:
    - toEndpoints:
        - matchLabels:
            k8s-app: kube-dns
            k8s:io.kubernetes.pod.namespace: kube-system
      toPorts:
        - ports:
            - port: "53"
              protocol: ANY
          rules:
            dns:
              - matchPattern: "*"
    # <one rule per destination, each with a comment saying what uses it>
  endpointSelector:
    matchLabels:
      app.kubernetes.io/controller: <controller>
      app.kubernetes.io/instance: <app>
```

Always keep the DNS rule, even for an app with no egress at all: an empty `egress: [{}]` deny rule breaks, because Flux turns `{}` into `null`. Add a rule for each outbound connection from Step 1, copying these blocks from an existing policy:

| Destination                                                      | Rule                                                                                                                                                    |
| ---------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Own Postgres                                                     | `toEndpoints` `cnpg.io/cluster: <app>-postgres`, 5432 (every instance, the primary moves)                                                               |
| Own MariaDB                                                      | `toEndpoints` `app.kubernetes.io/instance: <app>-mariadb` + `app.kubernetes.io/name: mariadb`, 3306                                                     |
| Own Dragonfly                                                    | `toEndpoints` `app: <app>-dragonfly` + `app.kubernetes.io/name: dragonfly`, 6379                                                                        |
| LiteLLM                                                          | `toEndpoints` `app.kubernetes.io/instance: litellm` + `app.kubernetes.io/name: litellm` in `ai`, 4000                                                   |
| Pocket ID, or any other public `*.bykaj.app` / `cyrannus.id` URL | `toEndpoints` `gateway.envoyproxy.io/owning-gateway-name: envoy-external` in `network`, **10443** (the LoadBalancer IP is translated to the envoy pods) |
| SMTP relay (`smtp.bykaj.io`)                                     | `toEndpoints` `app.kubernetes.io/name: smtp-relay` in `network`, 25                                                                                     |
| Garage (`s3.bykaj.io`) or anything else on the NAS               | `toCIDRSet` `cidrGroupRef: nas`, 443                                                                                                                    |
| Known internet hosts                                             | `toFQDNs` `matchName` (or `matchPattern`), with ports                                                                                                   |
| Any URL (crawlers, media servers, renderers)                     | `toCIDRSet` `cidrGroupRef: internet` (public space only), ports optional                                                                                |

Rules for finding the destinations:

- Build the list from the app's config, its source code (search for hardcoded URLs and HTTP clients) and its settings in the database, then compare with kguardian (`get_pod_network_traffic`) for an existing pod. kguardian can miss flows.
- Prefer switching off update checks, telemetry and analytics (env var or setting) over allowing their hosts; say in the comment that they stay blocked.
- Check redirects with a real `GET` (`curl -s -o /dev/null -r 0-0 -D - <url>`), never `curl -I`: downloads often redirect to a CDN on another host, and `HEAD` can hide that (MaxMind → Cloudflare R2, Hugging Face → `us.aws.cdn.hf.co`).
- In `matchPattern`, `*.` matches exactly one label; use `**.example.com` for CDN hosts at any depth.
- Multicast with TTL 1 (SSDP to `239.255.255.250:1900`, mDNS) dies on the node anyway, but under a policy it becomes a policy drop. Allow it explicitly if the app sends it regularly (see `media/plex`).

Document the policy: a bullet in the policy list on `docs/content/infrastructure/networking/index.md` and, for anything non-obvious (blocked features, hosts that need a rule when a feature is switched on), a line in the app's section of `docs/content/platforms/kubernetes/app-notes.md`.

## Step 3: Register in the namespace kustomization

Add `./<app>/ks.yaml` to `kubernetes/apps/<namespace>/kustomization.yaml` `resources`, in alphabetical position among the app entries (`namespace.yaml` stays first; leave existing entries where they are).

**New namespace?** Create `kubernetes/apps/<namespace>/` with a `namespace.yaml` and `kustomization.yaml` copied from an existing namespace (e.g. `selfhosted`) — keep the `alerts` component and the literal `name: _` in namespace.yaml (kustomize renames it) — and register the directory in `kubernetes/clusters/main`'s apps kustomization if namespaces are listed there.

## Step 4: Verify

```bash
kustomize build kubernetes/apps/<namespace>/<app>/app   # must render; ${APP} vars staying literal is expected
yamllint --config-file .yamllint.yaml kubernetes/apps/<namespace>/<app>
kustomize build kubernetes/apps/<namespace>/<app>/app | yq 'select(.kind=="CiliumNetworkPolicy")' | kubectl apply -n <namespace> --dry-run=server -f -
```

After the rollout, check `CiliumEgressPolicyDenied` and test the allowed destinations from inside the pod. Don't test blocked ones: every blocked attempt fires the critical alert. A drop or two within a minute of a policy first being applied, then none, is Cilium's DNS proxy taking over port 53, not a missing rule; a pod that fails its first start on a new `toFQDNs` rule usually gets through on a restart.

Then run `just docs apps` and, in the new row on `docs/content/platforms/kubernetes/applications.md`, replace the `TODO` purpose with a short description and set Upstream to `[owner/repo](https://github.com/owner/repo)` of the project. A new namespace must first be added to `PLATFORM` or `WORKLOADS` in `scripts/docs-applications.py`. The `docs-apps` pre-commit hook fails until this is done.

Show the user the created files and get confirmation before committing. Commit style: `feat(<app>): deploy`.

## Common mistakes

- **Copying a chart version or image tag from this skill or memory** — always read the current version from the repo (Step 2 command) and upstream.
- **Leaving the image tag without a digest** — pin `<tag>@sha256:<digest>`, looked up from the registry (see the HelmRelease template).
- **Using volsync** — this repo migrated to kopiur; `components/volsync` no longer exists.
- **Forgetting `reloader.stakater.com/auto`** — without it, secret/config changes don't restart pods.
- **`readOnlyRootFilesystem: true` without a tmpfs** — apps that write to `/tmp` will crash; mount an emptyDir.
- **Skipping the sorting conventions** — HelmRelease values follow `.agents/instructions/sorting.instructions.md`.
- **A public app without an egress policy** — every `envoy-external` app gets `networkpolicy.yaml` (see above); only Gatus is exempt, on purpose.
- **Allowing `*.example.com` for a CDN** — it matches one label only; downloads that redirect to `a.b.example.com` are dropped. Use `**.example.com`.
- **Leaving `POSTGRES_BACKUP_SCHEDULE` at its default** — set it from `just k8s cron-minute <app>`.
- **Adding the `components.database/postgres: init` label for a database that already has a backup**, or leaving it in after the first backup — see the New Database runbook.
- **Adding the postgres, mariadb or dragonfly component without `dependsOn: []` in the HelmRelease** — their JSON patches append to that list, and the Kustomization build fails if it's missing.
- **Adding `wait`, `commonMetadata`, or `timeout` to `ks.yaml`** — all three are boilerplate now. Leave `wait` unset unless another Kustomization depends on this one and it has no `healthChecks` (then, and only then, `wait: true`).
