#!/usr/bin/env bash
# LibVersion: 1.1.4
#
# Proxmox VM management functions for Talos/Kubernetes.
# Relies on:
#   - Logging functions (log_info, log_error, etc.) from the main script.
#   - VERBOSE_FLAG from the main script.
#   - run_* utility functions (run_quiet, etc.) from utils.lib.sh.
#   - Default configuration variables (DEFAULT_VM_NAME_PREFIX, CORES, RAM_MB, etc.) from main script.
#   - Option variables (CORES_OPT, RAM_MB_OPT, etc.) from main script argument parsing.

usage() {
    # Uses SCRIPT_NAME, DEFAULT_VM_NAME_PREFIX, CORES, RAM_MB from the main script's scope
    echo ""
    echo "Usage: $SCRIPT_NAME <action> [options]"
    echo ""
    echo "Actions:"
    echo "  create <VMID> [VM_NAME_SUFFIX] [create_options]"
    echo "    Creates a new Talos VM."
    echo "    VMID: A unique numeric ID for the VM (e.g., 9001)."
    echo "    VM_NAME_SUFFIX (optional): Suffix for VM name (e.g., 'master-1'). Defaults to 'node'."
    echo "                           Full name will be ${DEFAULT_VM_NAME_PREFIX}-<VM_NAME_SUFFIX>"
    echo "  destroy <VMID[,VMID,...]>"
    echo "    Stops and destroys existing VM(s). Supports multiple VMIDs separated by commas."
    echo "  start <VMID[,VMID,...]>"
    echo "    Starts stopped VM(s). Supports multiple VMIDs separated by commas."
    echo "  stop <VMID[,VMID,...]>"
    echo "    Stops running VM(s) (gracefully, then force if needed). Supports multiple VMIDs."
    echo "  shutdown <VMID[,VMID,...]>"
    echo "    Attempts to gracefully shut down VM(s) via QEMU guest agent,"
    echo "    then falls back to stop if agent command fails or times out."
    echo "  restart <VMID[,VMID,...]>"
    echo "    Stops and then starts VM(s) (host-level restart). Supports multiple VMIDs."
    echo "  reboot <VMID[,VMID,...]>"
    echo "    Attempts to reboot VM(s) via QEMU guest agent (guest OS reboot)."
    echo "  mount <VMID> --iso=<ISO_NAME> [--storage-iso=<STORAGE>]"
    echo "    Mounts an ISO image to the VM's IDE2 interface."
    echo "  unmount <VMID[,VMID,...]>"
    echo "    Unmounts any ISO image from the VM(s) IDE2 interface."
    echo "  list-iso"
    echo "    Lists all available ISO storages and their contents."
    echo "  update"
    echo "    Checks for script updates (main script and libraries) and prompts to install."
    echo "  version | --version"
    echo "    Shows the script and library versions."
    echo ""
    echo "Create Options:"
    echo "  --cores=<N>             Number of CPU cores (default: $CORES)"
    echo "  --sockets=<N>           Number of CPU sockets (default: $SOCKETS)"
    echo "  --ram=<MB>              RAM in MB (default: $RAM_MB, min: 512)"
    echo "  --iso=<ISO_NAME>        Specific ISO file to mount (e.g., talos-v1.6.0-amd64.iso)"
    echo "  --storage-iso=<STORAGE> Storage pool for ISO (defaults to 'local' if --iso is used without it)"
    echo "  --storage-os=<STORAGE>  Storage pool for OS disk (default: $STORAGE_POOL_OS)"
    echo "  --storage-data=<STORAGE> Storage pool for data disk (default: $STORAGE_POOL_DATA)"
    echo "  --vlan=<VLAN_ID>        VLAN tag for network interface (1-4094)"
    echo "  --mac-address=<MAC>     Specific MAC address for network interface (format: XX:XX:XX:XX:XX:XX)"
    echo "  --force                 Delete existing VM with same VMID before creating"
    echo "  --start                 Automatically start the VM after creation"
    echo ""
    echo "Global Options:"
    echo "  --verbose               Show detailed output during operations"
    echo ""
    echo "Examples:"
    echo "  $SCRIPT_NAME create 9001 master-1"
    echo "  $SCRIPT_NAME create 9002 worker-1 --iso=talos-v1.7.0-amd64.iso --cores=2 --ram=8192 --start"
    echo "  $SCRIPT_NAME create 9003 worker-2 --iso=custom.iso --storage-iso=nfs-iso --vlan=100"
    echo "  $SCRIPT_NAME create 9004 worker-3 --force --storage-os=local-zfs --storage-data=local-zfs --start"
    echo "  $SCRIPT_NAME create 9005 worker-4 --mac-address=02:00:00:00:00:01 --vlan=100"
    echo "  $SCRIPT_NAME destroy 9001"
    echo "  $SCRIPT_NAME destroy 9001,9002,9003"
    echo "  $SCRIPT_NAME start 9001,9002"
    echo "  $SCRIPT_NAME stop 9001,9002,9003"
    echo "  $SCRIPT_NAME restart 9001,9002"
    echo "  $SCRIPT_NAME mount 9001 --iso=talos-v1.7.0-amd64.iso"
    echo "  $SCRIPT_NAME mount 9002 --iso=custom.iso --storage-iso=nfs-iso"
    echo "  $SCRIPT_NAME unmount 9001"
    echo "  $SCRIPT_NAME unmount 9001,9002,9003"
    echo "  $SCRIPT_NAME list-iso"
    echo "  $SCRIPT_NAME update --verbose"
    # This function is typically called with `usage; exit 1` from main script.
}

