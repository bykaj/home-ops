#!/usr/bin/env bash

# To download:
# curl -o vm.sh https://gist.githubusercontent.com/QNimbus/a972908f09c2b6fed2b33307d00076f1/raw/vm.sh && chmod +x vm.sh

################################################################################
# Proxmox VM Creation and Management Script for Talos/Kubernetes Nodes
################################################################################
#
# Description: Automated script for creating and managing Talos Kubernetes VMs
#              on Proxmox VE with advanced configuration options and power controls.
#              Uses external libraries for utility and Proxmox functions.
#
# Author:      B. van Wetten <git@bvw.email>
# Version:     1.3.8
# Created:     2025-06-18
# Updated:     2025-06-27
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
#              - Self-update mechanism for main script and libraries
#              - Modular design with functions in ./lib/
#              - Cluster-aware VM management (automatically detects VM location)
#              - Cross-node VM operations via SSH
#              - Dependency checking including jq for JSON parsing
#
# Usage:       ./vm.sh <action> [VMID[,VMID,...]] [options]
#
# Examples:    ./vm.sh create 1001 server-1 --iso=talos-v1.7.0-amd64.iso --cores=2 --ram=4096
#              ./vm.sh create 1002 worker-1 --vlan=100 --force
#              ./vm.sh destroy 1001
#              ./vm.sh destroy 1001,1002,1003
#              ./vm.sh start 1001,1002
#              ./vm.sh stop 1001,1002,1003
#              ./vm.sh list-iso
#              ./vm.sh update
#
# Repository:  https://gist.github.com/QNimbus/a972908f09c2b6fed2b33307d00076f1
#
################################################################################

# --- Script Metadata for Updates ---
SCRIPT_NAME=$(basename "$0")
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
SCRIPT_CURRENT_VERSION_LINE=$(grep '^# Version:' "$0" || echo "# Version: 0.0.0-local")
SCRIPT_CURRENT_VERSION=$(echo "$SCRIPT_CURRENT_VERSION_LINE" | awk '{print $3}')
SCRIPT_RAW_URL="https://gist.githubusercontent.com/QNimbus/a972908f09c2b6fed2b33307d00076f1/raw/vm.sh"

# --- Library Configuration ---
LIB_DIR_NAME="lib"
LIB_DIR="${SCRIPT_DIR}/${LIB_DIR_NAME}"

declare -A LIBRARIES_CONFIG
LIBRARIES_CONFIG=(
    ["utils"]="utils.lib.sh UTILS_LIB_RAW_URL UTILS_LIB_CURRENT_VERSION ^# LibVersion:"
    ["proxmox"]="proxmox.lib.sh PROXMOX_LIB_RAW_URL PROXMOX_LIB_CURRENT_VERSION ^# LibVersion:"
)
UTILS_LIB_RAW_URL="https://gist.githubusercontent.com/QNimbus/a972908f09c2b6fed2b33307d00076f1/raw/utils.lib.sh"
PROXMOX_LIB_RAW_URL="https://gist.githubusercontent.com/QNimbus/a972908f09c2b6fed2b33307d00076f1/raw/proxmox.lib.sh"

# --- Global Flags & Early Utility Definitions ---
VERBOSE_FLAG="false"

log_info() { echo "ℹ️  $*"; }
log_success() { echo "✅ $*"; }
log_warning() { echo "⚠️  $*" >&2; } # Warnings to stderr
log_error() { echo "❌ $*" >&2; }   # Errors to stderr
log_verbose() { if [[ "$VERBOSE_FLAG" == "true" ]]; then echo "🔍 $*" >&2; fi; } # Verbose to stderr (FIXED)

