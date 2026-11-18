set default-list
set default-script
set lazy
set no-exit-message
set quiet
set script-interpreter := ['bash', '-euo', 'pipefail']
set shell := ['bash', '-euo', 'pipefail', '-c']

controller := `talosctl config info -o yaml | yq -r -e '.endpoints[0]'`
nodes := `talosctl config info -o yaml | yq -r -e '.nodes | join (" ")'`
configs := "kubeconfig talosconfig"

[confirm('Bootstrap cluster? [y|N]')]
[doc('Bootstrap a Talos & Kubernetes cluster end-to-end')]
cluster: nodes k8s (kubeconfig "node") base apps kubeconfig store-configs drop-helm-owners

[confirm('Bootstrap Docker host ' + host + '? [y|N]')]
[doc('Bootstrap a Docker host with Ansible (host = directory under docker/)')]
docker host:
    playbook="{{ source_directory() }}/docker/{{ host }}/bootstrap.yaml"
    if [[ ! -f "$playbook" ]]; then
        just log fatal "No bootstrap playbook for host" "host" "{{ host }}" "available" "$(basename -a "{{ source_directory() }}"/docker/*/ | xargs)"
    fi
    ansible-playbook -i "{{ source_directory() }}/../ansible/inventory.yaml" "$playbook"

[doc('Restore kubeconfig and talosconfig from 1Password')]
restore-configs:
    tmpdir="$(mktemp -d)"
    trap '/bin/rm -rf "$tmpdir"' EXIT
    for f in {{ configs }}; do
        tmp="${tmpdir}/${f}"
        section="$(just bootstrap config-section "$f")"
        if ! op read -f -o "$tmp" "op://Homelab/cluster/${section}/${f}" >/dev/null; then
            just log fatal "Failed to read from 1Password" "stage" "{{ recipe_name() }}" "file" "$f"
        fi
        dest="{{ justfile_dir() }}/${f}"
        if cmp -s "$tmp" "$dest"; then
            just log info "Already up to date" "stage" "{{ recipe_name() }}" "file" "$f" "expires" "$(just bootstrap cert-expiry "$f" "$dest")"
            continue
        fi
        if [[ -f "$dest" ]] && ! gum confirm "Overwrite the local ${f} with the copy from 1Password?"; then
            just log warn "Kept the local copy" "stage" "{{ recipe_name() }}" "file" "$f"
            continue
        fi
        chmod 600 "$tmp"
        /bin/mv -f "$tmp" "$dest"
        just log info "Restored from 1Password" "stage" "{{ recipe_name() }}" "file" "$f" "expires" "$(just bootstrap cert-expiry "$f" "$dest")"
    done

[doc('Store kubeconfig and talosconfig (or only the files given) with their expiry dates, and the earliest as next expiry, in 1Password')]
store-configs *files=configs:
    for f in {{ files }}; do
        src="{{ justfile_dir() }}/${f}"
        if [[ ! -f "$src" ]]; then
            just log fatal "Local file missing" "stage" "{{ recipe_name() }}" "file" "$f"
        fi
        section="$(just bootstrap config-section "$f")"
        expires="$(just bootstrap cert-expiry "$f" "$src")"
        # Date fields read back as a Unix timestamp, so compare the local date
        stored="$(op read "op://Homelab/cluster/${section}/expires" 2>/dev/null | jq -rR 'tonumber? | localtime | strftime("%Y-%m-%d")' || true)"
        if [[ "$stored" == "$expires" ]] && cmp -s "$src" <(op read "op://Homelab/cluster/${section}/${f}" 2>/dev/null); then
            just log info "Already up to date" "stage" "{{ recipe_name() }}" "file" "$f" "expires" "$expires"
            continue
        fi
        if ! op item edit cluster --vault Homelab "${section}.${f}[file]=${src}" "${section}.expires[date]=${expires}" >/dev/null; then
            just log fatal "Failed to store in 1Password" "stage" "{{ recipe_name() }}" "file" "$f"
        fi
        just log info "Stored in 1Password" "stage" "{{ recipe_name() }}" "file" "$f" "expires" "$expires"
    done
    # 1Password allows one expiry alert per item, so `next expiry` holds the earliest section date
    next="$(for f in {{ configs }}; do op read "op://Homelab/cluster/$(just bootstrap config-section "$f")/expires" 2>/dev/null || true; done \
        | jq -rRs 'split("\n") | map(tonumber?) | min | if . then localtime | strftime("%Y-%m-%d") else empty end')"
    current="$(op read "op://Homelab/cluster/next expiry" 2>/dev/null | jq -rR 'tonumber? | localtime | strftime("%Y-%m-%d")' || true)"
    if [[ -z "$next" || "$next" == "$current" ]]; then
        just log info "Next expiry already up to date" "stage" "{{ recipe_name() }}" "expires" "${current:-none}"
    elif ! op item edit cluster --vault Homelab "next expiry[date]=${next}" >/dev/null; then
        just log fatal "Failed to store next expiry in 1Password" "stage" "{{ recipe_name() }}"
    else
        just log info "Stored next expiry in 1Password" "stage" "{{ recipe_name() }}" "expires" "$next"
    fi