check_vmid_exists() {
    local vmid=$1
    if qm status "$vmid" >/dev/null 2>&1; then
        return 0 # Exists
    else
        return 1 # Does not exist
    fi
}

# Get VM information from cluster
get_vm_info() {
    local vmid=$1
    local vm_info

    log_verbose "Querying cluster for VM $vmid information..."

    # Get cluster resources and filter for the specific VMID
    if ! vm_info=$(pvesh get /cluster/resources --type vm --output json 2>/dev/null | jq -r ".[] | select(.vmid == $vmid)"); then
        log_verbose "Failed to query cluster resources for VM $vmid"
        return 1
    fi

    if [[ -z "$vm_info" || "$vm_info" == "null" ]]; then
        log_verbose "VM $vmid not found in cluster"
        return 1
    fi

    echo "$vm_info"
    return 0
}

# Get the node where a VM is located
get_vm_node() {
    local vmid=$1
    local vm_info node_name

    if ! vm_info=$(get_vm_info "$vmid"); then
        return 1
    fi

    node_name=$(echo "$vm_info" | jq -r '.node')
    if [[ -z "$node_name" || "$node_name" == "null" ]]; then
        log_verbose "Could not determine node for VM $vmid"
        return 1
    fi

    echo "$node_name"
    return 0
}

# Get current node name
get_current_node() {
    local current_node
    if ! current_node=$(hostname); then
        log_verbose "Failed to get current hostname"
        return 1
    fi
    echo "$current_node"
    return 0
}

# Check if VM exists locally or on remote node
check_vmid_exists_cluster() {
    local vmid=$1
    local vm_info

    # First try local check for performance
    if qm status "$vmid" >/dev/null 2>&1; then
        return 0 # Exists locally
    fi

    # Check cluster-wide
    if vm_info=$(get_vm_info "$vmid"); then
        return 0 # Exists somewhere in cluster
    else
        return 1 # Does not exist
    fi
}

# Execute command on remote node if VM is not local
execute_vm_command() {
    local vmid=$1
    local script_content="$2"
    shift 2
    local script_args=("$@")
    local vm_node current_node

    # Get current node
    if ! current_node=$(get_current_node); then
        log_error "Failed to determine current node"
        return 1
    fi

    # Check if VM exists locally first
    if qm status "$vmid" >/dev/null 2>&1; then
        log_verbose "VM $vmid found locally, executing command locally"
        bash -c "$script_content" -- "${script_args[@]}"
        return $?
    fi

    # Get VM node from cluster
    if ! vm_node=$(get_vm_node "$vmid"); then
        log_error "VM $vmid not found in cluster"
        return 1
    fi

    if [[ "$vm_node" == "$current_node" ]]; then
        # Should not happen since we checked locally first, but just in case
        log_verbose "VM $vmid should be local but wasn't found locally"
        bash -c "$script_content" -- "${script_args[@]}"
        return $?
    else
        log_info "VM $vmid is on node '$vm_node', executing command remotely via SSH..."
        log_verbose "Executing script on $vm_node with args: ${script_args[*]}"

        # Create a properly escaped command for SSH
        local ssh_command="bash -c $(printf '%q' "$script_content") --"
        for arg in "${script_args[@]}"; do
            ssh_command+=" $(printf '%q' "$arg")"
        done

        # Execute command on remote node via SSH
        if ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no "root@$vm_node" "$ssh_command"; then
            return 0
        else
            log_error "Failed to execute command on remote node '$vm_node'"
            return 1
        fi
    fi
}

is_vm_running() {
    local vmid=$1
    if qm status "$vmid" 2>/dev/null | grep -q "status: running"; then
        return 0 # Running
    else
        return 1 # Not running
    fi
}

