# Home Operations

!!! tip "Home-Ops: Where Hobby Meets High-Tech Infrastructure"

Documentation for my home infrastructure: a three-node bare-metal Kubernetes
cluster running [Talos Linux](https://www.talos.dev/), and a
[TrueNAS](https://www.truenas.com/) server that provides bulk storage, backups
and a handful of supporting services. Everything is declared in a single Git
repository, [bykaj/home-ops](https://github.com/bykaj/home-ops). That includes
the Kubernetes manifests, the Talos machine configs, the Docker Compose stacks,
the bootstrap tooling and these docs.

Merging to `main` is the deploy step:
[Flux](https://fluxcd.io/) reconciles the cluster and
[doco-cd](https://github.com/kimdre/doco-cd) redeploys the NAS stacks, both
immediately through webhooks, and [Renovate](https://github.com/renovatebot/renovate) opens
pull requests for every dependency in the repository.

## Where to start

<div class="grid cards" markdown>

- :material-sitemap: **[Architecture](architecture/index.md)**

    ***

    How the pieces fit together: GitOps flow, repository layout, secrets.

- :material-server: **[Hardware](hardware/index.md)**

    ***

    Cluster nodes, NAS, network gear and power.

- :material-lan: **[Networking](networking/index.md)**

    ***

    Subnets, BGP-announced VIPs, gateways and split-horizon DNS.

- :material-database: **[Storage](storage/index.md)**

    ***

    Rook-Ceph, OpenEBS, the NAS pools, PVC backups and PostgreSQL.

- :material-kubernetes: **[Kubernetes](kubernetes/index.md)**

    ***

    Talos, app layout conventions, reusable components and the app catalog.

- :material-docker: **[Docker](docker/index.md)**

    ***

    Compose stacks on the NAS, deployed by doco-cd.

- :material-book-open-variant: **[Runbooks](runbooks/index.md)**

    ***

    Bootstrap, upgrades, new databases, adding apps.

- :material-format-list-bulleted: **[Reference](reference/index.md)**

    ***

    `just` recipes, tooling, cloud dependencies, glossary.

</div>