_err_trap() {
    local exit_code=$?; local line_no=${1:-$LINENO}; local command_str="${BASH_COMMAND}"
    local func_stack=("${FUNCNAME[@]}"); local source_stack=("${BASH_SOURCE[@]}")
    if [[ "$command_str" == "exit"* || "$command_str" == *"_err_trap"* || "$exit_code" -eq 0 || "$command_str" == "return"* ]]; then return; fi
    echo; log_error "ERROR in $SCRIPT_NAME: Script exited with status $exit_code."
    log_error "Failed command: '$command_str' on line $line_no of file '${BASH_SOURCE[0]}'."
    if [[ ${#func_stack[@]} -gt 1 ]]; then
        log_error "Call Stack (most recent call first):"
        for i in $(seq 1 $((${#func_stack[@]} - 1))); do
            local func_idx=$((i)); local src_idx=$((i)); local line_idx=$((i-1))
            local func="${func_stack[$func_idx]}"; local src_file="${source_stack[$src_idx]}"; local src_line="${BASH_LINENO[$line_idx]}"
            log_error "  -> function '$func' in file '$src_file' at line $src_line"
        done
    fi
}
trap '_err_trap "${LINENO}"' ERR

set -euo pipefail

# --- Library Management Functions ---
get_remote_file_version() {
    local file_url="$1"; local version_grep_pattern="$2"; local timestamp cache_busted_url remote_script_content remote_version_line curl_exit_code
    log_verbose "Fetching remote version metadata from URL: $file_url"
    timestamp=$(date +%s); cache_busted_url="${file_url}?v=${timestamp}&nocache=$(date +%s%N 2>/dev/null || echo "$RANDOM")"
    log_verbose "Using cache-busted URL: $cache_busted_url"

    local curl_cmd_args=( # FIXED curl call
        --fail -sL
        -H "Cache-Control: no-cache, no-store, max-age=0, must-revalidate"
        -H "Pragma: no-cache"
        -H "Expires: 0"
        "$cache_busted_url"
    )
    set +e; remote_script_content=$(curl "${curl_cmd_args[@]}"); curl_exit_code=$?; set -e
    log_verbose "curl exit code for version fetch: $curl_exit_code"

    if [[ $curl_exit_code -ne 0 ]]; then log_warning "curl failed for '$file_url' (Code: $curl_exit_code)."; return 1; fi
    if [[ -z "$remote_script_content" ]]; then log_warning "Fetched content empty for '$file_url'."; return 1; fi
    remote_version_line=$(echo "$remote_script_content" | grep "$version_grep_pattern" || true)
    if [[ -z "$remote_version_line" ]]; then log_warning "No version (pattern: '$version_grep_pattern') in '$file_url'."; return 1; fi
    echo "$remote_version_line" | awk '{print $3}' # Only this goes to stdout
}

get_local_file_version() {
    local file_path="$1"; local version_grep_pattern="$2"; local version_line
    if [[ ! -f "$file_path" ]]; then return 1; fi
    version_line=$(grep "$version_grep_pattern" "$file_path" || echo "")
    if [[ -z "$version_line" ]]; then log_warning "No version (pattern: '$version_grep_pattern') in local '$file_path'."; return 1; fi
    echo "$version_line" | awk '{print $3}'
}

download_file() {
    local file_url="$1"; local local_path="$2"; local temp_file timestamp cache_busted_url
    log_info "Downloading '$file_url' to '$local_path'..."
    if ! temp_file=$(mktemp); then log_error "Failed to create temp file."; return 1; fi
    timestamp=$(date +%s); cache_busted_url="${file_url}?v=${timestamp}&nocache=$(date +%s%N 2>/dev/null || echo "$RANDOM")"
    log_verbose "Downloading from (cache-busted): $cache_busted_url"

    local curl_cmd_args=( # FIXED curl call
        --fail -sL
        -o "$temp_file"
        -H "Cache-Control: no-cache, no-store, max-age=0, must-revalidate"
        -H "Pragma: no-cache"
        -H "Expires: 0"
        "$cache_busted_url"
    )
    if ! curl "${curl_cmd_args[@]}"; then
        log_error "Failed to download from '$file_url' (curl exit: $?). Temp: $temp_file";
        rm -f "$temp_file"; # Clean up temp file on curl failure
        return 1;
    fi

    if [[ "$local_path" == *".sh" ]] && ! grep -qE "^#!/(bin/bash|usr/bin/env bash)|^# LibVersion:|^# Version:" "$temp_file"; then
        log_warning "Downloaded file '$temp_file' for '$local_path' may not be valid script.";
    fi
    if mv "$temp_file" "$local_path"; then
        if [[ "$local_path" == *".sh" ]]; then chmod +x "$local_path"; fi
        log_success "File '$local_path' downloaded."; return 0
    else
        log_error "Failed to move temp to '$local_path' (mv exit $?). Content at $temp_file"; return 1;
    fi
}

ensure_library_loaded() {
    local lib_key="$1"; IFS=' ' read -r lib_filename lib_url_var_name lib_version_var_name lib_version_grep_pattern <<< "${LIBRARIES_CONFIG[$lib_key]}"
    local lib_path="${LIB_DIR}/${lib_filename}"; local lib_url="${!lib_url_var_name}"
    log_verbose "Ensuring library '$lib_filename' is loaded..."
    if [[ ! -d "$LIB_DIR" ]]; then log_info "Creating lib dir: $LIB_DIR"; if ! mkdir -p "$LIB_DIR"; then log_error "Failed to create '$LIB_DIR'."; exit 1; fi; fi
    if [[ ! -f "$lib_path" ]]; then
        log_info "Library '$lib_filename' not found. Downloading..."
        if ! download_file "$lib_url" "$lib_path"; then log_error "Failed to download '$lib_filename'."; exit 1; fi
    fi
    if [[ -f "$lib_path" ]]; then
        source "$lib_path"; log_verbose "Library '$lib_filename' sourced."
        local current_lib_version=$(get_local_file_version "$lib_path" "$lib_version_grep_pattern" || echo "0.0.0-local")
        declare -g "$lib_version_var_name=$current_lib_version"; log_verbose "$lib_filename version: ${!lib_version_var_name}"
    else log_error "'$lib_filename' not found after download attempt."; exit 1; fi
}

temp_args=()
for arg in "$@"; do case "$arg" in --verbose) VERBOSE_FLAG="true";; *) temp_args+=("$arg");; esac; done
set -- "${temp_args[@]}"; ACTION="${1:-}"

log_verbose "Script directory: $SCRIPT_DIR"; log_verbose "Libraries directory: $LIB_DIR"
for lib_key in "${!LIBRARIES_CONFIG[@]}"; do ensure_library_loaded "$lib_key"; done

# --- VMID Parsing and Multi-VM Functions ---
parse_vmids() {
    local vmid_string="$1"
    local vmids=()

    # Split by comma and validate each VMID
    IFS=',' read -ra vmid_array <<< "$vmid_string"
    for vmid in "${vmid_array[@]}"; do
        # Trim whitespace
        vmid=$(echo "$vmid" | xargs)
        if ! [[ "$vmid" =~ ^[0-9]+$ ]]; then
            log_error "Invalid VMID: '$vmid' (must be numeric)"
            return 1
        fi
        vmids+=("$vmid")
    done

    # Return array as space-separated string
    echo "${vmids[@]}"
}

execute_multi_vm_action() {
    local action="$1"
    local vmids=("${@:2}")
    local success_count=0
    local failure_count=0
    local total_count=${#vmids[@]}

    # Temporarily disable error exit to handle failures gracefully
    set +e

    if [[ $total_count -gt 1 ]]; then
        log_info "Executing '$action' on $total_count VMs: ${vmids[*]}"
        echo
    fi

    for vmid in "${vmids[@]}"; do
        if [[ $total_count -gt 1 ]]; then
            echo "--- Processing VM $vmid ---"
        fi

        case "$action" in
            create)
                # For create action, use the first (and only) VMID since we validated it's single
                create_vm "$vmid" "$VM_NAME_SUFFIX"
                local result=$?
                if [[ $result -eq 0 ]]; then
                    ((success_count++))
                else
                    ((failure_count++))
                fi
                ;;
            destroy)
                destroy_vm "$vmid"
                local result=$?
                if [[ $result -eq 0 ]]; then
                    ((success_count++))
                else
                    ((failure_count++))
                fi
                ;;
            start)
                start_vm "$vmid"
                local result=$?
                if [[ $result -eq 0 ]]; then
                    ((success_count++))
                else
                    ((failure_count++))
                fi
                ;;
            stop)
                stop_vm "$vmid"
                local result=$?
                if [[ $result -eq 0 ]]; then
                    ((success_count++))
                else
                    ((failure_count++))
                fi
                ;;
            shutdown)
                shutdown_vm "$vmid"
                local result=$?
                if [[ $result -eq 0 ]]; then
                    ((success_count++))
                else
                    ((failure_count++))
                fi
                ;;
            restart)
                restart_vm "$vmid"
                local result=$?
                if [[ $result -eq 0 ]]; then
                    ((success_count++))
                else
                    ((failure_count++))
                fi
                ;;
            reboot)
                reboot_vm "$vmid"
                local result=$?
                if [[ $result -eq 0 ]]; then
                    ((success_count++))
                else
                    ((failure_count++))
                fi
                ;;
            mount)
                mount_iso "$vmid"
                local result=$?
                if [[ $result -eq 0 ]]; then
                    ((success_count++))
                else
                    ((failure_count++))
                fi
                ;;
            unmount)
                unmount_iso "$vmid"
                local result=$?
                if [[ $result -eq 0 ]]; then
                    ((success_count++))
                else
                    ((failure_count++))
                fi
                ;;
            *)
                log_error "Unknown action: $action"
                set -e  # Re-enable error exit before returning
                return 1
                ;;
        esac

        if [[ $total_count -gt 1 ]]; then
            echo
        fi
    done

    if [[ $total_count -gt 1 ]]; then
        echo "--- Summary ---"
        log_info "Action '$action' completed on $total_count VMs"
        if [[ $success_count -gt 0 ]]; then
            log_success "Successful: $success_count"
        fi
        if [[ $failure_count -gt 0 ]]; then
            log_error "Failed: $failure_count"
        fi
    fi

    # Re-enable error exit
    set -e

    # Return success only if all operations succeeded
    if [[ $failure_count -eq 0 ]]; then
        return 0
    else
        return 1
    fi
}

