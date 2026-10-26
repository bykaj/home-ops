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

[doc('Manual database backup')]
db-backup ns app:
    backup=$(kubectl create -o name -f - <<EOF
    apiVersion: postgresql.cnpg.io/v1
    kind: Backup
    metadata: { generateName: {{ app }}-postgres-manual-, namespace: {{ ns }} }
    spec: { cluster: { name: {{ app }}-postgres }, method: plugin, pluginConfiguration: { name: barman-cloud.cloudnative-pg.io } }
    EOF
    )
    just log info "Backup started" "backup" "$backup"

[doc('Debug a node')]
debug-node node:
    trap 'kubectl delete pod -n default -l app.kubernetes.io/managed-by=kubectl-debug --field-selector spec.nodeName={{ node }} --ignore-not-found --wait=false' EXIT
    kubectl debug node/{{ node }} -n default -it --image=docker.io/library/alpine:latest --profile=sysadmin

[doc('Delete local Flux Kustomization')]
delete-ks ns ks:
    just k8s render-local-ks "{{ ns }}" "{{ ks }}" | kubectl delete -f -

[doc('Prune pods in Failed, Pending, or Succeeded state')]
prune-pods:
    for phase in Failed Pending Succeeded; do
        kubectl delete pods -A --field-selector status.phase="$phase" --ignore-not-found=true
    done

[doc('Manual Kopiur backup of a volume, waits for it to finish')]
pvc-backup ns app:
    snapshot=$(kubectl create -o name -f - <<EOF
    apiVersion: kopiur.home-operations.com/v1alpha1
    kind: Snapshot
    metadata: { generateName: {{ app }}-manual-, namespace: {{ ns }} }
    spec: { policyRef: { name: {{ app }} } }
    EOF
    )
    just log info "Waiting for snapshot" "snapshot" "$snapshot"
    for _ in $(seq 360); do
      phase=$(kubectl -n {{ ns }} get "$snapshot" -o jsonpath='{.status.phase}')
      case "$phase" in
        Succeeded|Unchanged) just log info "Snapshot done" "snapshot" "$snapshot" "phase" "$phase"; exit 0 ;;
        Failed) just log error "Snapshot failed" "snapshot" "$snapshot"; exit 1 ;;
      esac
      sleep 5
    done
    just log error "Timed out after 30 minutes" "snapshot" "$snapshot" "phase" "$phase"
    exit 1

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