create_vm() {
    local vmid=$1
    local vm_name_suffix=${2:-node}
    local vm_name="${DEFAULT_VM_NAME_PREFIX}-${vm_name_suffix}"

    # Handle MAC address prompt BEFORE potentially destroying existing VM
    local mac_address_to_use=""
    if [[ -n "${MAC_ADDRESS_OPT:-}" ]]; then
        mac_address_to_use="$MAC_ADDRESS_OPT"
        log_verbose "Using custom MAC address: $mac_address_to_use"
    else
        # If VM exists and we're forcing, show its current MAC address for convenience
        if check_vmid_exists_cluster "$vmid" && [[ "${FORCE_FLAG_OPT:-false}" == "true" ]]; then
            local existing_mac
            existing_mac=$(execute_vm_command "$vmid" "qm config \$1 | grep '^net0:' | grep -o -E '([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}'" "$vmid" 2>/dev/null || echo "N/A")
            if [[ "$existing_mac" != "N/A" ]]; then
                log_info "Existing VM $vmid MAC address: $existing_mac"
            fi
        fi

        log_info "No MAC address specified. A random MAC address will be generated."
        read -r -p "Continue with random MAC address? (Y/n): " mac_choice
        if [[ "$mac_choice" =~ ^[Nn]$ ]]; then
            log_info "VM creation aborted. Specify a MAC address with --mac-address=XX:XX:XX:XX:XX:XX"
            return 1
        fi
        log_info "Proceeding with random MAC address generation..."
    fi

    # Now handle existing VM after MAC address decision is made
    if check_vmid_exists_cluster "$vmid"; then
        if [[ "${FORCE_FLAG_OPT:-false}" == "true" ]]; then
            log_warning "VM $vmid already exists. Force flag enabled - deleting existing VM first..."
            local force_destroy_script=$(cat << 'EOF'
vmid=$1
log_verbose() { if [[ "${VERBOSE_FLAG:-false}" == "true" ]]; then echo "🔍 $*" >&2; fi; }

log_verbose "Force destroying VM $vmid..."
qm stop "$vmid" --timeout 10 >/dev/null 2>&1 || true
for _ in {1..3}; do
    if ! qm status "$vmid" 2>/dev/null | grep -q "status: running"; then
        break
    fi
    sleep 1
done
qm stop "$vmid" --force >/dev/null 2>&1 || true
sleep 1
qm unlock "$vmid" >/dev/null 2>&1 || true
qm destroy "$vmid" --purge >/dev/null 2>&1 || true
EOF
)
            if execute_vm_command "$vmid" "$force_destroy_script" "$vmid"; then
                log_success "Existing VM $vmid deleted. Proceeding with creation..."
            else
                log_error "Failed to delete existing VM $vmid. Aborting creation."
                return 1
            fi
        else
            log_error "VMID $vmid already exists. Use '--force' flag or choose different VMID."
            return 1
        fi
    fi

    log_info "Creating VM $vmid ($vm_name)..."

    local actual_cores="${CORES_OPT:-$CORES}"
    local actual_sockets="${SOCKETS_OPT:-$SOCKETS}"
    local actual_ram_mb="${RAM_MB_OPT:-$RAM_MB}"
    log_verbose "VM resources: Cores=$actual_cores, Sockets=$actual_sockets, RAM=${actual_ram_mb}MB"

    local iso_path actual_iso_storage
    if [[ -n "${ISO_NAME_OPT:-}" ]]; then
        actual_iso_storage="${STORAGE_ISO_OPT:-local}"
        iso_path="${actual_iso_storage}:iso/${ISO_NAME_OPT}"
        log_verbose "Using custom ISO: $iso_path (from storage: $actual_iso_storage)"
    else
        iso_path="$TALOS_ISO_PATH"
        log_verbose "Using default ISO: $iso_path"
    fi

    local actual_storage_os="${STORAGE_OS_OPT:-$STORAGE_POOL_OS}"
    local actual_storage_efi="${STORAGE_EFI_OPT:-$actual_storage_os}" # Use specific EFI storage if provided, else same as OS
    local actual_storage_data="${STORAGE_DATA_OPT:-$STORAGE_POOL_DATA}"

    if [[ "$actual_storage_os" != "$STORAGE_POOL_OS" ]]; then log_verbose "Using custom OS storage: $actual_storage_os"; fi
    if [[ "$actual_storage_efi" != "$actual_storage_os" ]]; then log_verbose "Using custom EFI storage: $actual_storage_efi"; fi # Only log if different from OS
    if [[ "$actual_storage_data" != "$STORAGE_POOL_DATA" ]]; then log_verbose "Using custom data storage: $actual_storage_data"; fi

    local net_config="virtio,bridge=$NETWORK_BRIDGE,firewall=0"
    if [[ -n "$mac_address_to_use" ]]; then
        net_config="${net_config},macaddr=${mac_address_to_use}"
    fi
    if [[ -n "${VLAN_TAG_OPT:-}" ]]; then
        net_config="${net_config},tag=${VLAN_TAG_OPT}"
        log_verbose "Using VLAN tag: $VLAN_TAG_OPT"
    fi

    log_verbose "Creating VM with basic settings using 'qm create'..."
    run_critical qm create "$vmid" \
        --name "$vm_name" --ostype "$OS_TYPE" --machine "$MACHINE_TYPE" --bios "$BIOS_TYPE" \
        --cpu host --cores "$actual_cores" --sockets "$actual_sockets" --numa 1 \
        --memory "$actual_ram_mb" --balloon 0 --onboot 1 --net0 "$net_config"

    log_verbose "Adding EFI disk to storage '$actual_storage_efi'..."
    run_with_warnings qm set "$vmid" --efidisk0 "${actual_storage_efi}:0,efitype=4m,pre-enrolled-keys=0"
    log_verbose "Adding SCSI controller (virtio-scsi-pci)..."
    run_quiet qm set "$vmid" --scsihw virtio-scsi-pci
    log_verbose "Adding OS disk (${DISK_OS_SIZE_GB}GB) to storage '$actual_storage_os'..."
    run_with_warnings qm set "$vmid" --scsi0 "${actual_storage_os}:${DISK_OS_SIZE_GB},ssd=1"
    log_verbose "Adding data disk (${DISK_DATA_SIZE_GB}GB) to storage '$actual_storage_data'..."
    run_with_warnings qm set "$vmid" --scsi1 "${actual_storage_data}:${DISK_DATA_SIZE_GB},ssd=1"
    log_verbose "Mounting ISO: $iso_path"
    run_critical qm set "$vmid" --ide2 "$iso_path,media=cdrom"
    log_verbose "Setting boot order: ide2 (ISO), then scsi0 (OS Disk)..."
    run_quiet qm set "$vmid" --boot order="ide2;scsi0"
    log_verbose "Adding serial console and setting VGA to $VGA_TYPE..."
    run_quiet qm set "$vmid" --serial0 socket --vga "$VGA_TYPE"
    log_verbose "Enabling QEMU Guest Agent..."
    run_quiet qm set "$vmid" --agent enabled=1

    log_success "VM $vmid ($vm_name) created successfully!"
    if [[ "${VERBOSE_FLAG:-false}" == "true" ]]; then echo; log_verbose "VM Configuration:"; qm config "$vmid"; echo; fi

    # Always retrieve and display MAC address
    local actual_mac_address
    actual_mac_address=$(qm config "$vmid" | grep "^net0:" | grep -o -E '([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}' 2>/dev/null || echo "N/A")
    if [[ -n "$mac_address_to_use" ]]; then
        log_info "VM $vmid MAC address: $actual_mac_address (user-specified)"
    else
        log_info "VM $vmid MAC address: $actual_mac_address (randomly generated)"
    fi

    if [[ "${START_FLAG_OPT:-false}" == "true" ]]; then
        log_info "Starting VM $vmid (--start flag provided)..."
        if run_with_output qm start "$vmid"; then
            log_success "VM $vmid started successfully!"
            wait_for_vm_online "$vmid"
        else
            log_error "Failed to start VM $vmid. Check Proxmox task logs."
            return 1
        fi
        log_warning "After Talos install, remember to:"
        log_warning "  - Eject ISO         : 'qm set $vmid --ide2 none'"
        log_warning "  - Adjust boot order : 'qm set $vmid --boot order=scsi0'"
    else
        log_info "VM $vmid created but not started (use --start flag to auto-start)."
        log_info "To start manually: qm start $vmid"
        log_warning "Remember to eject ISO ('qm set $vmid --ide2 none') and adjust boot order after Talos install."
    fi
    return 0
}

