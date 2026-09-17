# Docker

The entire process is driven by a single command:

```sh
just bootstrap nas
```

This starts the provisioning of the TrueNAS server with Ansible. Once it completes, Doco-CD
reconciles the rest of the repository and this directory is not used again until the next
provisioning.
