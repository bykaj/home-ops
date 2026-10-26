---
description: Incidents and major migrations, what changed because of them, and what to watch
icon: material/history
---

# History

Short write-ups of incidents and large migrations: what happened, what was
changed because of it, and what to keep an eye on. Small, repeatable problems
go in the [knowledge base](../troubleshooting/index.md) instead.

## Incidents

| Date | Incident | Impact |
| --- | --- | --- |
| 2026-09-23 | [OSD NVMe failure and Ceph rebuild](2026-09-ceph-nvme-failure.md) | Degraded Ceph pool, stuck volumes, then a planned full rebuild |
| 2026-10-15 | [etcd fragmentation](2026-10-etcd-fragmentation.md) | Recurring alert, no outage |
| 2026-10-21 | [LiteLLM 1.107.0 compromise](2026-10-litellm-compromise.md) | Compromised image ran for about 5 hours; keys rotated |

## Migrations

| Date | Migration |
| --- | --- |
| 2026-10-16 | [Cilium 1.20 and Spegel 0.8](2026-10-cilium-1-20.md) |
| 2026-10-18 | [Authentik to Pocket ID](2026-10-pocket-id.md) |

## Writing one up

Name the file `<yyyy>-<mm>-<slug>.md` and use the same sections: a summary,
then Timeline, Cause, What changed and What to watch. Link the PRs. Add it to
the tables above and to the `nav` in `docs/zensical.toml`.
