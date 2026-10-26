---
description: Zot keeps using its old config after doco-cd deploys a change
---

# KB-011: Zot ignores config changes

## Symptom

After a change to `docker/nas/06-zot/config/config.json` is deployed, Zot
still behaves as before, for example new mirror paths return 404.

## Cause

`config.json` is a single-file bind mount. When doco-cd pulls a new revision,
the file is replaced with a new inode, but the running container keeps seeing
the old one. doco-cd doesn't recreate the container, because the compose file
itself didn't change.

## Fix

Restart the container on the NAS:

```sh
sudo docker restart zot
```

The image is distroless, so `docker exec` has no shell. Read the config the
container sees with:

```sh
sudo docker cp zot:/etc/zot/config.json - | tar -xO
```

## Seen

2026-10-05: adding the quay.io and registry.k8s.io mirrors
([#2721](https://github.com/bykaj/home-ops/pull/2721)).