destroy_vm() {
    local vmid=$1
    if ! check_vmid_exists_cluster "$vmid"; then
        log_warning "VMID $vmid does not exist. Nothing to destroy."
        return 0
    fi

    log_info "Attempting to destroy VM $vmid..."
    read -r -p "ARE YOU SURE to PERMANENTLY destroy VM $vmid and its disks? (yes/NO): " conf
    if [[ "$conf" != "yes" ]]; then log_info "Destruction aborted."; return 0; fi

    # Execute the destruction on the appropriate node
    local destroy_script=$(cat << 'EOF'
vmid=$1
log_info() { echo "ℹ️  $*"; }
log_success() { echo "✅ $*"; }
log_warning() { echo "⚠️  $*" >&2; }
log_error() { echo "❌ $*" >&2; }
log_verbose() { if [[ "${VERBOSE_FLAG:-false}" == "true" ]]; then echo "🔍 $*" >&2; fi; }

log_info "Stopping VM $vmid (if running)..."
qm stop "$vmid" --timeout 30 || log_verbose "VM $vmid not running or stop timed out."

for i in {1..5}; do
    if ! qm status "$vmid" 2>/dev/null | grep -q "status: running"; then
        log_verbose "VM $vmid is stopped."; break;
    fi
    log_verbose "Waiting for VM $vmid to stop... ($i/5)"; sleep 2
done

if qm status "$vmid" 2>/dev/null | grep -q "status: running"; then
     log_warning "VM $vmid still running. Attempting force stop."
     qm stop "$vmid" --force || log_verbose "Force stop issued."
     sleep 3
fi

log_info "Destroying VM $vmid and its disks..."
if qm destroy "$vmid" --purge; then
    log_success "VM $vmid destroyed."
else
    log_warning "Failed to destroy VM $vmid. Attempting unlock and retry..."
    qm unlock "$vmid" || log_verbose "Unlock issued for VM $vmid."
    if qm destroy "$vmid" --purge; then
        log_success "VM $vmid destroyed on retry."
    else
        log_error "Still failed to destroy VM $vmid. Manual intervention may be required."
        exit 1
    fi
fi
EOF
)

    if execute_vm_command "$vmid" "$destroy_script" "$vmid"; then
        log_success "VM $vmid destruction completed."
        return 0
    else
        log_error "Failed to destroy VM $vmid"
        return 1
    fi
}