# --- Preflight Checks ---
check_dependencies() {
    log_verbose "Performing preflight dependency checks..."
    local missing_deps=()

    # Check for required commands
    local required_commands=("qm" "pvesh" "pvesm" "jq" "ssh" "curl")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_deps+=("$cmd")
        fi
    done

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
        log_error "Please install the missing dependencies and try again."
        return 1
    fi

    log_verbose "All required dependencies are available."
    return 0
}

# Run preflight checks for all actions except update and version
case "$ACTION" in
    update|version|--version|""|"-h"|"--help") ;;
    *)
        if ! check_dependencies; then
            log_error "Preflight checks failed. Exiting."
            exit 1
        fi
        ;;
esac

DEFAULT_VM_NAME_PREFIX="talos-k8s"; CORES=4; SOCKETS=1; RAM_MB=32768
DISK_OS_SIZE_GB=128; DISK_DATA_SIZE_GB=256; TALOS_ISO_PATH="local:iso/metal-amd64.iso"
STORAGE_POOL_EFI="local-lvm"; STORAGE_POOL_OS="local-lvm"; STORAGE_POOL_DATA="local-lvm"
NETWORK_BRIDGE="vmbr0"; OS_TYPE="l26"; MACHINE_TYPE="q35"; BIOS_TYPE="ovmf"; VGA_TYPE="serial0"

