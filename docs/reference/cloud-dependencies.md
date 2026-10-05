---
description: External services the platform relies on, and why they stay external
---

# Cloud Dependencies

Most of the platform is self-hosted, but a few key pieces deliberately live in
the cloud:

| Service | Used for |
| --- | --- |
| [1Password](https://1password.com) | Password management, and the source of every secret (External Secrets, doco-cd, `op inject`) |
| [Cloudflare](https://www.cloudflare.com) | Public DNS, the Zero Trust tunnel, DNS-01 for certificates, and hosting the CRD schemas |
| [GitHub](https://github.com) | This repository, Actions CI, and GitHub Pages for these docs |
| [Fastmail](https://www.fastmail.com) | Email |
| [Pushover](https://pushover.net) | Alert and app notifications |
| [Backblaze B2](https://www.backblaze.com) | Off-site S3 object storage for apps and backups, including the [nightly copy of the Kopia repository](../storage/backups.md#off-site-copy) |

These stay external to avoid three problems:

1. **Chicken-and-egg**: dependencies that would prevent bootstrapping, for
   example secrets for the thing that serves secrets.
2. **Critical availability**: services that are needed whether or not the
   cluster is up.
3. **The "hit by a bus" factor**: email, passwords and photos must stay
   accessible to family and friends without anyone keeping a cluster alive.
