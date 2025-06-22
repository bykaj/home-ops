#!/usr/bin/env bash

# To download: `curl -O https://gist.githubusercontent.com/QNimbus/12b7b0651e196f1a80f1a7f6de66811e/raw/talos_download.sh`
# To run: `chmod +x talos_download.sh && ./talos_download.sh --id <your-schematic-id>`

# ====================================================
# Talos Linux ISO Download Script
# ====================================================
#
# Author:      B. van Wetten <git@bvw.email>
# Version:     1.0.9
# Created:     2025-06-19
# Updated:     2025-06-19
#
# This script automates the download of Talos Linux ISOs.
# It uses shared libraries for common utilities and Proxmox interactions.
#
# Features:
# - Downloads custom Talos ISOs using schematic IDs
# - Integrates with Proxmox storage for ISO placement (uses proxmox.lib.sh)
# - Shows download progress and verifies file integrity
# - Supports version selection
# - Self-update mechanism for script and libraries
#
# Requirements:
# - Proxmox VE with pvesm command available
# - curl, jq and numfmt commands
# - ./lib/utils.lib.sh and ./lib/proxmox.lib.sh
# ====================================================

# --- Script Metadata for Updates ---
SCRIPT_NAME=$(basename "$0")
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
SCRIPT_CURRENT_VERSION_LINE=$(grep '^# Version:' "$0" || echo "# Version: 0.0.0-local")
SCRIPT_CURRENT_VERSION=$(echo "$SCRIPT_CURRENT_VERSION_LINE" | awk '{print $3}')
SCRIPT_RAW_URL="https://gist.githubusercontent.com/QNimbus/12b7b0651e196f1a80f1a7f6de66811e/raw/talos_download.sh"

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

VERBOSE_FLAG="false"

log_info() { echo "ℹ️  $*"; }
log_success() { echo "✅ $*"; }
log_warning() { echo "⚠️  $*" >&2; }
log_error() { echo "❌ $*" >&2; }
log_verbose() { if [[ "$VERBOSE_FLAG" == "true" ]]; then echo "🔍 $*" >&2; fi; }

restore_cursor() {
    printf "\033[?25h"
}

_err_trap() {
    local exit_code=$?
    local line_no=${1:-$LINENO}
    local command_str="${BASH_COMMAND}"
    local func_stack=("${FUNCNAME[@]}")
    local source_stack=("${BASH_SOURCE[@]}")
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
    restore_cursor
}

trap '_err_trap "${LINENO}"' ERR
trap restore_cursor EXIT SIGINT SIGTERM

set -euo pipefail

