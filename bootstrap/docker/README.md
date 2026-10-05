# Docker

Provisions the TrueNAS server with Ansible. Once it completes, doco-cd reconciles `docker/nas/` and
nothing here is used again until the next provisioning.

```sh
just bootstrap nas
```

See the [Bootstrap runbook](https://docs.bykaj.com/runbooks/bootstrap/#nas)
([source](../../docs/runbooks/bootstrap.md)) and the [Docker](https://docs.bykaj.com/docker/)
page ([source](../../docs/docker/index.md)).
