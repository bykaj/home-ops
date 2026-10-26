# Docker

Provisions Docker hosts with Ansible, one playbook per host at `<host>/bootstrap.yaml`. Once it
completes, doco-cd reconciles `docker/<host>/` and nothing here is used again until the next
provisioning.

```sh
just bootstrap docker <host>   # e.g. nas
```

See the [Bootstrap runbook](https://docs.bykaj.com/operations/runbooks/bootstrap/#docker-hosts)
([source](../../docs/content/operations/runbooks/bootstrap.md)) and the [Docker](https://docs.bykaj.com/platforms/docker/)
page ([source](../../docs/content/platforms/docker.md)).