get_remote_file_version() {
    local file_url="$1"; local version_grep_pattern="$2"; local timestamp cache_busted_url remote_script_content remote_version_line
    log_verbose "Fetching remote version metadata from URL: $file_url" # General verbose message
    timestamp=$(date +%s); cache_busted_url="${file_url}?v=${timestamp}&nocache=$(date +%s%N 2>/dev/null || echo "$RANDOM")"
    log_verbose "Using cache-busted URL: $cache_busted_url"
    local curl_cmd_args=(--fail -sL -H "Cache-Control: no-cache, no-store, max-age=0, must-revalidate" -H "Pragma: no-cache" -H "Expires: 0" "$cache_busted_url")

    # Use a subshell to avoid affecting the main shell's error handling
    _curl_result=$(
        set +o pipefail
        curl "${curl_cmd_args[@]}"
        echo "EXIT_CODE:$?"
    )

    # Parse the output to separate content from exit code
    remote_script_content=$(echo "$_curl_result" | grep -v '^EXIT_CODE:')
    curl_exit_code=$(echo "$_curl_result" | grep '^EXIT_CODE:' | cut -d: -f2)

    log_verbose "curl exit code for version fetch: $curl_exit_code"
    if [[ $curl_exit_code -ne 0 ]]; then log_warning "curl failed for '$file_url' (Code: $curl_exit_code)."; return 1; fi
    if [[ -z "$remote_script_content" ]]; then log_warning "Fetched content empty for '$file_url'."; return 1; fi
    remote_version_line=$(echo "$remote_script_content" | grep "$version_grep_pattern" || true)
    if [[ -z "$remote_version_line" ]]; then log_warning "No version (pattern: '$version_grep_pattern') in '$file_url'."; return 1; fi
    echo "$remote_version_line" | awk '{print $3}'
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
    local curl_cmd_args=( --fail -sL -o "$temp_file" -H "Cache-Control: no-cache, no-store, max-age=0, must-revalidate" -H "Pragma: no-cache" -H "Expires: 0" "$cache_busted_url")
    if ! curl "${curl_cmd_args[@]}"; then log_error "Failed to download from '$file_url' (curl exit: $?). Temp: $temp_file"; return 1; fi
    # Check if the file is a shell script and contains expected markers
    if [[ "$local_path" == *".sh" ]]; then
        # Look for a shebang or version markers for validation
        if ! grep -qE "^#!/bin/bash|^#!/usr/bin/env bash" "$temp_file" && \
           ! grep -qE "^# LibVersion:" "$temp_file" && \
           ! grep -qE "^# Version:" "$temp_file"; then
            log_warning "Downloaded file '$temp_file' for '$local_path' may not be valid script."
        fi
    fi
    if mv "$temp_file" "$local_path"; then
        if [[ "$local_path" == *".sh" ]]; then chmod +x "$local_path"; fi
        log_success "File '$local_path' downloaded."; return 0
    else log_error "Failed to move temp to '$local_path' (mv exit $?). Content at $temp_file"; return 1; fi
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
        # shellcheck source=/dev/null
        source "$lib_path"; log_verbose "Library '$lib_filename' sourced."
        local current_lib_version=$(get_local_file_version "$lib_path" "$lib_version_grep_pattern" || echo "0.0.0-local")
        declare -g "$lib_version_var_name=$current_lib_version"; log_verbose "$lib_filename version: ${!lib_version_var_name}"
    else log_error "'$lib_filename' not found after download attempt."; exit 1; fi
}

for lib_key in "${!LIBRARIES_CONFIG[@]}"; do
    ensure_library_loaded "$lib_key"
done

check_and_prompt_script_update() {
    log_info "Checking for updates to $SCRIPT_NAME..."
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

    if [[ "$comparison_result" -eq 0 ]]; then # Current < Remote
        log_success "A new version ($remote_version) of $SCRIPT_NAME is available! (Current: $SCRIPT_CURRENT_VERSION)"
        read -r -p "Do you want to download and install it now? (y/N): " choice
        if [[ "$choice" =~ ^[Yy]$ ]]; then
            if perform_main_script_update "$remote_version"; then
                log_success "$SCRIPT_NAME updated successfully. Please re-run: $0 $*"; exit 0
            else log_error "Update process for $SCRIPT_NAME failed."; return 1; fi
        else log_info "Update for $SCRIPT_NAME skipped by user."; return 2; fi
    elif [[ "$comparison_result" -eq 1 ]]; then # Current == Remote
        log_info "$SCRIPT_NAME is already the latest version ($SCRIPT_CURRENT_VERSION)."
        return 0
    elif [[ "$comparison_result" -eq 2 ]]; then # Current > Remote
        log_warning "Your current $SCRIPT_NAME version ($SCRIPT_CURRENT_VERSION) seems newer than remote ($remote_version)."
        return 0
    else
        log_error "Unknown comparison_result ($comparison_result) from version comparison for $SCRIPT_NAME."
        return 1
    fi
    log_error "Fallback return from check_and_prompt_script_update - logic error." # Should not be reached
    return 1
}

