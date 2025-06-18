#!/usr/bin/env bash

# To download:
# curl -o vm.sh https://gist.githubusercontent.com/QNimbus/a972908f09c2b6fed2b33307d00076f1/raw/vm.sh && chmod +x vm.sh

################################################################################
# Proxmox VM Creation and Management Script for Talos/Kubernetes Nodes
################################################################################
#
# Description: Automated script for creating and managing Talos Kubernetes VMs
#              on Proxmox VE with advanced configuration options and power controls.
#
# Author:      B. van Wetten <git@bvw.email>
# Version:     1.1.2
# Created:     2025-06-18
# Updated:     2025-06-18
#
# Features:    - Automated VM creation with configurable resources (CPU, RAM, Disks)
#              - Custom ISO mounting and storage selection
#              - VLAN tagging support
#              - QEMU Guest Agent integration for creation and power operations
#              - Force recreation of existing VMs
#              - VM power controls: stop, shutdown, restart, reboot
#              - Verbose and quiet operation modes
#              - VM status monitoring and statistics
#              - Clean, formatted output with progress indicators
#              - Robust error trapping and reporting
#              - Self-update mechanism
#
# Usage:       ./vm.sh <action> [VMID] [options]
#
# Examples:    ./vm.sh create 1001 server-1 --iso=talos-v1.7.0-amd64.iso --cores=2 --ram=4096
#              ./vm.sh create 1002 worker-1 --vlan=100 --force
#              ./vm.sh destroy 1001
#              ./vm.sh stop 1001
#              ./vm.sh shutdown 1002
#              ./vm.sh restart 1001
#              ./vm.sh reboot 1002
#              ./vm.sh list-iso
#              ./vm.sh update
#
# Repository:  https://gist.github.com/QNimbus/a972908f09c2b6fed2b33307d00076f1
#
################################################################################

# --- Script Metadata for Updates ---
SCRIPT_NAME=$(basename "$0")
SCRIPT_CURRENT_VERSION_LINE=$(grep '^# Version:' "$0" || echo "# Version: 0.0.0-local") # Graceful fallback if grep fails (e.g. new script)
SCRIPT_CURRENT_VERSION=$(echo "$SCRIPT_CURRENT_VERSION_LINE" | awk '{print $3}')
SCRIPT_RAW_URL="https://gist.githubusercontent.com/QNimbus/a972908f09c2b6fed2b33307d00076f1/raw/vm.sh"

# --- Global Flags & Early Utility Definitions ---
VERBOSE_FLAG="false" # Default, will be updated by arg parsing later

# Output formatting functions
log_info() {
    echo "ℹ️  $*"
}

log_success() {
    echo "✅ $*"
}

log_warning() {
    echo "⚠️  $*"
}

log_error() {
    # Ensure this function is simple and has no external dependencies beyond echo
    echo "❌ $*" >&2 # Send errors to stderr
}

log_verbose() {
    if [[ "$VERBOSE_FLAG" == "true" ]]; then
        echo "🔍 $*"
    fi
}

# Helper execution functions
run_quiet() {
    if [[ "$VERBOSE_FLAG" == "true" ]]; then
        "$@"
    else
        "$@" >/dev/null 2>&1
    fi
}

run_with_output() {
    if [[ "$VERBOSE_FLAG" == "true" ]]; then
        "$@"
    else
        "$@" 2>/dev/null # Suppresses stderr in non-verbose. Exit status is still checked.
    fi
}

run_with_warnings() {
    # Execute command and capture output, showing warnings even in non-verbose mode
    local temp_output
    temp_output=$(mktemp)
    local exit_code

    if [[ "$VERBOSE_FLAG" == "true" ]]; then
        # In verbose mode, show everything
        "$@" 2>&1 | tee "$temp_output"
        exit_code=${PIPESTATUS[0]}
    else
        # In non-verbose mode, capture output and only show warnings
        if "$@" >"$temp_output" 2>&1; then
            exit_code=0
        else
            exit_code=$?
        fi

        # Always show WARNING lines, even in non-verbose mode
        if grep -i "WARNING" "$temp_output" >/dev/null 2>&1; then
            echo ""
            log_warning "Storage warnings detected:"
            grep -i "WARNING" "$temp_output" | while IFS= read -r warning_line; do
                echo "  $warning_line"
            done
            echo ""
        fi
    fi

    rm -f "$temp_output"
    return $exit_code
}

run_critical() {
    # Execute command and show errors even in non-verbose mode
    # Used for commands where errors are critical and must be seen
    if [[ "$VERBOSE_FLAG" == "true" ]]; then
        "$@"
    else
        # Capture output, suppress on success, show on failure
        local temp_output
        temp_output=$(mktemp)
        if "$@" >"$temp_output" 2>&1; then
            rm -f "$temp_output"
            return 0
        else
            local exit_code=$?
            log_error "Command failed. Error details:"
            cat "$temp_output" >&2
            rm -f "$temp_output"
            return $exit_code
        fi
    fi
}

