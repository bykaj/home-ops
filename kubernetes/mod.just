set default-list
set default-script
set quiet
set script-interpreter := ['bash', '-euo', 'pipefail']
set shell := ['bash', '-euo', 'pipefail', '-c']

[doc('Apply local Flux Kustomization')]
apply-ks ns ks:
    just k8s render-local-ks "{{ ns }}" "{{ ks }}" | kubectl apply --server-side --force-conflicts --field-manager=kustomize-controller -f -

[doc('Browse a PVC')]
browse-pvc ns claim:
    kubectl run -n {{ ns }} browse-pvc-{{ claim }} -it --rm --restart=Never \
        --image=docker.io/library/alpine:latest \
        --overrides='{"spec":{"containers":[{"name":"browse-pvc-{{ claim }}","image":"docker.io/library/alpine:latest","stdin":true,"tty":true,"command":["/bin/sh"],"workingDir":"/mnt","volumeMounts":[{"mountPath":"/mnt","name":"data"}]}],"volumes":[{"name":"data","persistentVolumeClaim":{"claimName":"{{ claim }}"}}]}}'

[doc('Derive a stable cron minute (0-59) from an app name, used for POSTGRES_BACKUP_SCHEDULE')]
cron-minute name:
    echo $(( $(echo -n "{{ name }}" | cksum | cut -d' ' -f1) % 60 ))

[doc('Manual database base backup (CNPG and/or MariaDB, whichever the app has)')]
db-backup ns app:
    found=false
    if kubectl get clusters.postgresql.cnpg.io -n "{{ ns }}" "{{ app }}-postgres" >/dev/null 2>&1; then
        backup=$(echo '{"apiVersion": "postgresql.cnpg.io/v1", "kind": "Backup",
            "metadata": {"generateName": "{{ app }}-postgres-manual-", "namespace": "{{ ns }}"},
            "spec": {"cluster": {"name": "{{ app }}-postgres"}, "method": "plugin",
            "pluginConfiguration": {"name": "barman-cloud.cloudnative-pg.io"}}}' | kubectl create -o name -f -)
        just log info "Backup started" "backup" "$backup"
        found=true
    fi
    if kubectl get mariadbs.k8s.mariadb.com -n "{{ ns }}" "{{ app }}-mariadb" >/dev/null 2>&1; then
        # The scheduled PhysicalBackup of the current timeline; a new onDemand value runs it once
        physicalbackup=$(kubectl get pointintimerecoveries.k8s.mariadb.com -n "{{ ns }}" "{{ app }}-mariadb" \
            -o jsonpath='{.spec.physicalBackupRef.name}')
        kubectl patch physicalbackups.k8s.mariadb.com -n "{{ ns }}" "$physicalbackup" --type merge \
            -p "{\"spec\": {\"schedule\": {\"onDemand\": \"$(date +%s)\"}}}" >/dev/null
        just log info "Backup started" "physicalbackup" "$physicalbackup"
        found=true
    fi
    if [[ "$found" == false ]]; then
        just log error "No CNPG cluster or MariaDB found" "namespace" "{{ ns }}" "app" "{{ app }}"
        exit 1
    fi

[doc('Debug a node')]
debug-node node:
    trap 'kubectl delete pod -n default -l app.kubernetes.io/managed-by=kubectl-debug --field-selector spec.nodeName={{ node }} --ignore-not-found --wait=false' EXIT
    kubectl debug node/{{ node }} -n default -it --image=docker.io/library/alpine:latest --profile=sysadmin

[doc('Delete local Flux Kustomization')]
delete-ks ns ks:
    just k8s render-local-ks "{{ ns }}" "{{ ks }}" | kubectl delete -f -