force_destroy_vm() {
    local vmid=$1
    if ! check_vmid_exists "$vmid"; then log_verbose "VM $vmid non-existent, nothing to force destroy."; return 0; fi

    log_verbose "Force destroying VM $vmid..."
    qm stop "$vmid" --timeout 10 >/dev/null 2>&1 || true
    for _ in {1..3}; do if ! is_vm_running "$vmid"; then break; fi; sleep 1; done
    if is_vm_running "$vmid"; then qm stop "$vmid" --force >/dev/null 2>&1 || true; sleep 2; fi

    if qm destroy "$vmid" --purge >/dev/null 2>&1; then
        log_verbose "VM $vmid force-destroyed."
        return 0
    else
        qm unlock "$vmid" >/dev/null 2>&1 || true
        if qm destroy "$vmid" --purge >/dev/null 2>&1; then
            log_verbose "VM $vmid force-destroyed on retry after unlock."
            return 0
        else
            return 1 # Caller (create_vm) will log error
        fi
    fi
}

stop_vm() {
    local vmid=$1
    if ! check_vmid_exists_cluster "$vmid"; then log_warning "VM $vmid does not exist."; return 1; fi

    local stop_script=$(cat << 'EOF'
vmid=$1
log_info() { echo "ℹ️  $*"; }
log_success() { echo "✅ $*"; }
log_warning() { echo "⚠️  $*" >&2; }
log_error() { echo "❌ $*" >&2; }
log_verbose() { if [[ "${VERBOSE_FLAG:-false}" == "true" ]]; then echo "🔍 $*" >&2; fi; }

if ! qm status "$vmid" 2>/dev/null | grep -q "status: running"; then
    log_info "VM $vmid is already stopped."
    exit 0
fi

log_info "Attempting graceful stop for VM $vmid..."
if qm stop "$vmid" --timeout 60; then
    log_success "VM $vmid stopped."
    exit 0
fi

log_warning "Graceful stop failed or timed out."
if ! qm status "$vmid" 2>/dev/null | grep -q "status: running"; then
    log_success "VM $vmid now stopped (after timeout)."
    exit 0
fi

log_info "Attempting force stop for VM $vmid..."
if qm stop "$vmid" --force; then
    log_success "VM $vmid forcibly stopped."
else
    if ! qm status "$vmid" 2>/dev/null | grep -q "status: running"; then
        log_success "VM $vmid now stopped (after force attempt)."
        exit 0
    fi
    log_error "Failed to stop VM $vmid even with force."
    exit 1
fi
EOF
)

    execute_vm_command "$vmid" "$stop_script" "$vmid"
    return $?
}

shutdown_vm() {
    local vmid=$1
    if ! check_vmid_exists_cluster "$vmid"; then log_warning "VM $vmid does not exist."; return 1; fi

    local shutdown_script=$(cat << 'EOF'
vmid=$1
log_info() { echo "ℹ️  $*"; }
log_success() { echo "✅ $*"; }
log_warning() { echo "⚠️  $*" >&2; }
log_error() { echo "❌ $*" >&2; }
log_verbose() { if [[ "${VERBOSE_FLAG:-false}" == "true" ]]; then echo "🔍 $*" >&2; fi; }

if ! qm status "$vmid" 2>/dev/null | grep -q "status: running"; then
    log_info "VM $vmid is already stopped."
    exit 0
fi

log_info "Attempting guest OS shutdown for VM $vmid via QEMU agent..."
if qm guest cmd "$vmid" ping >/dev/null 2>&1; then
    log_verbose "QEMU agent responsive. Sending shutdown..."
    if qm guest cmd "$vmid" shutdown; then
        log_info "Shutdown command sent. Waiting up to 60s for VM $vmid to power off..."
        wait_time=0
        dots=false
        while [[ $wait_time -lt 60 ]]; do
            if ! qm status "$vmid" 2>/dev/null | grep -q "status: running"; then
                if [[ "${VERBOSE_FLAG:-false}" != "true" && "$dots" == "true" ]]; then echo; fi
                log_success "VM $vmid shut down via guest agent."
                exit 0
            fi
            if [[ "${VERBOSE_FLAG:-false}" != "true" ]]; then printf "."; dots=true; fi
            log_verbose "VM $vmid still running. Waited ${wait_time}s..."
            sleep 5
            wait_time=$((wait_time + 5))
        done
        if [[ "${VERBOSE_FLAG:-false}" != "true" && "$dots" == "true" ]]; then echo; fi
        log_warning "VM $vmid did not shut down via guest agent within 60s."
    else
        log_warning "Agent ping OK, but qm guest cmd $vmid shutdown failed."
    fi
else
    log_warning "QEMU agent for VM $vmid not responding. Cannot send guest shutdown."
fi

log_info "Falling back to standard stop for VM $vmid."
# Fall back to standard stop
if qm stop "$vmid" --timeout 60; then
    log_success "VM $vmid stopped."
else
    log_warning "Graceful stop failed or timed out."
    if ! qm status "$vmid" 2>/dev/null | grep -q "status: running"; then
        log_success "VM $vmid now stopped (after timeout)."
        exit 0
    fi
    log_info "Attempting force stop for VM $vmid..."
    if qm stop "$vmid" --force; then
        log_success "VM $vmid forcibly stopped."
    else
        if ! qm status "$vmid" 2>/dev/null | grep -q "status: running"; then
            log_success "VM $vmid now stopped (after force attempt)."
            exit 0
        fi
        log_error "Failed to stop VM $vmid even with force."
        exit 1
    fi
fi
EOF
)

    execute_vm_command "$vmid" "$shutdown_script" "$vmid"
    return $?
}