# Error trap function
_err_trap() {
    local exit_code=$?                 # Capture exit code immediately
    local line_no=${1:-$LINENO}        # LINENO from trap, or current if not passed
    local command_str="${BASH_COMMAND}" # Command that failed
    local func_stack=("${FUNCNAME[@]}")
    local source_stack=("${BASH_SOURCE[@]}")
    # local line_stack=("${BASH_LINENO[@]}") # BASH_LINENO includes trap line itself

    # Avoid trapping 'exit' or recursion within the trap, or non-error exits, or controlled returns
    if [[ "$command_str" == "exit"* || "$command_str" == *"_err_trap"* || "$exit_code" -eq 0 || "$command_str" == "return"* ]]; then
        return
    fi

    echo # Newline for readability
    log_error "ERROR in $SCRIPT_NAME: Script exited with status $exit_code."
    log_error "Failed command: '$command_str' on line $line_no of file '${BASH_SOURCE[0]}'." # BASH_SOURCE[0] is current file

    # Print call stack, excluding the _err_trap itself
    if [[ ${#func_stack[@]} -gt 1 ]]; then
        log_error "Call Stack (most recent call first):"
        # Iterate from the caller of _err_trap up to the main script
        for i in $(seq 1 $((${#func_stack[@]} - 1))); do
            local func_idx=$((i)) # Function name index in FUNCNAME
            local src_idx=$((i))  # Source file index in BASH_SOURCE
            local line_idx=$((i-1)) # Line number index in BASH_LINENO (caller's line)

            local func="${func_stack[$func_idx]}"
            local src_file="${source_stack[$src_idx]}"
            local src_line="${BASH_LINENO[$line_idx]}"
            log_error "  -> function '$func' in file '$src_file' at line $src_line"
        done
    fi
    # Script will exit after trap due to `set -e`
}

# Set the trap *after* _err_trap and its dependencies (log_error) are defined.
trap '_err_trap "${LINENO}"' ERR

# --- Script Behavior Options ---
# Enable strict mode after trap is set.
set -euo pipefail # Exit on error, undefined variable, or pipe failure

# --- Default Configuration ---
# VM settings
DEFAULT_VM_NAME_PREFIX="talos-k8s"
CORES=4                                     # Default number of CPU cores
SOCKETS=1                                   # Default number of CPU sockets
RAM_MB=32768                                # Default 32GB RAM
DISK_OS_SIZE_GB=128                         # 128GB SSD for OS disk
DISK_DATA_SIZE_GB=256                       # 256GB SSD for Data disk

# Proxmox specific settings
TALOS_ISO_PATH="local:iso/metal-amd64.iso"  # IMPORTANT: Change 'local' to your ISO storage ID
                                            # and 'metal-amd64.iso' to your actual ISO file name.
                                            # e.g., "storage_iso:iso/talos-v1.6.0-amd64.iso"
STORAGE_POOL_EFI="local-lvm"                # Storage for EFI disk (usually same as OS disk storage)
STORAGE_POOL_OS="local-lvm"                 # Storage for the OS disk
STORAGE_POOL_DATA="local-lvm"               # Storage for the data disk
NETWORK_BRIDGE="vmbr0"                      # Your Proxmox network bridge
OS_TYPE="l26"                               # l26 is generic Linux 2.6/3.x/4.x/5.x
MACHINE_TYPE="q35"
BIOS_TYPE="ovmf"                            # For EFI
VGA_TYPE="serial0"                          # Or 'qxl' if you want a graphical console, but Talos is often headless

# --- Function Definitions ---
usage() {
    echo ""
    echo "Usage: $0 <action> [options]"
    echo ""
    echo "Actions:"
    echo "  create <VMID> [VM_NAME_SUFFIX] [create_options]"
    echo "    Creates a new Talos VM."
    echo "    VMID: A unique numeric ID for the VM (e.g., 9001)."
    echo "    VM_NAME_SUFFIX (optional): Suffix for VM name (e.g., 'master-1'). Defaults to 'node'."
    echo "                           Full name will be ${DEFAULT_VM_NAME_PREFIX}-<VM_NAME_SUFFIX>"
    echo "  destroy <VMID>"
    echo "    Stops and destroys an existing VM."
    echo "  start <VMID>"
    echo "    Starts a stopped VM."
    echo "  stop <VMID>"
    echo "    Stops a running VM (gracefully, then force if needed)."
    echo "  shutdown <VMID>"
    echo "    Attempts to gracefully shut down a VM via QEMU guest agent,"
    echo "    then falls back to stop if agent command fails or times out."
    echo "  restart <VMID>"
    echo "    Stops and then starts a VM (host-level restart)."
    echo "  reboot <VMID>"
    echo "    Attempts to reboot a VM via QEMU guest agent (guest OS reboot)."
    echo "  list-iso"
    echo "    Lists all available ISO storages and their contents."
    echo "  update"
    echo "    Checks for script updates and prompts to install."
    echo "  version | --version"
    echo "    Shows the script version."
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
    echo "  --force                 Delete existing VM with same VMID before creating"
    echo "  --no-start              Do not automatically start the VM after creation"
    echo ""
    echo "Global Options:"
    echo "  --verbose               Show detailed output during operations"
    echo ""
    echo "Examples:"
    echo "  $0 create 9001 master-1"
    echo "  $0 create 9002 worker-1 --iso=talos-v1.7.0-amd64.iso --cores=2 --ram=8192"
    echo "  $0 create 9003 worker-2 --iso=custom.iso --storage-iso=nfs-iso --vlan=100"
    echo "  $0 create 9004 worker-3 --force --storage-os=local-zfs --storage-data=local-zfs"
    echo "  $0 destroy 9001"
    echo "  $0 start 9001"
    echo "  $0 stop 9002"
    echo "  $0 list-iso"
    echo "  $0 update --verbose"
    exit 1
}

check_vmid_exists() {
    local vmid=$1
    if qm status "$vmid" >/dev/null 2>&1; then
        return 0 # Exists
    else
        return 1 # Does not exist
    fi
}

is_vm_running() {
    local vmid=$1
    # check_vmid_exists should be called before this if there's doubt about existence
    if qm status "$vmid" 2>/dev/null | grep -q "status: running"; then
        return 0 # Running
    else
        return 1 # Not running (or doesn't exist, though qm status would error then)
    fi
}

create_vm() {
    local vmid=$1
    local vm_name_suffix=${2:-node} # Default suffix if not provided

    # Uses global *_OPT variables set by main argument parsing
    # Falls back to script defaults (DEFAULT_*, CORES, RAM_MB, etc.) if _OPT not set

    local vm_name="${DEFAULT_VM_NAME_PREFIX}-${vm_name_suffix}"

    # Handle force flag - delete existing VM if it exists
    if check_vmid_exists "$vmid"; then
        if [[ "$FORCE_FLAG_OPT" == "true" ]]; then
            log_warning "VM $vmid already exists. Force flag enabled - deleting existing VM first..."
            if force_destroy_vm "$vmid"; then
                log_success "Existing VM $vmid deleted. Proceeding with creation..."
            else
                log_error "Failed to delete existing VM $vmid. Aborting creation."
                return 1
            fi
        else
            log_error "VMID $vmid already exists. Use '--force' flag to delete it first, or choose a different VMID."
            return 1
        fi
    fi

    log_info "Creating VM $vmid ($vm_name)..."

    # Determine resource settings
    local actual_cores="${CORES_OPT:-$CORES}"
    local actual_sockets="${SOCKETS_OPT:-$SOCKETS}"
    local actual_ram_mb="${RAM_MB_OPT:-$RAM_MB}"

    log_verbose "VM resources: Cores=$actual_cores, Sockets=$actual_sockets, RAM=${actual_ram_mb}MB"

    # Determine ISO path
    local iso_path
    local actual_iso_storage
    if [[ -n "$ISO_NAME_OPT" ]]; then
        actual_iso_storage="${STORAGE_ISO_OPT:-local}" # Default to 'local' if --storage-iso not with --iso
        iso_path="${actual_iso_storage}:iso/${ISO_NAME_OPT}"
        log_verbose "Using custom ISO: $iso_path (from storage: $actual_iso_storage)"
    else
        iso_path="$TALOS_ISO_PATH" # This already includes storage
        log_verbose "Using default ISO: $iso_path"
    fi

    # Determine storage pools for disks
    local actual_storage_os="${STORAGE_OS_OPT:-$STORAGE_POOL_OS}"
    local actual_storage_efi="${actual_storage_os}" # EFI disk usually on same storage as OS disk
    if [[ -n "$STORAGE_EFI_OPT" ]]; then # Allow specific EFI storage if ever needed
      actual_storage_efi="${STORAGE_EFI_OPT}"
    fi
    local actual_storage_data="${STORAGE_DATA_OPT:-$STORAGE_POOL_DATA}"


    if [[ "$actual_storage_os" != "$STORAGE_POOL_OS" ]]; then
        log_verbose "Using custom OS/EFI storage: $actual_storage_os (EFI will be on $actual_storage_efi)"
    fi
    if [[ "$actual_storage_data" != "$STORAGE_POOL_DATA" ]]; then
        log_verbose "Using custom data storage: $actual_storage_data"
    fi


    # Determine network configuration
    local net_config="virtio,bridge=$NETWORK_BRIDGE,firewall=0" # firewall=0 is often safer for Talos
    if [[ -n "$VLAN_TAG_OPT" ]]; then
        net_config="${net_config},tag=${VLAN_TAG_OPT}"
        log_verbose "Using VLAN tag: $VLAN_TAG_OPT"
    fi

    # 1. Create the VM with basic settings
    log_verbose "Creating VM with basic settings using 'qm create'..."
    run_critical qm create "$vmid" \
        --name "$vm_name" \
        --ostype "$OS_TYPE" \
        --machine "$MACHINE_TYPE" \
        --bios "$BIOS_TYPE" \
        --cpu host \
        --cores "$actual_cores" \
        --sockets "$actual_sockets" \
        --numa 1 \
        --memory "$actual_ram_mb" \
        --balloon 0 \
        --onboot 1 \
        --net0 "$net_config"

    log_verbose "VM basic structure created. Proceeding with 'qm set' for devices..."

    # 2. Add EFI disk
    log_verbose "Adding EFI disk to storage '$actual_storage_efi'..."
    # efitype=4m implies a 4MB disk. The '0' for size means "create new volume of specified efitype size".
    run_with_warnings qm set "$vmid" --efidisk0 "${actual_storage_efi}:0,efitype=4m,pre-enrolled-keys=0"

    # 3. Add SCSI controller
    log_verbose "Adding SCSI controller (virtio-scsi-pci)..."
    run_quiet qm set "$vmid" --scsihw virtio-scsi-pci

    # 4. Add the OS disk
    log_verbose "Adding OS disk (${DISK_OS_SIZE_GB}GB) to storage '$actual_storage_os'..."
    run_with_warnings qm set "$vmid" --scsi0 "${actual_storage_os}:${DISK_OS_SIZE_GB},ssd=1"

    # 5. Add the Data disk
    log_verbose "Adding data disk (${DISK_DATA_SIZE_GB}GB) to storage '$actual_storage_data'..."
    run_with_warnings qm set "$vmid" --scsi1 "${actual_storage_data}:${DISK_DATA_SIZE_GB},ssd=1"

    # 6. Add the ISO for installation
    log_verbose "Mounting ISO: $iso_path"
    run_critical qm set "$vmid" --ide2 "$iso_path,media=cdrom"

    # 7. Set boot order
    log_verbose "Setting boot order: ide2 (CD/ISO), then scsi0 (OS Disk)..."
    run_quiet qm set "$vmid" --boot order="ide2;scsi0"

    # 8. Add serial console
    log_verbose "Adding serial console and setting VGA to serial0..."
    run_quiet qm set "$vmid" --serial0 socket --vga "$VGA_TYPE" # VGA_TYPE is "serial0" by default

    # 9. Enable QEMU Guest Agent
    log_verbose "Enabling QEMU Guest Agent..."
    run_quiet qm set "$vmid" --agent enabled=1

    log_success "VM $vmid ($vm_name) created successfully!"

    if [[ "$VERBOSE_FLAG" == "true" ]]; then
        echo ""
        log_verbose "VM Configuration:"
        qm config "$vmid" # This command outputs directly
        echo ""
    fi

    if [[ "$NO_START_FLAG_OPT" == "true" ]]; then
        log_info "VM $vmid created but not started (--no-start flag provided)."
        log_info "To start the VM manually: qm start $vmid"
    else
        log_info "Starting VM $vmid..."
        if run_with_output qm start "$vmid"; then # run_with_output checks exit code
            log_success "VM $vmid started successfully!"
            log_verbose "Connect to console: qm terminal $vmid"
            wait_for_vm_online "$vmid"
        else
            log_error "Failed to start VM $vmid. Check Proxmox task logs for details."
            return 1
        fi
    fi
    log_warning "Remember to eject the ISO ('qm set $vmid --ide2 none') and potentially adjust boot order after Talos installation if it doesn't handle it automatically."
    return 0
}

destroy_vm() {
    local vmid=$1

    if ! check_vmid_exists "$vmid"; then
        log_warning "VMID $vmid does not exist. Nothing to do."
        return 0
    fi

    log_info "Attempting to destroy VM $vmid..."
    read -r -p "ARE YOU SURE you want to stop and PERMANENTLY destroy VM $vmid and its disks? (yes/NO): " confirmation
    if [[ "$confirmation" != "yes" ]]; then
        log_info "Destruction aborted by user."
        return 0
    fi

    log_info "Stopping VM $vmid (if running)..."
    qm stop "$vmid" --timeout 30 || log_verbose "VM $vmid was not running or stop timed out. Continuing..."

    for i in {1..5}; do
        if ! is_vm_running "$vmid"; then
            log_verbose "VM $vmid is stopped."
            break
        fi
        log_verbose "Waiting for VM $vmid to stop... ($i/5)"
        sleep 2
    done

    if is_vm_running "$vmid"; then
         log_warning "VM $vmid is still running. Attempting force stop."
         qm stop "$vmid" --force || log_verbose "Force stop command issued. Might have already stopped or failed."
         sleep 3
    fi

    log_info "Destroying VM $vmid and its disks..."
    if qm destroy "$vmid" --purge; then
        log_success "VM $vmid and its disks have been destroyed."
    else
        log_warning "Failed to destroy VM $vmid initially. Attempting to unlock and retry..."
        qm unlock "$vmid" || log_verbose "Unlock command issued for VM $vmid." # Allow unlock to fail if not locked
        if qm destroy "$vmid" --purge; then
            log_success "VM $vmid and its disks have been destroyed on retry."
        else
            log_error "Still failed to destroy VM $vmid. Manual intervention may be required."
            return 1
        fi
    fi
    return 0
}

force_destroy_vm() {
    local vmid=$1

    if ! check_vmid_exists "$vmid"; then
        log_verbose "VM $vmid does not exist. Nothing to force destroy."
        return 0
    fi

    log_verbose "Force destroying VM $vmid..."
    # Suppress output from these commands as it's a "force" operation
    qm stop "$vmid" --timeout 10 >/dev/null 2>&1 || true
    for i in {1..3}; do
        if ! is_vm_running "$vmid"; then break; fi
        sleep 1
    done
    if is_vm_running "$vmid"; then
        qm stop "$vmid" --force >/dev/null 2>&1 || true
        sleep 2
    fi

    if qm destroy "$vmid" --purge >/dev/null 2>&1; then
        log_verbose "VM $vmid force-destroyed successfully."
        return 0
    else
        qm unlock "$vmid" >/dev/null 2>&1 || true # Attempt unlock
        if qm destroy "$vmid" --purge >/dev/null 2>&1; then
            log_verbose "VM $vmid force-destroyed successfully on retry after unlock."
            return 0
        else
            # Do not log_error here if it's called from create_vm context, let create_vm handle it
            # Just return failure.
            return 1
        fi
    fi
}

stop_vm() {
    local vmid=$1

    if ! check_vmid_exists "$vmid"; then
        log_warning "VM $vmid does not exist. Cannot stop."
        return 1
    fi

    if ! is_vm_running "$vmid"; then
        log_info "VM $vmid is already stopped."
        return 0
    fi

    log_info "Attempting to gracefully stop VM $vmid..."
    if run_with_output qm stop "$vmid" --timeout 60; then
        log_success "VM $vmid stopped successfully."
        return 0
    fi

    log_warning "Graceful stop failed or timed out after 60 seconds."
    # Check if it stopped despite timeout message
    if ! is_vm_running "$vmid"; then
        log_success "VM $vmid is now stopped (detected after graceful stop attempt timed out)."
        return 0
    fi

    log_info "Attempting force stop for VM $vmid..."
    if run_with_output qm stop "$vmid" --force; then
        log_success "VM $vmid forcibly stopped."
        return 0
    else
        # Final check
        if ! is_vm_running "$vmid"; then
             log_success "VM $vmid is now stopped (detected after force stop attempt)."
             return 0
        fi
        log_error "Failed to stop VM $vmid even with force. Manual intervention may be required."
        return 1
    fi
}

shutdown_vm() {
    local vmid=$1

    if ! check_vmid_exists "$vmid"; then
        log_warning "VM $vmid does not exist. Cannot shutdown."
        return 1
    fi

    if ! is_vm_running "$vmid"; then
        log_info "VM $vmid is already stopped."
        return 0
    fi

    log_info "Attempting to send shutdown command to guest OS for VM $vmid via QEMU agent..."
    if qm guest cmd "$vmid" ping >/dev/null 2>&1; then
        log_verbose "QEMU guest agent is responsive. Sending shutdown command..."
        if run_with_output qm guest cmd "$vmid" shutdown; then
            log_info "Shutdown command sent. Waiting up to 60 seconds for VM $vmid to power off..."
            local shutdown_wait_time=0
            local dots_printed=false
            while [[ $shutdown_wait_time -lt 60 ]]; do
                if ! is_vm_running "$vmid"; then
                    if [[ "$VERBOSE_FLAG" != "true" && "$dots_printed" == "true" ]]; then echo; fi
                    log_success "VM $vmid shut down successfully via guest agent."
                    return 0
                fi
                if [[ "$VERBOSE_FLAG" != "true" ]]; then printf "."; dots_printed=true; fi
                log_verbose "VM $vmid still running. Waited ${shutdown_wait_time}s..."
                sleep 5
                shutdown_wait_time=$((shutdown_wait_time + 5))
            done
            if [[ "$VERBOSE_FLAG" != "true" && "$dots_printed" == "true" ]]; then echo; fi
            log_warning "VM $vmid did not shut down via guest agent within 60 seconds."
        else
            log_warning "Guest agent responded to ping, but 'qm guest cmd $vmid shutdown' command failed."
        fi
    else
        log_warning "QEMU guest agent for VM $vmid is not responding to ping."
        log_warning "Cannot send guest shutdown command. Agent might not be installed/running, or VM is busy/booting."
    fi

    log_info "Falling back to standard stop procedure for VM $vmid."
    stop_vm "$vmid" # Delegate to stop_vm for the rest
    return $? # Return status of stop_vm
}

restart_vm() {
    local vmid=$1

    if ! check_vmid_exists "$vmid"; then
        log_warning "VM $vmid does not exist. Cannot restart."
        return 1
    fi

    log_info "Attempting to restart VM $vmid..."
    if is_vm_running "$vmid"; then
        log_info "VM $vmid is currently running. Proceeding to stop it first..."
        if ! stop_vm "$vmid"; then
            log_error "Failed to stop VM $vmid as part of restart. Aborting restart."
            return 1
        fi
        # stop_vm already logs success or failure of stopping
        log_verbose "VM $vmid successfully stopped. Proceeding with start."
    else
        log_info "VM $vmid is not currently running. Will proceed to start it."
    fi

    log_info "Starting VM $vmid..."
    if run_with_output qm start "$vmid"; then
        log_success "VM $vmid started successfully."
        wait_for_vm_online "$vmid" # Monitor for agent readiness
        return 0
    else
        log_error "Failed to start VM $vmid."
        return 1
    fi
}

reboot_vm() {
    local vmid=$1

    if ! check_vmid_exists "$vmid"; then
        log_warning "VM $vmid does not exist. Cannot reboot."
        return 1
    fi

    if ! is_vm_running "$vmid"; then
        log_warning "VM $vmid is not running. Cannot send guest reboot command. Start it first or use 'restart' action."
        return 1
    fi

    log_info "Attempting to reboot VM $vmid via guest OS shutdown followed by start..."
    if ! qm guest cmd "$vmid" ping >/dev/null 2>&1; then
        log_warning "QEMU guest agent for VM $vmid is not responding to ping."
        log_warning "Cannot send guest shutdown command. Agent might not be installed/running, or VM is busy/booting."
        log_info "Consider using './vm.sh restart $vmid' for a host-level restart."
        return 1
    fi

    log_verbose "Guest agent ping successful. Sending shutdown command for reboot..."
    if run_with_output qm guest cmd "$vmid" shutdown; then
        log_info "Shutdown command sent successfully to VM $vmid via guest agent."

        log_info "Waiting up to 60 seconds for VM $vmid to shut down completely..."
        local shutdown_wait_time=0
        local shutdown_timeout=60
        local dots_printed_shutdown=false
        while [[ $shutdown_wait_time -lt $shutdown_timeout ]]; do
            if ! is_vm_running "$vmid"; then
                if [[ "$VERBOSE_FLAG" != "true" && "$dots_printed_shutdown" == "true" ]]; then echo; fi
                log_success "VM $vmid has shut down successfully."
                break
            fi
            if [[ "$VERBOSE_FLAG" != "true" ]]; then printf "."; dots_printed_shutdown=true; fi
            log_verbose "VM $vmid still running, waited ${shutdown_wait_time}s..."
            sleep 5
            shutdown_wait_time=$((shutdown_wait_time + 5))
        done
        if [[ "$VERBOSE_FLAG" != "true" && "$dots_printed_shutdown" == "true" ]]; then echo; fi

        if is_vm_running "$vmid"; then
            log_warning "VM $vmid did not shut down within ${shutdown_timeout} seconds. Attempting force stop..."
            if ! run_with_output qm stop "$vmid" --force; then
                log_error "Failed to force stop VM $vmid. Cannot complete reboot."
                return 1
            fi
            sleep 3
        fi

        log_info "Starting VM $vmid to complete reboot..."
        if run_with_output qm start "$vmid"; then
            log_success "VM $vmid started successfully."
            wait_for_vm_online "$vmid"
            log_success "VM $vmid has been rebooted successfully (via guest shutdown + start)."
            return 0
        else
            log_error "Failed to start VM $vmid after shutdown. Reboot incomplete."
            return 1
        fi
    else
        log_error "Failed to send shutdown command via guest agent."
        log_info "Consider using './vm.sh restart $vmid' for a host-level restart."
        return 1
    fi
}

start_vm() {
    local vmid=$1

    if ! check_vmid_exists "$vmid"; then
        log_warning "VM $vmid does not exist. Cannot start."
        return 1
    fi

    if is_vm_running "$vmid"; then
        log_info "VM $vmid is already running."
        return 0
    fi

    log_info "Starting VM $vmid..."
    if run_with_output qm start "$vmid"; then
        log_success "VM $vmid started successfully."
        wait_for_vm_online "$vmid" # Monitor for agent readiness
        return 0
    else
        log_error "Failed to start VM $vmid."
        return 1
    fi
}

list_iso_storages() {
    log_info "=== Available ISO Storages and Contents ==="
    echo

    local storages
    if ! storages=$(pvesm status --content iso 2>/dev/null | tail -n +2 | awk '{print $1}'); then
        log_warning "Could not list ISO storages (pvesm status failed). Is Proxmox VE running correctly?"
        return 1
    fi

    if [[ -z "$storages" ]]; then
        log_info "No storages with ISO content found or accessible."
        return 0
    fi

    for storage in $storages; do
        echo "Storage: $storage"
        echo "---------------------------------------"
        local storage_info
        storage_info=$(pvesm status --storage "$storage" 2>/dev/null || true)
        if [[ -n "$storage_info" ]]; then
             # Example output of pvesm status:
             # Name             Type     Status           Total            Used       Available        %
             # local             dir     active        98215900         4065612        88900000    4.14%
             # We want the 'active' (Status) and 'dir' (Type) parts.
            echo "Status: $(echo "$storage_info" | tail -n +2 | awk '{print $3" ("$2")"}')"
        fi

        local iso_files
        iso_files=$(pvesm list "$storage" --content iso 2>/dev/null | tail -n +2 || true)
        if [[ -n "$iso_files" ]]; then
            echo "Available ISO files:"
            # pvesm list output:
            # Volid                               Format      Type            Size  Encrypted
            # local:iso/talos-amd64.iso           iso         iso       46137344          0
            echo "$iso_files" | while IFS= read -r line; do
                local volid size format
                volid=$(echo "$line" | awk '{print $1}')
                volid_name=$(basename "$volid") # Get just the filename part
                size=$(echo "$line" | awk '{print $4}') # Size is usually 4th field
                format=$(echo "$line" | awk '{print $2}')
                # Human readable size (optional, requires numfmt)
                local human_size=""
                if command -v numfmt >/dev/null && [[ "$size" =~ ^[0-9]+$ ]]; then
                    human_size=" ($(numfmt --to=iec-i --suffix=B --format="%.1f" "$size"))"
                fi
                echo "  - ${volid_name} (Storage VolID: ${volid}, Format: ${format}, Size: ${size}${human_size})"
            done
        else
            echo "  No ISO files found in this storage."
        fi
        echo
    done
    return 0
}

wait_for_vm_online() {
    local vmid=$1
    local max_wait=300 # 5 minutes
    local check_interval=5
    local elapsed=0
    local initial_message_printed=false
    local dots_printed=false

    log_info "Waiting for VM $vmid to be running and QEMU guest agent to be available..."

    while [[ $elapsed -lt $max_wait ]]; do
        if ! is_vm_running "$vmid"; then
            if [[ "$VERBOSE_FLAG" != "true" && ! "$initial_message_printed" == "true" ]]; then
                 echo -n "VM is not running, waiting"
                 initial_message_printed=true
            fi
            if [[ "$VERBOSE_FLAG" != "true" ]]; then printf "."; dots_printed=true; fi
            log_verbose "VM $vmid is not running. Waiting..."
            sleep $check_interval
            elapsed=$((elapsed + check_interval))
            continue
        fi

        # VM is running, now check agent
        if ! $initial_message_printed && [[ "$VERBOSE_FLAG" != "true" ]]; then
            echo -n "VM is running, waiting for agent"
            initial_message_printed=true
        fi

        if qm guest cmd "$vmid" ping >/dev/null 2>&1; then
            if [[ "$VERBOSE_FLAG" != "true" && "$dots_printed" == "true" ]]; then echo; fi # New line after dots
            log_success "VM $vmid is online and guest agent is responding to ping!"
            if qm guest cmd "$vmid" get-time >/dev/null 2>&1; then
                log_success "Guest agent is fully functional (get-time successful)."
                display_vm_stats "$vmid"
                return 0
            else
                log_verbose "Guest agent pingable but not fully ready (get-time failed). Retrying in $check_interval seconds..."
                 # It's online but get-time failed, can still be considered a success for some operations.
                 # For now, we return success if ping worked. Could be stricter.
                 display_vm_stats "$vmid"
                 return 0 # Or decide to wait longer for full functionality
            fi
        else
            if [[ "$VERBOSE_FLAG" != "true" ]]; then printf "."; dots_printed=true; fi
            log_verbose "VM $vmid is running, but guest agent not responding to ping. Waiting..."
        fi

        sleep $check_interval
        elapsed=$((elapsed + check_interval))
    done

    if [[ "$VERBOSE_FLAG" != "true" && "$dots_printed" == "true" ]]; then echo; fi
    log_warning "Timeout waiting for VM $vmid online or guest agent after ${max_wait} seconds."
    if is_vm_running "$vmid"; then
        log_info "VM $vmid is running, but guest agent did not become responsive."
    else
        log_info "VM $vmid is not running."
    fi
    log_info "Check manually:"
    log_info "  - VM status: qm status $vmid"
    log_info "  - Console:   qm terminal $vmid"
    return 1
}

display_vm_stats() {
    local vmid=$1

    log_info "VM Statistics ($vmid):"
    echo "┌────────────────────────────────────────────────────────────┐"
    local vm_status
    vm_status=$(qm status "$vmid" | awk '{print $2}' 2>/dev/null || echo "unknown")
    printf "│ %-15s │ %-40s │\n" "Status:" "$vm_status"

    local mac_address
    mac_address=$(qm config "$vmid" | grep "^net0:" | grep -o -E '([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}' 2>/dev/null || echo "N/A")
    printf "│ %-15s │ %-40s │\n" "MAC Address:" "$mac_address"

    echo "└────────────────────────────────────────────────────────────┘"
}

get_remote_version() {
    local timestamp
    timestamp=$(date +%s)
    local cache_busted_url="${SCRIPT_RAW_URL}?v=${timestamp}&nocache=$(date +%s%N 2>/dev/null || echo $RANDOM)"

    if [[ "$VERBOSE_FLAG" == "true" ]]; then
        echo "🔍 Fetching remote version from: $cache_busted_url" >&2
    fi

    local remote_script_content
    if ! remote_script_content=$(curl --fail -sSL \
        -H "Cache-Control: no-cache, no-store, max-age=0, must-revalidate" \
        -H "Pragma: no-cache" \
        -H "Expires: 0" \
        "$cache_busted_url"); then
        echo "⚠️  curl failed to fetch remote script. HTTP error or network issue." >&2
        return 1
    fi

    if [[ -z "$remote_script_content" ]]; then
        echo "⚠️  Fetched remote script content is empty." >&2
        return 1
    fi

    local remote_version_line
    remote_version_line=$(echo "$remote_script_content" | grep '^# Version:' || true)
    if [[ -z "$remote_version_line" ]]; then
        echo "⚠️  Could not find version information in remote script." >&2
        if [[ "$VERBOSE_FLAG" == "true" ]]; then
            echo "🔍 First 5 lines of fetched content:" >&2
            echo "$remote_script_content" | head -5 >&2
        fi
        return 1
    fi
    echo "$remote_version_line" | awk '{print $3}'
}

compare_versions() {
    local v1=$1
    local v2=$2
    if [[ "$v1" == "$v2" ]]; then return 1; fi # Equal
    # Sort -V handles versions like 1.0.0, 1.0.10, 1.1.0 correctly
    if [[ "$(printf '%s\n' "$v1" "$v2" | sort -V | head -n1)" == "$v1" ]]; then
        return 0 # v1 < v2
    else
        return 2 # v1 > v2
    fi
}

check_and_prompt_update() {
    log_info "Checking for updates..."
    local remote_version
    remote_version=$(get_remote_version || true) # Capture output, allow function to fail

    if [[ -z "$remote_version" ]]; then
        log_warning "Update check failed: could not retrieve remote version."
        return 1
    fi

    if [[ "$VERBOSE_FLAG" == "true" ]]; then
        echo "🔍 Current version: $SCRIPT_CURRENT_VERSION, Remote version: $remote_version" >&2
    fi

    local comparison_result
    # Use subshell to capture exit status of compare_versions
    comparison_result=$(compare_versions "$SCRIPT_CURRENT_VERSION" "$remote_version"; echo $?)

    if [[ "$comparison_result" -eq 0 ]]; then # Current < Remote
        log_success "A new version ($remote_version) is available! (Current: $SCRIPT_CURRENT_VERSION)"
        read -r -p "Do you want to download and install it now? (y/N): " choice
        if [[ "$choice" =~ ^[Yy]$ ]]; then
            if ! perform_self_update "$remote_version"; then
                log_error "Update process failed."
                return 1
            fi
            # perform_self_update exits on success
        else
            log_info "Update skipped by user."
        fi
    elif [[ "$comparison_result" -eq 1 ]]; then # Equal
        log_info "You are running the latest version ($SCRIPT_CURRENT_VERSION)."
    elif [[ "$comparison_result" -eq 2 ]]; then # Current > Remote
        log_warning "Your current version ($SCRIPT_CURRENT_VERSION) seems newer than remote ($remote_version)."
    else
        log_error "Unknown result ($comparison_result) from version comparison." # Should not happen
        return 1
    fi
    return 0
}

perform_self_update() {
    local new_version=$1
    log_info "Attempting to update to version $new_version..."

    local script_path
    script_path=$(realpath "$0")
    local temp_file
    if ! temp_file=$(mktemp); then
        log_error "Failed to create temporary file. Update aborted."
        return 1
    fi

    local timestamp
    timestamp=$(date +%s)
    local cache_busted_url="${SCRIPT_RAW_URL}?v=${timestamp}&nocache=$(date +%s%N 2>/dev/null || echo $RANDOM)"
    log_verbose "Downloading from: $cache_busted_url"

    if ! curl --fail -sSL \
        -H "Cache-Control: no-cache, no-store, max-age=0, must-revalidate" \
        -H "Pragma: no-cache" \
        -H "Expires: 0" \
        "$cache_busted_url" -o "$temp_file"; then
        log_error "Failed to download new version. Update aborted."
        rm -f "$temp_file"
        return 1
    fi

    if ! grep -qE "^#!/(bin/bash|usr/bin/env bash)" "$temp_file"; then
        log_error "Downloaded file does not appear to be a valid bash script. Update aborted."
        rm -f "$temp_file"
        return 1
    fi

    local downloaded_version
    downloaded_version=$(grep '^# Version:' "$temp_file" | awk '{print $3}' || true)
    if [[ -z "$downloaded_version" ]]; then
         log_error "Could not extract version from downloaded script. Update aborted."
         rm -f "$temp_file"
         return 1
    fi
    if [[ "$downloaded_version" != "$new_version" ]]; then
        log_warning "Downloaded version ($downloaded_version) mismatch expected ($new_version)."
        log_warning "This might be due to cache or recent update. Proceeding if downloaded is newer or equal."
        local comparison_result
        comparison_result=$(compare_versions "$new_version" "$downloaded_version"; echo $?) # Is expected_new < downloaded
        if [[ "$comparison_result" -eq 2 ]]; then # new_version (expected) > downloaded_version
            log_error "Downloaded version is older than expected. Update aborted."
            rm -f "$temp_file"
            return 1
        fi
    fi

    log_verbose "New version ($downloaded_version) downloaded to $temp_file. Replacing $script_path..."
    if mv "$temp_file" "$script_path"; then
        chmod +x "$script_path"
        log_success "Script updated to version $downloaded_version successfully!"
        log_info "Please re-run the script: $script_path"
        exit 0 # Exit after successful update
    else
        local mv_exit_code=$?
        log_error "Failed to replace script file (mv exited $mv_exit_code). Update aborted."
        log_error "New version is at: $temp_file (not removed)"
        return 1
    fi
}

# --- Main Script Logic ---
# Initialize option flags/variables that will be set by argument parsing
ACTION="${1:-}"
VMID=""
VM_NAME_SUFFIX=""

CORES_OPT=""
SOCKETS_OPT=""
RAM_MB_OPT=""
ISO_NAME_OPT=""
STORAGE_ISO_OPT=""
STORAGE_OS_OPT=""
STORAGE_EFI_OPT="" # For distinct EFI storage, though typically same as OS
STORAGE_DATA_OPT=""
VLAN_TAG_OPT=""
FORCE_FLAG_OPT="false"
NO_START_FLAG_OPT="false"
# VERBOSE_FLAG is global, initialized earlier

# Handle global options that can appear anywhere, like --verbose
# And also specific commands like update --verbose
temp_args=()
for arg in "$@"; do
    case "$arg" in
        --verbose)
            VERBOSE_FLAG="true"
            ;;
        *)
            temp_args+=("$arg")
            ;;
    esac
done
# Re-assign arguments without --verbose (it's now globally handled)
set -- "${temp_args[@]}"
ACTION="${1:-}" # Re-evaluate ACTION after --verbose is stripped


# Handle commands that don't require VMID or further complex parsing first
case "$ACTION" in
    list-iso)
        list_iso_storages
        exit $?
        ;;
    update)
        check_and_prompt_update # VERBOSE_FLAG is already set if it was provided
        exit $?
        ;;
    version|--version)
        echo "$SCRIPT_NAME version $SCRIPT_CURRENT_VERSION"
        exit 0
        ;;
    ""|"-h"|"--help")
        usage
        ;;
esac

# For 'create', 'destroy', and new power actions, VMID is mandatory (second argument)
case "$ACTION" in
    create|destroy|start|stop|shutdown|restart|reboot)
        if [[ -z "${2:-}" ]]; then
            log_error "Action '$ACTION' requires a VMID as the second argument."
            usage
        fi
        VMID="$2"
        if ! [[ "$VMID" =~ ^[0-9]+$ ]]; then
            log_error "VMID must be a number. Got: '$VMID'"
            usage
        fi
        ;;
    *) # Unrecognized action if not one of the above simple commands or VMID-requiring commands
        log_error "Invalid action '$ACTION'."
        usage
        ;;
