# Docker

Provisions Docker hosts with Ansible, one playbook per host at `<host>/bootstrap.yaml`. Once it
completes, doco-cd reconciles `docker/<host>/` and nothing here is used again until the next
provisioning.

```sh
just bootstrap docker <host>   # e.g. nas
```

See the [Bootstrap runbook](https://docs.bykaj.com/runbooks/bootstrap/#docker-hosts)
([source](../../docs/content/runbooks/bootstrap.md)) and the [Docker](https://docs.bykaj.com/docker/)
page ([source](../../docs/content/docker/index.md)).