check_and_prompt_script_update() { # FIXED
    log_info "Checking for updates to main script ($SCRIPT_NAME)..."
    local remote_version
    remote_version=$(get_remote_file_version "$SCRIPT_RAW_URL" "^# Version:" || true)
    if [[ -z "$remote_version" ]]; then log_warning "Update check for $SCRIPT_NAME failed: no remote version."; return 1; fi

    log_verbose "Current $SCRIPT_NAME version: $SCRIPT_CURRENT_VERSION, Remote version: $remote_version"

    local comparison_result
    if compare_versions "$SCRIPT_CURRENT_VERSION" "$remote_version"; then
        comparison_result=0
    else
        comparison_result=$?
    fi
    log_verbose "Version comparison result: $comparison_result (0: remote newer, 1: equal, 2: local newer)"

    if [[ "$comparison_result" -eq 0 ]]; then
        log_success "A new version ($remote_version) of $SCRIPT_NAME is available! (Current: $SCRIPT_CURRENT_VERSION)"
        read -r -p "Download and install? (y/N): " choice
        if [[ "$choice" =~ ^[Yy]$ ]]; then
            if perform_main_script_update "$remote_version"; then
                log_success "$SCRIPT_NAME updated successfully!"
                log_info "📋 Reminder: Run '$0 update' again to check if libraries need updating."
                exit 0
            else log_error "Update for $SCRIPT_NAME failed."; return 1; fi
        else log_info "Update for $SCRIPT_NAME skipped."; return 2; fi
    elif [[ "$comparison_result" -eq 1 ]]; then
        log_info "$SCRIPT_NAME is already the latest version ($SCRIPT_CURRENT_VERSION)."
        return 0
    elif [[ "$comparison_result" -eq 2 ]]; then
        log_warning "Current $SCRIPT_NAME version ($SCRIPT_CURRENT_VERSION) > remote ($remote_version)."
        return 0
    else
        log_error "Unknown comparison_result ($comparison_result) for $SCRIPT_NAME."
        return 1
    fi
    log_error "Fallback return from check_and_prompt_script_update - logic error."; return 1
}

