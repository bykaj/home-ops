---
description: Remove an app from the cluster, and clean up what Flux leaves behind
---

# Retiring an App

The reverse of [Adding an App](adding-an-app.md). Removing the app from Git
makes Flux delete its Kubernetes objects, including its volumes. Backups,
1Password items and files on the NAS stay behind, so they are cleaned up by
hand.

!!! warning "Flux deletes the app's volumes"

    Both `ceph-block` and `openebs-hostpath` use `reclaimPolicy: Delete`, so
    the app's PVCs and their data are gone once Flux prunes the app. The
    backups are what's left; take a last one first.

## Before you start

1. **Decide what to keep.** Either keep the backups, so the app can come back
   later with its data, or remove everything.
2. **Take a final backup** of every volume and database the app has. Skip
   this for a stateless app.

    - **Volumes (Kopiur)**

        Take a final snapshot:

        ```sh
        just k8s pvc-backup <namespace> <app>
        kubectl -n <namespace> get snapshot   # wait for the new snapshot's PHASE to be Succeeded
        ```

        Removing the app later deletes the `Snapshot` objects from the
        cluster, but the snapshots stay in the repository on the NAS.

    - **Database (CNPG)**

        If the app has a `<app>-postgres` cluster:

        ```sh
        just k8s db-backup <namespace> <app>
        kubectl -n <namespace> get backup   # wait for the new backup's PHASE to be completed
        ```

3. **Find everything that refers to the app**:

    ```sh
    grep -rn '<app>' kubernetes docker docs/content .renovaterc.json5
    ```

    Look in particular for `dependsOn` entries in other apps' `ks.yaml`, OIDC
    clients in Pocket ID, and Grafana dashboards or alert rules elsewhere.
    Homepage entries are annotations on the app's own route, so they go with
    it.

## The PR

1. **Remove** `./<app>/ks.yaml` from the namespace `kustomization.yaml`, and
   delete `kubernetes/apps/<namespace>/<app>/`.
2. **Remove references** found above, such as `dependsOn` in other apps.
3. **Last app in its namespace?** Delete `kubernetes/apps/<namespace>/`
   entirely (`cluster-apps` then prunes the namespace), and remove it from
   `PLATFORM` or `WORKLOADS` in `scripts/docs-applications.py`.
4. **Update the docs**: run `just docs apps` to regenerate the
   [Applications](../../platforms/kubernetes/applications.md) tables, and update any other
   page that mentions the app.
5. **Validate** with `just docs build`, and `kustomize build` on the namespace.

## What Flux and the controllers remove

After the merge, these go away without any action:

- the Flux Kustomization, the HelmRelease and everything they created,
  including PVCs, Secrets, routes and the CNPG `Cluster` with its volumes
- DNS records: both external-dns instances use `policy: sync`, so they delete
  the app's records in UniFi and Cloudflare
- the Gatus check, which is generated from the route
- the Kopiur `SnapshotPolicy`, `SnapshotSchedule` and `Snapshot` objects (the
  snapshots themselves stay in the repository; see below)

Check that the Flux Kustomization is gone with `flux get ks -A | grep <app>`.
If anything is still there, see
[KB-003](../troubleshooting/kb/003-flux-instance-no-prune.md): not every
Kustomization prunes.

## What stays behind

| What | Where | Remove it |
| --- | --- | --- |
| Kopia snapshots | The `nas` repository on the NAS, and its B2 mirror | The `Snapshot` objects in the cluster are deleted with the app, but the snapshots in the repository are kept. Delete them with Kopia against the repository if the app won't come back; the B2 mirror follows on its next sync |
| Barman base backups and WAL | Garage, `s3://postgresql/<app>/` | Retention stops with the `Cluster`, so nothing expires. Delete the prefix in Garage |
| MariaDB base backups and binlogs | Garage, `s3://mariadb/<app>/` (every `v<N>/` timeline and `replica/`) | Retention stops with the `MariaDB`, and binlogs are never pruned. Delete the prefix in Garage |
| Local database dumps | NAS, `/mnt/vault/Backups/Database` | Delete the app's files |
| 1Password items | The `Homelab` vault | Archive the app's item, and any OIDC or API credentials made for it |
| OIDC client | Pocket ID | Delete the client |
| NFS data | NAS datasets mounted by the app | Delete or archive the directory |

!!! note "Coming back later restores the old data"

    If the backups are kept, adding the app again with the same name in the
    same namespace restores them. Kopiur rediscovers the snapshots from the
    repository on the NAS (as `Snapshot` objects with `origin: discovered`),
    its `Restore` fills the new PVC from the latest one, and the CNPG `Cluster`
    bootstraps from Barman by default. For a fresh start,
    delete the backups first, or follow [New Database](new-database.md) for
    the database.

## Deleting the database backups

Delete the Garage prefix only after Flux has pruned the `Cluster` or
`MariaDB`; until then the WAL archiver or binlog agent keeps writing into it.
Use the S3 keys from the `cloudnative-pg` or `mariadb` 1Password item, list
the prefix first, and keep the trailing slash, so `<app>` doesn't also match
an app whose name starts with it:

```sh
aws s3 ls s3://postgresql/<app>/ --recursive --endpoint-url https://s3.bykaj.io --region <region>
aws s3 rm s3://postgresql/<app>/ --recursive --endpoint-url https://s3.bykaj.io --region <region>
```

Use the `mariadb` bucket for MariaDB. garage-ui at `garage.bykaj.app` can
delete the objects too. Remove the app's folder in
`/mnt/vault/Backups/Database` on the NAS as well. Deleted objects remain
recoverable for a while from the NAS backups of the Garage stack's data.

!!! warning "Fresh start: delete before redeploying"

    To bring an app back with an empty database, delete its prefix **before**
    deploying it again with the `init` label from
    [New Database](new-database.md). Without the label, the old data is
    restored. With the label but old backups in place, a new CNPG cluster
    archives into the same path as the old one (`skipEmptyWalArchiveCheck`
    doesn't stop it), so a later rebuild may recover from the wrong backups,
    and a new MariaDB never archives binlogs, because the agent only starts
    in an empty prefix.

    For MariaDB, a fresh start can keep the old backups instead: set
    `MARIADB_TIMELINE` to a number not used before, so the new instance
    archives into an empty `v<N>/` prefix. See
    [Rebuilding](../../infrastructure/storage/mariadb.md#rebuilding). CNPG has
    no equivalent, because the `serverName` is always `${APP}`.

## Retiring a domain

The reverse of [Adding a Domain](adding-a-domain.md), in **one PR**: there is
no ordering problem when removing. First move or remove every route that
still uses the domain, then remove the domain from:

- `letsencrypt-production`'s `dnsZones` in
  `cert-manager/cert-manager/app/clusterissuer.yaml`
- `domainFilters` in both external-dns HelmReleases
- the `Certificate` in `network/certificates/export/certificates.yaml`
- the `PushSecret` in `network/certificates/export/pushsecrets.yaml`
- the `ExternalSecret` in `network/certificates/import/externalsecrets.yaml`
- the ingress entries in the cloudflared `config.yaml`
- `certificateRefs` on both Gateways in `network/envoy-gateway/config/gateway.yaml`
- the zone list in [DNS](../../infrastructure/networking/dns.md)

After the merge, archive the `<domain>-tls` item in 1Password. Keep the zone
in Cloudflare if the domain may come back; adding it again then starts at
[PR 1](adding-a-domain.md#pr-1-serve-the-domain).