esac

# Argument parsing specific to 'create' action
param_offset=2 # Start after ACTION and VMID

if [[ "$ACTION" == "create" ]]; then
    # The third argument ($3) for 'create' can be VM_NAME_SUFFIX or an option
    if [[ -n "${3:-}" && "${3::2}" != "--" ]]; then
        VM_NAME_SUFFIX="$3"
        param_offset=3 # Options start from $4
    else
        VM_NAME_SUFFIX="node" # Default suffix if $3 is an option or not present
        # param_offset remains 2, options start from $3
    fi
fi

# Shift away ACTION, VMID, and optional VM_NAME_SUFFIX for 'create'
# For other VMID actions, only ACTION and VMID are shifted.
shift "$param_offset"
# Now $@ contains only the remaining options (e.g., --iso=..., --force for create)
# For destroy, stop, shutdown, restart, reboot, $@ should be empty if no extra args.

if [[ "$ACTION" != "create" && -n "$@" ]]; then
    log_warning "Warning: Action '$ACTION' does not accept additional options. Ignoring: '$@'"
fi


# Parse options only if action is 'create'
if [[ "$ACTION" == "create" ]]; then
    for arg in "$@"; do
        case "$arg" in
            --cores=*)
                CORES_OPT="${arg#--cores=}"
                if ! [[ "$CORES_OPT" =~ ^[0-9]+$ && "$CORES_OPT" -gt 0 ]]; then
                    log_error "Invalid cores value: '$CORES_OPT'. Must be a positive integer."
                    usage
                fi
                ;;
            --sockets=*)
                SOCKETS_OPT="${arg#--sockets=}"
                if ! [[ "$SOCKETS_OPT" =~ ^[0-9]+$ && "$SOCKETS_OPT" -gt 0 ]]; then
                    log_error "Invalid sockets value: '$SOCKETS_OPT'. Must be a positive integer."
                    usage
                fi
                ;;
            --ram=*)
                RAM_MB_OPT="${arg#--ram=}"
                if ! [[ "$RAM_MB_OPT" =~ ^[0-9]+$ && "$RAM_MB_OPT" -ge 512 ]]; then
                    log_error "Invalid RAM value: '$RAM_MB_OPT'. Must be an integer >= 512 MB."
                    usage
                fi
                ;;
            --iso=*)
                ISO_NAME_OPT="${arg#--iso=}"
                ;;
            --storage-iso=*)
                STORAGE_ISO_OPT="${arg#--storage-iso=}"
                ;;
            --storage-os=*)
                STORAGE_OS_OPT="${arg#--storage-os=}"
                ;;
            --storage-data=*)
                STORAGE_DATA_OPT="${arg#--storage-data=}"
                ;;
            --vlan=*)
                VLAN_TAG_OPT="${arg#--vlan=}"
                if ! [[ "$VLAN_TAG_OPT" =~ ^[0-9]+$ && "$VLAN_TAG_OPT" -ge 1 && "$VLAN_TAG_OPT" -le 4094 ]]; then
                    log_error "Invalid VLAN tag: '$VLAN_TAG_OPT'. Must be 1-4094."
                    usage
                fi
                ;;
            --force)
                FORCE_FLAG_OPT="true"
                ;;
            --no-start)
                NO_START_FLAG_OPT="true"
                ;;
            # --verbose is handled globally earlier
            *)
                # Only warn if it's not an already processed global option
                if [[ "$arg" != "--verbose" ]]; then
                    log_warning "Unknown parameter '$arg' ignored for 'create' action."
                fi
                ;;
        esac
    done
fi

# Execute main action
case "$ACTION" in
    create)
        # create_vm uses the globally set *_OPT variables
        if create_vm "$VMID" "$VM_NAME_SUFFIX"; then
            exit 0
        else
            exit 1 # create_vm should log specific errors
        fi
        ;;
    destroy)
        if destroy_vm "$VMID"; then
            exit 0
        else
            exit 1
        fi
        ;;
    start)
        if start_vm "$VMID"; then exit 0; else exit 1; fi
        ;;
    stop)
        if stop_vm "$VMID"; then exit 0; else exit 1; fi
        ;;
    shutdown)
        if shutdown_vm "$VMID"; then exit 0; else exit 1; fi
        ;;
    restart)
        if restart_vm "$VMID"; then exit 0; else exit 1; fi
        ;;
    reboot)
        if reboot_vm "$VMID"; then exit 0; else exit 1; fi
        ;;
    *)
        # This case should ideally not be reached due to earlier checks
        log_error "Internal error: Unhandled action '$ACTION' at final dispatch."
        usage
        ;;
esac

exit 0