[private]
nodes:
    just log info "Running stage..." "stage" "{{ recipe_name() }}"
    for n in {{ nodes }}; do
        if ! op=$(just --yes talos apply-node "$n" --insecure 2>&1); then
            if [[ "$op" == *"certificate required"* ]]; then
                just log info "Talos already configured, skipping apply of config" "stage" "{{ recipe_name() }}" "node" "$n"
                continue
            fi
            just log fatal "Failed to apply Talos configuration" "stage" "{{ recipe_name() }}" "node" "$n" "output" "$op"
        fi
    done

[private]
k8s:
    just log info "Running stage..." "stage" "{{ recipe_name() }}"
    until op=$(talosctl -n "{{ controller }}" bootstrap 2>&1 || true) && [[ "$op" == *"AlreadyExists"* ]]; do
        just log info "Kubernetes bootstrap in progress. Retrying in 5 seconds..." "stage" "{{ recipe_name() }}"
        sleep 5
    done

[private]
kubeconfig lb="cilium":
    just log info "Running stage..." "stage" "{{ recipe_name() }}"
    if ! talosctl kubeconfig -n "{{ controller }}" -f {{ justfile_dir() }}; then
        just log fatal "Failed to fetch kubeconfig" "stage" "{{ recipe_name() }}"
    fi
    if [[ "{{ lb }}" != "cilium" ]]; then
        if ! kubectl config set-cluster main --server "https://{{ controller }}:6443"; then
            just log fatal "Failed to set kubectl cluster server address" "stage" "{{ recipe_name() }}"
        fi
    fi

[private]
base: api-ready nodes-ready
    just log info "Running stage..." "stage" "{{ recipe_name() }}"
    if ! kustomize build {{ source_directory() }}/kubernetes/kustomize/manifests | just template - | kubectl apply --server-side --force-conflicts -f -; then
        just log fatal "Failed to apply manifests" "stage" "{{ recipe_name() }}"
    fi
    if ! helmfile -f "{{ source_directory() }}/kubernetes/helmfile/crds.yaml" template -q | yq ea -r -e 'select(.kind == "CustomResourceDefinition")' | kubectl apply --server-side --force-conflicts -f -; then
        just log fatal "Failed to apply base crds" "stage" "{{ recipe_name() }}"
    fi

[private]
apps:
    just log info "Running stage..." "stage" "{{ recipe_name() }}"
    if ! helmfile -f "{{ source_directory() }}/kubernetes/helmfile/apps.yaml" sync --hide-notes; then
        just log fatal "Failed to sync helmfile" "stage" "{{ recipe_name() }}"
    fi