perform_main_script_update() {
    local new_version=$1; log_info "Attempting to update $SCRIPT_NAME to version $new_version..."
    local script_path="${SCRIPT_DIR}/${SCRIPT_NAME}"; local new_script_temp_path
    if ! new_script_temp_path=$(mktemp); then log_error "Failed to create temp file for update."; return 1; fi
    if ! download_file "$SCRIPT_RAW_URL" "$new_script_temp_path"; then log_error "Failed to download new $SCRIPT_NAME."; rm -f "$new_script_temp_path"; return 1; fi
    local downloaded_version=$(get_local_file_version "$new_script_temp_path" "^# Version:" || true)
    if [[ -z "$downloaded_version" ]]; then log_error "Could not extract version from downloaded $SCRIPT_NAME."; rm -f "$new_script_temp_path"; return 1; fi
    if [[ "$downloaded_version" != "$new_version" ]]; then
        log_warning "Downloaded $SCRIPT_NAME version ($downloaded_version) mismatch expected ($new_version)."
        local comp_res; if compare_versions "$new_version" "$downloaded_version"; then comp_res=0; else comp_res=$?; fi
        if [[ "$comp_res" -eq 2 ]]; then log_error "Downloaded $SCRIPT_NAME older than expected."; rm -f "$new_script_temp_path"; return 1; fi
    fi
    log_verbose "New version of $SCRIPT_NAME ($downloaded_version) downloaded to $new_script_temp_path. Replacing $script_path..."
    if mv "$new_script_temp_path" "$script_path"; then chmod +x "$script_path"; return 0;
    else log_error "Failed to replace $SCRIPT_NAME. New version at $new_script_temp_path"; return 1; fi
}

check_and_prompt_library_update() {
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
            else log_error "Update for '$lib_filename' failed."; fi
        else log_info "Update for '$lib_filename' skipped."; fi
    elif [[ "$comparison_result" -eq 1 ]]; then log_info "'$lib_filename' is latest ($current_lib_version_val)."
    elif [[ "$comparison_result" -eq 2 ]]; then log_warning "Current '$lib_filename' ($current_lib_version_val) > remote ($remote_lib_version)."
    else log_error "Unknown comparison_result ($comparison_result) for '$lib_filename'."; fi
    return 0
}