perform_main_script_update() {
    local new_version=$1; log_info "Attempting to update $SCRIPT_NAME to version $new_version..."
    local script_path="${SCRIPT_DIR}/${SCRIPT_NAME}"; local new_script_temp_path
    if ! new_script_temp_path=$(mktemp); then log_error "Failed to create temp file for update."; return 1; fi
    # The first download_file call was part of a more complex logic, simplified now.
    # We directly download to new_script_temp_path for self-update.
    log_info "Downloading new version of $SCRIPT_NAME to temporary location..." # This line was correct
    if ! download_file "$SCRIPT_RAW_URL" "$new_script_temp_path"; then
         log_error "Failed to download new version of $SCRIPT_NAME. Update aborted."; rm -f "$new_script_temp_path"; return 1; fi
    local downloaded_version=$(get_local_file_version "$new_script_temp_path" "^# Version:" || true)
    if [[ -z "$downloaded_version" ]]; then log_error "Could not extract version from downloaded script $new_script_temp_path."; rm -f "$new_script_temp_path"; return 1; fi
    if [[ "$downloaded_version" != "$new_version" ]]; then
        log_warning "Downloaded $SCRIPT_NAME version ($downloaded_version) mismatch expected ($new_version)."
        local comp_res; if compare_versions "$new_version" "$downloaded_version"; then comp_res=0; else comp_res=$?; fi
        if [[ "$comp_res" -eq 2 ]]; then log_error "Downloaded $SCRIPT_NAME older than expected."; rm -f "$new_script_temp_path"; return 1; fi
    fi
    log_verbose "New $SCRIPT_NAME ($downloaded_version) at $new_script_temp_path. Replacing $script_path..."
    if mv "$new_script_temp_path" "$script_path"; then
        chmod +x "$script_path"; return 0
    else log_error "Failed to replace $SCRIPT_NAME. New version at $new_script_temp_path"; return 1; fi
}

check_and_prompt_library_update() { # FIXED
    local lib_key="$1"; IFS=' ' read -r lib_filename lib_url_var_name lib_version_var_name lib_version_grep_pattern <<< "${LIBRARIES_CONFIG[$lib_key]}"
    local lib_path="${LIB_DIR}/${lib_filename}"; local lib_url="${!lib_url_var_name}"; local current_lib_version_val="${!lib_version_var_name}"
    log_info "Checking for updates to library '$lib_filename'..."
    local remote_lib_version=$(get_remote_file_version "$lib_url" "$lib_version_grep_pattern" || true)
    if [[ -z "$remote_lib_version" ]]; then log_warning "Update check for '$lib_filename' failed."; return 1; fi
    log_verbose "Current '$lib_filename' version: $current_lib_version_val, Remote version: $remote_lib_version"
    local comparison_result; if compare_versions "$current_lib_version_val" "$remote_lib_version"; then comparison_result=0; else comparison_result=$?; fi
    log_verbose "Library '$lib_filename' version comparison result: $comparison_result"
    if [[ "$comparison_result" -eq 0 ]]; then
        log_success "New version ($remote_lib_version) of '$lib_filename' available! (Current: $current_lib_version_val)"
        read -r -p "Download and install? (y/N): " choice
        if [[ "$choice" =~ ^[Yy]$ ]]; then
            if perform_library_update "$lib_key" "$remote_lib_version"; then
                log_success "'$lib_filename' updated."; declare -g "$lib_version_var_name=$remote_lib_version"
                log_info "You may need to re-run script or re-source library if behavior changed."
            else log_error "Update for '$lib_filename' failed."; fi
        else log_info "Update for '$lib_filename' skipped."; fi
    elif [[ "$comparison_result" -eq 1 ]]; then log_info "'$lib_filename' is latest ($current_lib_version_val)."
    elif [[ "$comparison_result" -eq 2 ]]; then log_warning "Current '$lib_filename' ($current_lib_version_val) > remote ($remote_lib_version)."
    else log_error "Unknown comparison_result ($comparison_result) for '$lib_filename'."; fi
    return 0 # check_and_prompt_library_update itself should return 0 unless it cannot check
}