# Helm 4 server-side applies as field manager "helm" and has no flag to rename it; Flux applies
# as "helm-controller" and never drops the "helm" entry. Fields a later chart version stops
# rendering would then stay on the object, so remove the entry once helm-controller co-owns it.
[doc('Remove the bootstrap helmfile field manager once Flux manages the same releases')]
drop-helm-owners timeout="15m":
    just log info "Running stage..." "stage" "{{ recipe_name() }}"
    releases="$(helmfile -f "{{ source_directory() }}/kubernetes/helmfile/apps.yaml" list --output json | jq -r '.[] | "\(.namespace)/\(.name)"')"
    for r in $releases; do
        ns="${r%/*}" rel="${r#*/}"
        just log info "Waiting for HelmRelease to be Ready" "stage" "{{ recipe_name() }}" "release" "$r"
        if ! kubectl -n "$ns" wait "helmrelease/${rel}" --for=create --timeout="{{ timeout }}" >/dev/null \
            || ! kubectl -n "$ns" wait "helmrelease/${rel}" --for=condition=Ready --timeout="{{ timeout }}" >/dev/null; then
            just log fatal "HelmRelease not Ready" "stage" "{{ recipe_name() }}" "release" "$r"
        fi
        fixed=0 skipped=0
        while IFS='|' read -r api kind obj_ns name; do
            group="${api%/*}"
            [[ "$group" == "$api" ]] && group=""
            res="${kind}${group:+.${group}}"
            json="$(kubectl get "$res" "$name" -n "${obj_ns:-$ns}" --show-managed-fields -o json 2>/dev/null)" || continue
            if [[ "$(jq '.metadata.managedFields | any(.manager == "helm")' <<<"$json")" != "true" ]]; then
                continue
            fi
            if [[ "$(jq '.metadata.managedFields | any(.manager == "helm-controller")' <<<"$json")" != "true" ]]; then
                (( ++skipped ))
                continue
            fi
            # Guard each removal with a test op, so a concurrent change to managedFields fails the patch instead of removing the wrong entry
            while idx="$(jq -e '.metadata.managedFields | map(.manager) | index("helm")' <<<"$json")"; do
                kubectl patch "$res" "$name" -n "${obj_ns:-$ns}" --type=json \
                    -p "[{\"op\":\"test\",\"path\":\"/metadata/managedFields/${idx}/manager\",\"value\":\"helm\"},{\"op\":\"remove\",\"path\":\"/metadata/managedFields/${idx}\"}]" >/dev/null
                json="$(kubectl get "$res" "$name" -n "${obj_ns:-$ns}" --show-managed-fields -o json)"
            done
            (( ++fixed ))
        done < <(helm get manifest -n "$ns" "$rel" | yq -r 'select(.kind != null) | [.apiVersion, .kind, (.metadata.namespace // ""), .metadata.name] | join("|")')
        just log info "Removed helm field manager" "stage" "{{ recipe_name() }}" "release" "$r" "objects" "$fixed"
        if (( skipped > 0 )); then
            just log warn "Not yet managed by helm-controller, left as is; re-run this recipe later" "stage" "{{ recipe_name() }}" "release" "$r" "objects" "$skipped"
        fi
    done

# Wait until every apiserver answers /readyz. Helm and kubectl calls after this stage are not retried.
[private]
api-ready:
    just log info "Running stage..." "stage" "{{ recipe_name() }}"
    for n in {{ nodes }}; do
        until [[ "$(curl -ks -o /dev/null -w '%{http_code}' --connect-timeout 2 "https://${n}:6443/readyz")" == "200" ]]; do
            just log info "Waiting for kube-apiserver. Retrying in 5 seconds..." "stage" "{{ recipe_name() }}" "node" "$n"
            sleep 5
        done
    done

# Wait until every node registers as Ready=False. They only become Ready=True once the CNI is healthy.
[private]
nodes-ready:
    just log info "Running stage..." "stage" "{{ recipe_name() }}"
    if ! kubectl wait nodes --for=condition=Ready=True --all --timeout=10s &>/dev/null; then
        until kubectl wait nodes --for=condition=Ready=False --all --timeout=10s &>/dev/null; do
            just log info "Nodes not available, waiting for nodes to be available. Retrying in 5 seconds..." "stage" "{{ recipe_name() }}"
            sleep 5
        done
    fi

# Print the expiry date (YYYY-MM-DD, UTC) of the client certificate in a kubeconfig or talosconfig
[private]
cert-expiry file path:
    case "{{ file }}" in
        kubeconfig)
            user="$(yq -r '.current-context as $ctx | .contexts[] | select(.name == $ctx) | .context.user' "{{ path }}")"
            end="$(USER_NAME="$user" yq -r '.users[] | select(.name == strenv(USER_NAME)) | .user.client-certificate-data' "{{ path }}" | base64 -d | openssl x509 -noout -enddate | cut -d= -f2)"
            python3 -c 'import sys, datetime; print(datetime.datetime.strptime(sys.argv[1], "%b %d %H:%M:%S %Y %Z").date())' "$end"
            ;;
        talosconfig)
            talosctl --talosconfig "{{ path }}" config info -o yaml | yq -r '.certNotAfter'
            ;;
        *)
            just log fatal "Unknown config file" "file" "{{ file }}"
            ;;
    esac

# Print the section of the 1Password cluster item that holds a config file and its expiry date
[private]
config-section file:
    case "{{ file }}" in
        kubeconfig) echo Kubernetes ;;
        talosconfig) echo Talos ;;
        *) just log fatal "Unknown config file" "file" "{{ file }}" ;;
    esac