perform_library_update() {
    local lib_key="$1"; local new_version="$2"
    IFS=' ' read -r lib_filename lib_url_var_name _ lib_version_grep_pattern <<< "${LIBRARIES_CONFIG[$lib_key]}"
    local lib_path="${LIB_DIR}/${lib_filename}"; local lib_url="${!lib_url_var_name}"
    log_info "Updating '$lib_filename' to $new_version..."
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

DEFAULT_TALOS_VERSION="v1.10.4"
DEFAULT_IMAGE_TYPE="metal-amd64"
SCHEMATIC_ID=""
TALOS_VERSION="$DEFAULT_TALOS_VERSION"
IMAGE_TYPE="$DEFAULT_IMAGE_TYPE"
FORCE_MODE=false
PROXMOX_STORAGE=""
ACTION=""

usage() {
    echo "Usage: $SCRIPT_NAME --schematic-id <id> [OPTIONS]" >&2
    echo "       $SCRIPT_NAME --id <id> [OPTIONS]" >&2
    echo "       $SCRIPT_NAME update [--verbose]" >&2; echo "" >&2
    echo "Required Arguments for download:" >&2
    echo "  --schematic-id <id>, --id <id>  Talos schematic ID (64-char hex)" >&2; echo "" >&2
    echo "Optional Arguments for download:" >&2
    echo "  --version <version>      Talos version (default: $DEFAULT_TALOS_VERSION)" >&2
    echo "  --image-type <type>      Image type (default: $DEFAULT_IMAGE_TYPE)" >&2
    echo "  --force                  Overwrite existing ISO file" >&2
    echo "  --storage <storage>      Proxmox storage (default: auto-detect)" >&2; echo "" >&2
    echo "Other Actions:" >&2
    echo "  update                   Check for updates to this script and its libraries." >&2
    echo "    --verbose              Enable verbose output during update." >&2; echo "" >&2
    echo "Examples:" >&2
    echo "  $SCRIPT_NAME --id ce4c...c7515" >&2
    echo "  $SCRIPT_NAME --id ce4c...c7515 --version v1.7.4" >&2
    echo "  $SCRIPT_NAME update --verbose" >&2
    exit 1
}

if [[ "${1:-}" == "update" ]]; then
    ACTION="update"; shift
    if [[ "${1:-}" == "--verbose" ]]; then VERBOSE_FLAG="true"; log_verbose "Verbose mode enabled for update process."; shift; fi
else
    if [[ $# -eq 0 ]]; then usage; fi
    _idx=0; TALOS_VERSION="$DEFAULT_TALOS_VERSION"; IMAGE_TYPE="$DEFAULT_IMAGE_TYPE"; FORCE_MODE=false; PROXMOX_STORAGE=""; SCHEMATIC_ID=""
    while [[ $_idx -lt $# ]]; do
        _current_arg="${!((_idx + 1))}"; _next_arg="${!((_idx + 2))}"
        case "$_current_arg" in
            --schematic-id|--id) if [[ -z "$_next_arg" ]] || [[ "$_next_arg" == --* ]]; then log_error "$_current_arg needs value."; usage; fi; SCHEMATIC_ID="$_next_arg"; _idx=$((_idx + 1)) ;;
            --version) if [[ -z "$_next_arg" ]] || [[ "$_next_arg" == --* ]]; then log_error "$_current_arg needs value."; usage; fi; TALOS_VERSION="$_next_arg"; _idx=$((_idx + 1)) ;;
            --image-type) if [[ -z "$_next_arg" ]] || [[ "$_next_arg" == --* ]]; then log_error "$_current_arg needs value."; usage; fi; IMAGE_TYPE="$_next_arg"; _idx=$((_idx + 1)) ;;
            --force) FORCE_MODE=true ;;
            --storage) if [[ -z "$_next_arg" ]] || [[ "$_next_arg" == --* ]]; then log_error "$_current_arg needs value."; usage; fi; PROXMOX_STORAGE="$_next_arg"; _idx=$((_idx + 1)) ;;
            -h|--help) usage ;;
            *) log_error "Unknown option: $_current_arg"; usage ;;
        esac; _idx=$((_idx + 1))
    done; ACTION="download"
fi

if [[ "$ACTION" == "update" ]]; then
    check_and_prompt_script_update; update_status_main_script=$?
    if [[ "$update_status_main_script" -eq 1 ]]; then log_error "Main script update failed."; exit 1;
    elif [[ "$update_status_main_script" -eq 2 ]]; then log_info "Main script update skipped."; fi
    log_info "Proceeding to check for library updates..."
    for lib_key_for_update in "${!LIBRARIES_CONFIG[@]}"; do check_and_prompt_library_update "$lib_key_for_update"; done
    log_info "Update check process finished."; exit 0
fi

