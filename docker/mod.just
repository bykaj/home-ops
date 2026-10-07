set default-list
set default-script
set no-exit-message
set quiet
set script-interpreter := ['bash', '-euo', 'pipefail']
set shell := ['bash', '-euo', 'pipefail', '-c']

doco_url := 'https://doco-cd.bykaj.app'
doco_repo := 'https://github.com/bykaj/home-ops.git'

[doc('Reconcile Doco-CD on TrueNAS: poll main now and redeploy changed stacks')]
sync-stacks:
    key=$(op read 'op://Homelab/doco-cd/API_SECRET')
    just log info "Triggering doco-cd poll run" repo "{{ doco_repo }}" ref main
    resp=$(curl -fsS -m 600 -X POST "{{ doco_url }}/v1/api/poll/run?wait=true" \
        -H "x-api-key: $key" -H 'content-type: application/json' \
        --data '[{"url": "{{ doco_repo }}", "reference": "refs/heads/main"}]')
    job=$(jq -r '.job_id' <<< "$resp")
    run=$(curl -fsS -m 30 "{{ doco_url }}/v1/api/run/$job" -H "x-api-key: $key" | jq '.content')
    status=$(jq -r '.status' <<< "$run")
    stacks=$(jq -r '[.deployments[]?.stack] | join(",")' <<< "$run")
    if [ "$status" = succeeded ]; then
        just log info "Poll run $status" job "$job" stacks "$stacks"
    else
        just log error "Poll run $status" job "$job" message "$(jq -r '.message' <<< "$run")"
        exit 1
    fi

[doc('Restart the Doco-CD container on TrueNAS via Ansible')]
restart-doco-cd:
    ansible-playbook -i "{{ source_directory() }}/../ansible/inventory.yaml" "{{ source_directory() }}/.ansible/nas/restart-doco-cd.yaml" --become-password-file <(op read 'op://Homelab/truenas/TRUENAS_ADMIN_PASSWORD')