perform_library_update() {
    local lib_key="$1"; local new_version="$2"
    IFS=' ' read -r lib_filename lib_url_var_name _ lib_version_grep_pattern <<< "${LIBRARIES_CONFIG[$lib_key]}"
    local lib_path="${LIB_DIR}/${lib_filename}"; local lib_url="${!lib_url_var_name}"
    log_info "Attempting to update library '$lib_filename' to version $new_version..."
    if ! download_file "$lib_url" "$lib_path"; then log_error "Failed to download '$lib_filename'."; return 1; fi
    local downloaded_version=$(get_local_file_version "$lib_path" "$lib_version_grep_pattern" || true)
    if [[ -z "$downloaded_version" ]]; then log_error "No version in new '$lib_filename'."; return 1; fi
    if [[ "$downloaded_version" != "$new_version" ]]; then
        log_warning "Downloaded '$lib_filename' version ($downloaded_version) != expected ($new_version)."
        local comp_res; if compare_versions "$new_version" "$downloaded_version"; then comp_res=0; else comp_res=$?; fi
        if [[ "$comp_res" -eq 2 ]]; then log_error "Downloaded '$lib_filename' older. Failed."; return 1; fi
    fi
    return 0
}

VMID_STRING=""; VMIDS=(); VM_NAME_SUFFIX=""
CORES_OPT=""; SOCKETS_OPT=""; RAM_MB_OPT=""; ISO_NAME_OPT=""
STORAGE_ISO_OPT=""; STORAGE_OS_OPT=""; STORAGE_EFI_OPT=""; STORAGE_DATA_OPT=""
VLAN_TAG_OPT=""; MAC_ADDRESS_OPT=""; FORCE_FLAG_OPT="false"; START_FLAG_OPT="false"

case "$ACTION" in
    list-iso) list_iso_storages; exit $?;;
    update)
        check_and_prompt_script_update; update_status_main_script=$?
        if [[ "$update_status_main_script" -eq 1 ]]; then log_error "Main script update failed."; exit 1;
        elif [[ "$update_status_main_script" -eq 2 ]]; then log_info "Main script update skipped."; fi
        log_info "Proceeding to check for library updates..."
        for lib_key_for_update in "${!LIBRARIES_CONFIG[@]}"; do check_and_prompt_library_update "$lib_key_for_update"; done
        log_info "Update check process finished."; exit 0 ;;
    version|--version)
        echo "$SCRIPT_NAME version $SCRIPT_CURRENT_VERSION"; echo "--- Library Versions ---"
        for lib_key_for_ver_display in "${!LIBRARIES_CONFIG[@]}"; do
            IFS=' ' read -r lib_filename _ lib_version_var_name _ <<< "${LIBRARIES_CONFIG[$lib_key_for_ver_display]}"
            echo "${lib_filename}: ${!lib_version_var_name}"; done; exit 0 ;;
    ""|"-h"|"--help") usage; exit 1 ;; # usage is in proxmox.lib.sh, it does not exit itself.
esac

case "$ACTION" in
    create|destroy|start|stop|shutdown|restart|reboot|mount|unmount)
        if [[ -z "${2:-}" ]]; then log_error "Action '$ACTION' needs VMID(s)."; usage; exit 1; fi
        VMID_STRING="$2"
        if ! VMIDS=($(parse_vmids "$VMID_STRING")); then
            log_error "Invalid VMID format: '$VMID_STRING'"
            log_error "Use single VMID (e.g., '1001') or comma-separated list (e.g., '1001,1002,1003')"
            usage
            exit 1
        fi
        ;;
    *) log_error "Invalid action '$ACTION'."; usage; exit 1 ;;
esac