if [[ "$ACTION" == "download" ]]; then
    if [[ -z "$SCHEMATIC_ID" ]]; then log_error "--schematic-id required."; usage; fi
    if [[ ! "$SCHEMATIC_ID" =~ ^[a-f0-9]{64}$ ]]; then log_error "Invalid schematic ID format."; exit 1; fi
    log_info "=== Talos Linux ISO Download Script ==="; log_info "Schematic ID: $SCHEMATIC_ID"; log_info "Version: $TALOS_VERSION"
    log_info "Image Type: $IMAGE_TYPE"; if [[ "$FORCE_MODE" == "true" ]]; then log_info "Force mode enabled"; fi
    log_info "======================================="
    LOG_FILE="${SCRIPT_DIR}/talos_download_output.log"
    if ! touch "$LOG_FILE" 2>/dev/null; then log_error "Cannot write to log file $LOG_FILE."; exit 1; fi
    echo "$(date): Starting Talos ISO download - SID: $SCHEMATIC_ID, Ver: $TALOS_VERSION" > "$LOG_FILE"

    preflight_checks() {
        log_info "Performing preflight checks..."; local check_ok=true
        for cmd_check in curl pvesm jq numfmt; do if ! command -v "$cmd_check" &> /dev/null; then log_error "'$cmd_check' not found."; check_ok=false; fi; done
        if ! curl -s --connect-timeout 5 https://factory.talos.dev/ >/dev/null; then log_error "No connection to factory.talos.dev."; check_ok=false; fi
        if [[ "$check_ok" == "false" ]]; then exit 1; fi; log_success "✓ Preflight checks passed."
    }
    get_storage_path() {
        local storage_name=$1; log_info "Getting storage path for '$storage_name'..."
        local storage_details=$(pvesh get "/storage/${storage_name}" --output-format=json 2>/dev/null || { log_error "Failed to get details for '$storage_name'."; return 1; })
        local storage_physical_path=$(echo "$storage_details" | jq -r '.path // .export // ""' 2>/dev/null)
        if [[ -z "$storage_physical_path" ]]; then log_error "No physical path for '$storage_name'."; log_verbose "Details: $storage_details"; exit 1; fi
        local iso_dir_path="${storage_physical_path}/template/iso"
        if [[ ! -d "$iso_dir_path" ]]; then
            log_info "Attempting to create ISO dir: $iso_dir_path"
            if ! mkdir -p "$iso_dir_path"; then log_error "Failed to create ISO dir: $iso_dir_path"; exit 1; fi
            log_success "Created ISO dir: $iso_dir_path"
        fi; log_success "✓ Storage ISO path: $iso_dir_path"; echo "$iso_dir_path"
    }
    verify_schematic() {
        local sid=$1 ver=$2 img_type=$3; log_info "Verifying schematic $sid / $ver / $img_type..."
        local test_url="https://factory.talos.dev/image/${sid}/${ver}/${img_type}.iso"
        if ! curl -s --head --fail "$test_url" >/dev/null 2>&1; then log_error "Schematic/version/type not found: $test_url"; exit 1; fi
        log_success "✓ Schematic verified."
    }
    download_iso_file() {
        local sid=$1 ver=$2 store_path=$3 force=$4 img_type=$5
        local download_url="https://factory.talos.dev/image/${sid}/${ver}/${img_type}.iso"; local filename=$(basename "$download_url")
        local full_path="${store_path}/${filename}"; local id_file="${full_path}.id"
        log_info "Download URL: $download_url"; log_info "Target file: $full_path"
        if [[ -f "$full_path" && "$force" != "true" ]]; then log_error "File exists: $full_path. Use --force."; exit 1; fi
        if [[ -f "$full_path" && "$force" == "true" ]]; then log_warning "Overwriting: $full_path"; echo "$(date): Overwriting: $full_path" >> "$LOG_FILE"; fi
        log_info "Starting ISO download..."; echo "$(date): Downloading $download_url to $full_path" >> "$LOG_FILE"; printf "\033[?25l"
        local curl_dl_args=(-L --fail --progress-bar -o "$full_path" "$download_url")
        if ! curl "${curl_dl_args[@]}"; then restore_cursor; echo ""; log_error "Download failed."; [[ -f "$full_path" ]] && rm -f "$full_path"; exit 1; fi
        restore_cursor; echo ""; log_success "✓ Download completed."
        local file_size
        if ! file_size=$(stat -f%z "$full_path" 2>/dev/null); then
            if ! file_size=$(stat -c%s "$full_path" 2>/dev/null); then
                log_warning "Could not determine file size for $full_path. Defaulting to 0."
                file_size="0"
            fi
        fi
        if [[ "$file_size" -lt 1000000 ]]; then log_error "File too small ($file_size B). Failed?"; rm -f "$full_path"; exit 1; fi
        log_info "File size: $(numfmt --to=iec-i --suffix=B "$file_size")"; echo "$(date): Downloaded. Size: $file_size B" >> "$LOG_FILE"
        log_info "Creating ID file: $id_file"; echo "$sid" > "$id_file"
        if [[ $? -eq 0 ]]; then log_success "✓ ID saved."; echo "$(date): ID saved to $id_file" >> "$LOG_FILE";
        else log_warning "No ID file $id_file"; echo "$(date): Warn: no ID file $id_file" >> "$LOG_FILE"; fi; echo "$full_path"
    }
    check_iso_in_proxmox() {
        local storage_name=$1 iso_filename_to_check=$2; log_info "Verifying ISO '$iso_filename_to_check' in Proxmox '$storage_name'..."
        local retries=3 delay=3; for attempt in $(seq 1 $retries); do
            if pvesm list "$storage_name" --content iso 2>/dev/null | grep -q "${storage_name}:iso/${iso_filename_to_check}"; then
                log_success "✓ ISO '$iso_filename_to_check' visible in Proxmox '$storage_name'."; return 0; fi
            if [[ $attempt -lt $retries ]]; then log_verbose "Attempt $attempt: ISO not visible. Retrying..."; sleep $delay; fi
        done; log_warning "ISO '$iso_filename_to_check' not visible in Proxmox '$storage_name' after $retries attempts."; return 1
    }

    preflight_checks
    FINAL_PROXMOX_STORAGE_NAME=""
    if [[ -n "$PROXMOX_STORAGE" ]]; then
        FINAL_PROXMOX_STORAGE_NAME="$PROXMOX_STORAGE"
        log_info "Using specified Proxmox storage: $FINAL_PROXMOX_STORAGE_NAME"
    else
        # Use a subshell to avoid affecting the main shell's pipefail state
        _detect_result=$(
            set +o pipefail
            detect_iso_storage
            echo "EXIT_CODE:$?"
        )
        _detected_storage_output=$(echo "$_detect_result" | grep -v '^EXIT_CODE:')
        _detect_exit_status=$(echo "$_detect_result" | grep '^EXIT_CODE:' | cut -d: -f2)
        if [[ $_detect_exit_status -ne 0 ]] || [[ -z "$_detected_storage_output" ]] || [[ "$_detected_storage_output" == *"Error:"* ]]; then
            log_error "Failed to auto-detect ISO storage."
            log_verbose "Output: $_detected_storage_output"
            exit 1
        fi
        FINAL_PROXMOX_STORAGE_NAME=$(echo "$_detected_storage_output" | tail -n 1)
        log_info "Auto-detected Proxmox ISO storage: $FINAL_PROXMOX_STORAGE_NAME"
    fi
    TARGET_STORAGE_PHYSICAL_PATH=$(get_storage_path "$FINAL_PROXMOX_STORAGE_NAME")
    verify_schematic "$SCHEMATIC_ID" "$TALOS_VERSION" "$IMAGE_TYPE"
    DOWNLOADED_ISO_FULL_PATH=$(download_iso_file "$SCHEMATIC_ID" "$TALOS_VERSION" "$TARGET_STORAGE_PHYSICAL_PATH" "$FORCE_MODE" "$IMAGE_TYPE")
    ISO_FILENAME_ONLY=$(basename "$DOWNLOADED_ISO_FULL_PATH")
    check_iso_in_proxmox "$FINAL_PROXMOX_STORAGE_NAME" "$ISO_FILENAME_ONLY"
    log_success "===== Talos ISO Download Complete ====="
    log_info "  Schematic ID: $SCHEMATIC_ID"; log_info "  Version: $TALOS_VERSION"; log_info "  Image Type: $IMAGE_TYPE"
    log_info "  Storage: $FINAL_PROXMOX_STORAGE_NAME"; log_info "  Final path: $DOWNLOADED_ISO_FULL_PATH"
    log_info ""; log_info "ISO should be available in Proxmox."; echo "$(date): Talos ISO download complete: $DOWNLOADED_ISO_FULL_PATH" >> "$LOG_FILE"
    exit 0
fi
log_error "Invalid script state or unknown action: '$ACTION'."
usage