restart_vm() {
    local vmid=$1
    if ! check_vmid_exists_cluster "$vmid"; then log_warning "VM $vmid does not exist."; return 1; fi

    log_info "Attempting host-level restart for VM $vmid..."

    local restart_script=$(cat << 'EOF'
vmid=$1
log_info() { echo "ℹ️  $*"; }
log_success() { echo "✅ $*"; }
log_warning() { echo "⚠️  $*" >&2; }
log_error() { echo "❌ $*" >&2; }
log_verbose() { if [[ "${VERBOSE_FLAG:-false}" == "true" ]]; then echo "🔍 $*" >&2; fi; }

if qm status "$vmid" 2>/dev/null | grep -q "status: running"; then
    log_info "VM $vmid running. Stopping it first..."
    if ! qm stop "$vmid" --timeout 60; then
        log_warning "Graceful stop failed or timed out."
        if qm status "$vmid" 2>/dev/null | grep -q "status: running"; then
            log_info "Attempting force stop for VM $vmid..."
            if ! qm stop "$vmid" --force; then
                log_error "Failed to stop VM $vmid. Aborting restart."
                exit 1
            fi
        fi
    fi
    log_verbose "VM $vmid stopped. Proceeding with start."
else
    log_info "VM $vmid not running. Will start it."
fi

log_info "Starting VM $vmid..."
if qm start "$vmid"; then
    log_success "VM $vmid started."
else
    log_error "Failed to start VM $vmid."
    exit 1
fi
EOF
)

    if execute_vm_command "$vmid" "$restart_script" "$vmid"; then
        wait_for_vm_online "$vmid"
        return 0
    else
        return 1
    fi
}

start_vm() {
    local vmid=$1
    if ! check_vmid_exists_cluster "$vmid"; then log_warning "VM $vmid does not exist."; return 1; fi

    local start_script=$(cat << 'EOF'
vmid=$1
log_info() { echo "ℹ️  $*"; }
log_success() { echo "✅ $*"; }
log_warning() { echo "⚠️  $*" >&2; }
log_error() { echo "❌ $*" >&2; }
log_verbose() { if [[ "${VERBOSE_FLAG:-false}" == "true" ]]; then echo "🔍 $*" >&2; fi; }

if qm status "$vmid" 2>/dev/null | grep -q "status: running"; then
    log_info "VM $vmid is already running."
    exit 0
fi

log_info "Starting VM $vmid..."
if qm start "$vmid"; then
    log_success "VM $vmid started."
else
    log_error "Failed to start VM $vmid."
    exit 1
fi
EOF
)

    if execute_vm_command "$vmid" "$start_script" "$vmid"; then
        wait_for_vm_online "$vmid"
        return 0
    else
        return 1
    fi
}

reboot_vm() {
    local vmid=$1
    if ! check_vmid_exists_cluster "$vmid"; then log_warning "VM $vmid does not exist."; return 1; fi

    local reboot_script=$(cat << 'EOF'
vmid=$1
log_info() { echo "ℹ️  $*"; }
log_success() { echo "✅ $*"; }
log_warning() { echo "⚠️  $*" >&2; }
log_error() { echo "❌ $*" >&2; }
log_verbose() { if [[ "${VERBOSE_FLAG:-false}" == "true" ]]; then echo "🔍 $*" >&2; fi; }

if ! qm status "$vmid" 2>/dev/null | grep -q "status: running"; then
    log_warning "VM $vmid not running. Use restart or start it first."
    exit 1
fi

log_info "Attempting guest OS reboot for VM $vmid..."
if ! qm guest cmd "$vmid" ping >/dev/null 2>&1; then
    log_warning "QEMU agent for VM $vmid not responding. Cannot send guest reboot."
    log_info "Consider restart command for host-level restart."
    exit 1
fi

log_verbose "Agent ping OK. Sending guest reboot command (via shutdown)..."
# Proxmox reboot command can be unreliable, shutdown + start is more robust.
if qm guest cmd "$vmid" shutdown; then
    log_info "Guest shutdown command sent for reboot. Waiting up to 60s..."
    wait_s=0
    timeout_s=60
    dots_s=false
    while [[ $wait_s -lt $timeout_s ]]; do
        if ! qm status "$vmid" 2>/dev/null | grep -q "status: running"; then
            if [[ "${VERBOSE_FLAG:-false}" != "true" && "$dots_s" == "true" ]]; then echo; fi
            log_success "VM $vmid shut down via agent."
            break
        fi
        if [[ "${VERBOSE_FLAG:-false}" != "true" ]]; then printf "."; dots_s=true; fi
        log_verbose "VM $vmid still running. Waited ${wait_s}s..."
        sleep 3
        wait_s=$((wait_s + 3))
    done

    if [[ $wait_s -ge $timeout_s ]]; then
        if [[ "${VERBOSE_FLAG:-false}" != "true" && "$dots_s" == "true" ]]; then echo; fi
        log_warning "VM $vmid did not shut down within ${timeout_s}s. Forcing restart..."
        qm stop "$vmid" --force || true
        sleep 2
    fi

    log_info "Starting VM $vmid after reboot..."
    if qm start "$vmid"; then
        log_success "VM $vmid reboot completed."
    else
        log_error "Failed to start VM $vmid after reboot."
        exit 1
    fi
else
    log_error "Failed to send shutdown command for reboot."
    exit 1
fi
EOF
)

    if execute_vm_command "$vmid" "$reboot_script" "$vmid"; then
        wait_for_vm_online "$vmid"
        return 0
    else
        return 1
    fi
}