[doc('Mark a MariaDB as initialized, after removing its components.database/mariadb init label')]
mariadb-mark-initialized ns app:
    # mariadb-operator only sets Initialized and BinlogsReplayed at the end of a
    # bootstrapFrom restore. An instance created without one would otherwise
    # try to restore into its existing PVCs ("storage PVCs already exist") and
    # wait for a binlog replay that never comes, which also stops archiving,
    # scheduled base backups and User/Grant/Database reconciliation
    mdb="{{ app }}-mariadb"
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    for condition in \
        "{\"type\": \"Initialized\", \"status\": \"True\", \"reason\": \"Initialized\", \"message\": \"Initialized\"}" \
        "{\"type\": \"BinlogsReplayed\", \"status\": \"True\", \"reason\": \"ReplayBinlogsSkipped\", \"message\": \"Created empty with the init label\"}"; do
        condition=$(jq -c --arg now "$now" '. + {lastTransitionTime: $now}' <<<"$condition")
        type=$(jq -r .type <<<"$condition")
        current=$(kubectl -n "{{ ns }}" get mariadbs.k8s.mariadb.com "$mdb" -o json \
            | jq -c --arg type "$type" '[.status.conditions[]?.type] as $types
                | {index: ($types | index($type)), status: ([.status.conditions[]? | select(.type == $type)][0].status)}')
        index=$(jq -r .index <<<"$current")
        if [[ "$(jq -r .status <<<"$current")" == "True" ]]; then
            just log info "Already set" "mariadb" "$mdb" "condition" "$type"
            continue
        fi
        if [[ "$index" == "null" ]]; then
            patch="[{\"op\": \"add\", \"path\": \"/status/conditions/-\", \"value\": $condition}]"
        else
            patch="[{\"op\": \"test\", \"path\": \"/status/conditions/$index/type\", \"value\": \"$type\"},
                {\"op\": \"replace\", \"path\": \"/status/conditions/$index\", \"value\": $condition}]"
        fi
        kubectl -n "{{ ns }}" patch mariadbs.k8s.mariadb.com "$mdb" --subresource=status --type=json -p "$patch" >/dev/null
        just log info "Set condition" "mariadb" "$mdb" "condition" "$type"
    done

[doc('Prune pods in Failed, Pending, or Succeeded state')]
prune-pods:
    for phase in Failed Pending Succeeded; do
        kubectl delete pods -A --field-selector status.phase="$phase" --ignore-not-found=true
    done

[doc('Manual Kopiur backup of a volume')]
pvc-backup ns app:
    snapshot=$(kubectl create -o name -f - <<EOF
    apiVersion: kopiur.home-operations.com/v1alpha1
    kind: Snapshot
    metadata: { generateName: {{ app }}-manual-, namespace: {{ ns }} }
    spec: { policyRef: { name: {{ app }} } }
    EOF
    )
    just log info "Snapshot started" "snapshot" "$snapshot"

[arg('resource', pattern='hr|ks|gitrepo|ocirepo|es')]
[doc('Sync a resource')]
sync resource:
    kubectl get {{ resource }} --no-headers -A | while read -r ns name _; do
        kubectl -n "$ns" annotate --field-manager flux-client-side-apply --overwrite {{ resource }} "$name" \
            "force-sync=$(date +%s)" \
            "reconcile.fluxcd.io/requestedAt=$(date +%s)" \
            "reconcile.fluxcd.io/forceAt=$(date +%s)"
    done

[doc('Sync single Flux HelmRelease')]
sync-hr ns name:
    kubectl -n "{{ ns }}" annotate --field-manager flux-client-side-apply --overwrite hr "{{ name }}" reconcile.fluxcd.io/requestedAt="$(date +%s)" reconcile.fluxcd.io/forceAt="$(date +%s)"; \

[doc('Sync single Flux Kustomizations')]
sync-ks ns name:
    kubectl -n "{{ ns }}" annotate --field-manager flux-client-side-apply --overwrite ks "{{ name }}" reconcile.fluxcd.io/requestedAt="$(date +%s)"; \

[doc('Sync single ExternalSecret')]
sync-es ns name:
    kubectl -n "{{ ns }}" annotate --field-manager flux-client-side-apply --overwrite es "{{ name }}" force-sync="$(date +%s)"; \

[doc('Connect to the Rook Ceph Toolbox pod')]
toolbox:
    #!/usr/bin/env bash
    set -euo pipefail
    pod=$(kubectl get pods -n rook-ceph -l app=rook-ceph-tools -o jsonpath='{.items[0].metadata.name}')
    if [ -n "$pod" ]; then
      just log info "Connecting to pod '$pod'"
      kubectl -n rook-ceph exec -it "$pod" -- bash
    else
      just log error "No rook-ceph-tools pod found"
    fi

[doc('View a secret')]
view-secret ns secret:
    kubectl view-secret -n {{ ns }} {{ secret }}

[private]
render-local-ks ns ks:
    flate build ks --namespace "{{ ns }}" --output yaml "{{ ks }}"