# Validate that create action only accepts single VMID
if [[ "$ACTION" == "create" ]]; then
    if [[ ${#VMIDS[@]} -gt 1 ]]; then
        log_error "Action '$ACTION' only supports a single VMID, got: $VMID_STRING"
        usage
        exit 1
    fi
fi

param_offset=2
if [[ "$ACTION" == "create" ]]; then
    if [[ -n "${3:-}" && "${3::2}" != "--" ]]; then VM_NAME_SUFFIX="$3"; param_offset=3; else VM_NAME_SUFFIX="node"; fi
fi
shift "$param_offset"

if [[ "$ACTION" != "create" && "$ACTION" != "mount" && -n "$@" ]]; then log_warning "Action '$ACTION' ignores extra options: '$@'"; fi

if [[ "$ACTION" == "create" ]]; then
    for arg in "$@"; do
        case "$arg" in
            --cores=*) CORES_OPT="${arg#--cores=}"; if ! [[ "$CORES_OPT" =~ ^[0-9]+$ && "$CORES_OPT" -gt 0 ]]; then log_error "Invalid cores: '$CORES_OPT'"; usage; exit 1; fi;;
            --sockets=*) SOCKETS_OPT="${arg#--sockets=}"; if ! [[ "$SOCKETS_OPT" =~ ^[0-9]+$ && "$SOCKETS_OPT" -gt 0 ]]; then log_error "Invalid sockets: '$SOCKETS_OPT'"; usage; exit 1; fi;;
            --ram=*) RAM_MB_OPT="${arg#--ram=}"; if ! [[ "$RAM_MB_OPT" =~ ^[0-9]+$ && "$RAM_MB_OPT" -ge 512 ]]; then log_error "Invalid RAM: '$RAM_MB_OPT'"; usage; exit 1; fi;;
            --iso=*) ISO_NAME_OPT="${arg#--iso=}";;
            --storage-iso=*) STORAGE_ISO_OPT="${arg#--storage-iso=}";;
            --storage-os=*) STORAGE_OS_OPT="${arg#--storage-os=}";;
            --storage-data=*) STORAGE_DATA_OPT="${arg#--storage-data=}";;
            --vlan=*) VLAN_TAG_OPT="${arg#--vlan=}"; if ! [[ "$VLAN_TAG_OPT" =~ ^[0-9]+$ && "$VLAN_TAG_OPT" -ge 1 && "$VLAN_TAG_OPT" -le 4094 ]]; then log_error "Invalid VLAN: '$VLAN_TAG_OPT'"; usage; exit 1; fi;;
            --mac-address=*) MAC_ADDRESS_OPT="${arg#--mac-address=}"; if ! [[ "$MAC_ADDRESS_OPT" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then log_error "Invalid MAC address format: '$MAC_ADDRESS_OPT'. Expected format: XX:XX:XX:XX:XX:XX"; usage; exit 1; fi;;
            --force) FORCE_FLAG_OPT="true";;
            --start) START_FLAG_OPT="true";;
            *) if [[ "$arg" != "--verbose" ]]; then log_warning "Unknown param '$arg' for 'create'."; fi;;
        esac
    done
fi

if [[ "$ACTION" == "mount" ]]; then
    for arg in "$@"; do
        case "$arg" in
            --iso=*) ISO_NAME_OPT="${arg#--iso=}";;
            --storage-iso=*) STORAGE_ISO_OPT="${arg#--storage-iso=}";;
            *) if [[ "$arg" != "--verbose" ]]; then log_warning "Unknown param '$arg' for 'mount'."; fi;;
        esac
    done

    # Validate that --iso is provided for mount action
    if [[ -z "${ISO_NAME_OPT:-}" ]]; then
        log_error "Mount action requires --iso option to specify ISO file to mount."
        usage
        exit 1
    fi
fi

case "$ACTION" in
    create) execute_multi_vm_action "$ACTION" "${VMIDS[@]}"; exit $?;;
    destroy) execute_multi_vm_action "$ACTION" "${VMIDS[@]}"; exit $?;;
    start) execute_multi_vm_action "$ACTION" "${VMIDS[@]}"; exit $?;;
    stop) execute_multi_vm_action "$ACTION" "${VMIDS[@]}"; exit $?;;
    shutdown) execute_multi_vm_action "$ACTION" "${VMIDS[@]}"; exit $?;;
    restart) execute_multi_vm_action "$ACTION" "${VMIDS[@]}"; exit $?;;
    reboot) execute_multi_vm_action "$ACTION" "${VMIDS[@]}"; exit $?;;
    mount) execute_multi_vm_action "$ACTION" "${VMIDS[@]}"; exit $?;;
    unmount) execute_multi_vm_action "$ACTION" "${VMIDS[@]}"; exit $?;;
    *) log_error "Internal error: Unhandled action '$ACTION'."; usage; exit 1;;
esac

exit 0