list_iso_storages() {
    log_info "=== Available ISO Storages and Contents ==="; echo
    local storages
    if ! storages=$(pvesm status --content iso 2>/dev/null | tail -n +2 | awk '{print $1}'); then
        log_warning "Could not list ISO storages (pvesm status failed)."; return 1;
    fi
    if [[ -z "$storages" ]]; then log_info "No storages with ISO content found."; return 0; fi

    for storage in $storages; do
        echo "Storage: $storage"; echo "---------------------------------------"
        local storage_info; storage_info=$(pvesm status --storage "$storage" 2>/dev/null || true)
        if [[ -n "$storage_info" ]]; then
            echo "Status: $(echo "$storage_info" | tail -n +2 | awk '{print $3" ("$2")"}')"
        fi

        local iso_files; iso_files=$(pvesm list "$storage" --content iso 2>/dev/null | tail -n +2 || true)
        if [[ -n "$iso_files" ]]; then
            echo "Available ISO files:"
            echo "$iso_files" | while IFS= read -r line; do
                local volid name size format human_size=""
                volid=$(echo "$line" | awk '{print $1}')
                name=$(basename "$volid")
                size=$(echo "$line" | awk '{print $4}')
                format=$(echo "$line" | awk '{print $2}')
                if command -v numfmt >/dev/null && [[ "$size" =~ ^[0-9]+$ ]]; then
                    human_size=" ($(numfmt --to=iec-i --suffix=B --format="%.1f" "$size"))"
                fi
                echo "  - ${name} (VolID: ${volid}, Format: ${format}, Size: ${size}${human_size})"
            done
        else
            echo "  No ISO files found in this storage."
        fi; echo
    done
    return 0
}

wait_for_vm_online() {
    local vmid=$1 max_wait=300 interval=5 elapsed=0 init_msg=false dots=false

    log_info "Waiting for VM $vmid QEMU agent..."

    local wait_script=$(cat << 'EOF'
vmid=$1
max_wait=$2
interval=$3
elapsed=0
init_msg=false
dots=false

while [[ $elapsed -lt $max_wait ]]; do
    if ! qm status "$vmid" 2>/dev/null | grep -q "status: running"; then
        if [[ "${VERBOSE_FLAG:-false}" != "true" && "$init_msg" == "false" ]]; then echo -n "VM not running, waiting"; init_msg=true; fi
        if [[ "${VERBOSE_FLAG:-false}" != "true" ]]; then printf "."; dots=true; fi
        if [[ "${VERBOSE_FLAG:-false}" == "true" ]]; then echo "🔍 VM $vmid not running. Waiting..." >&2; fi
        sleep $interval
        elapsed=$((elapsed + interval))
        continue
    fi

    if ! $init_msg && [[ "${VERBOSE_FLAG:-false}" != "true" ]]; then echo -n "VM running, waiting for agent"; init_msg=true; fi

    if qm guest cmd "$vmid" ping >/dev/null 2>&1; then
        if [[ "${VERBOSE_FLAG:-false}" != "true" && "$dots" == "true" ]]; then echo; fi
        echo "✅ VM $vmid agent responding to ping!"
        exit 0
    fi

    if [[ "${VERBOSE_FLAG:-false}" != "true" ]]; then printf "."; dots=true; fi
    if [[ "${VERBOSE_FLAG:-false}" == "true" ]]; then echo "🔍 VM $vmid agent not yet responding to ping. Waiting..." >&2; fi
    sleep $interval
    elapsed=$((elapsed + interval))
done

if [[ "${VERBOSE_FLAG:-false}" != "true" && "$dots" == "true" ]]; then echo; fi
echo "⚠️  Timeout waiting for VM $vmid agent after ${max_wait}s." >&2

if qm status "$vmid" 2>/dev/null | grep -q "status: running"; then
    echo "ℹ️  VM $vmid running, but agent unresponsive."
else
    echo "ℹ️  VM $vmid not running."
fi
echo "ℹ️  Check manually: qm status $vmid / qm terminal $vmid"
exit 1
EOF
)

    execute_vm_command "$vmid" "$wait_script" "$vmid" "$max_wait" "$interval"
    return $?
}

display_vm_stats() {
    local vmid=$1
    log_info "VM Statistics ($vmid):"
    echo "┌────────────────────────────────────────────────────────────┐"

    local stats_script=$(cat << 'EOF'
vmid=$1
status=$(qm status "$vmid" | awk "{print \$2}" 2>/dev/null || echo "unknown")
mac=$(qm config "$vmid" | grep "^net0:" | grep -o -E "([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}" 2>/dev/null || echo "N/A")
node=$(hostname 2>/dev/null || echo "unknown")
printf "│ %-15s │ %-40s │\n" "Status:" "$status"
printf "│ %-15s │ %-40s │\n" "MAC Address:" "$mac"
printf "│ %-15s │ %-40s │\n" "Node:" "$node"
EOF
)

    execute_vm_command "$vmid" "$stats_script" "$vmid"
    echo "└────────────────────────────────────────────────────────────┘"
}

mount_iso() {
    local vmid=$1
    if ! check_vmid_exists_cluster "$vmid"; then
        log_error "VM $vmid does not exist."
        return 1
    fi

    # Build the ISO path
    local iso_path actual_iso_storage
    actual_iso_storage="${STORAGE_ISO_OPT:-local}"
    iso_path="${actual_iso_storage}:iso/${ISO_NAME_OPT}"

    log_info "Mounting ISO '$iso_path' to VM $vmid..."
    log_verbose "Using storage: $actual_iso_storage, ISO file: $ISO_NAME_OPT"

    local mount_script=$(cat << 'EOF'
vmid=$1
iso_path=$2
log_info() { echo "ℹ️  $*"; }
log_success() { echo "✅ $*"; }
log_warning() { echo "⚠️  $*" >&2; }
log_error() { echo "❌ $*" >&2; }
log_verbose() { if [[ "${VERBOSE_FLAG:-false}" == "true" ]]; then echo "🔍 $*" >&2; fi; }

# Check if an ISO is already mounted
current_ide2=$(qm config "$vmid" | grep "^ide2:" || true)
if [[ -n "$current_ide2" && "$current_ide2" != *"none"* ]]; then
    log_warning "VM $vmid already has IDE2 configured: $current_ide2"
    read -r -p "Replace current IDE2 configuration? (y/N): " replace_choice
    if [[ ! "$replace_choice" =~ ^[Yy]$ ]]; then
        log_info "Mount operation cancelled."
        exit 0
    fi
fi

# Mount the ISO
if qm set "$vmid" --ide2 "$iso_path,media=cdrom"; then
    log_success "ISO \"$iso_path\" mounted to VM $vmid on IDE2."

    # Show current configuration for verification
    new_ide2=$(qm config "$vmid" | grep "^ide2:" || echo "none")
    log_info "Current IDE2 configuration: $new_ide2"
else
    log_error "Failed to mount ISO \"$iso_path\" to VM $vmid."
    exit 1
fi
EOF
)

    execute_vm_command "$vmid" "$mount_script" "$vmid" "$iso_path"
    return $?
}

unmount_iso() {
    local vmid=$1
    if ! check_vmid_exists_cluster "$vmid"; then
        log_error "VM $vmid does not exist."
        return 1
    fi

    log_info "Unmounting ISO from VM $vmid..."

    local unmount_script=$(cat << 'EOF'
vmid=$1
log_info() { echo "ℹ️  $*"; }
log_success() { echo "✅ $*"; }
log_warning() { echo "⚠️  $*" >&2; }
log_error() { echo "❌ $*" >&2; }
log_verbose() { if [[ "${VERBOSE_FLAG:-false}" == "true" ]]; then echo "🔍 $*" >&2; fi; }

# Check current IDE2 configuration
current_ide2=$(qm config "$vmid" | grep "^ide2:" || true)
if [[ -z "$current_ide2" || "$current_ide2" == *"none"* ]]; then
    log_info "VM $vmid has no ISO mounted (IDE2 is already empty)."
    exit 0
fi

log_verbose "Current IDE2 configuration: $current_ide2"

# Unmount the ISO by setting IDE2 to none
if qm set "$vmid" --ide2 none; then
    log_success "ISO unmounted from VM $vmid (IDE2 set to none)."

    # Verify the unmount
    new_ide2=$(qm config "$vmid" | grep "^ide2:" || echo "none")
    log_verbose "New IDE2 configuration: $new_ide2"
else
    log_error "Failed to unmount ISO from VM $vmid."
    exit 1
fi
EOF
)

    execute_vm_command "$vmid" "$unmount_script" "$vmid"
    return $?
}
