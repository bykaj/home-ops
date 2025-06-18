#!/usr/bin/env bash

# To download: `curl -O https://gist.githubusercontent.com/QNimbus/12b7b0651e196f1a80f1a7f6de66811e/raw/talos_download.sh`
# To run: `curl -s https://gist.githubusercontent.com/QNimbus/12b7b0651e196f1a80f1a7f6de66811e/raw/talos_download.sh > talos_download.sh && chmod +x talos_download.sh && ./talos_download.sh`

# ====================================================
# Talos Linux ISO Download Script
# ====================================================
#
# This script automates the download of Talos Linux ISOs from the factory service.
# It performs the following operations:
# 1. Downloads custom Talos ISOs using schematic IDs
# 2. Integrates with Proxmox storage for ISO placement
# 3. Shows download progress and verifies file integrity
# 4. Supports version selection with latest version detection
#
# Requirements:
# - Proxmox VE with pvesm command available
# - Internet connectivity to factory.talos.dev
# - Sufficient storage space for ISO files
# - curl command for downloading files
#
# Usage: ./talos_download.sh --schematic-id <id> [--version <version>] [--force]
#
# Output: Downloads ISO to Proxmox ISO storage and creates log file
# ====================================================

# Function to display usage information
usage() {
    echo "Usage: $0 --schematic-id <schematic-id> [OPTIONS]"
    echo "       $0 --id <schematic-id> [OPTIONS]"
    echo ""
    echo "Required Arguments:"
    echo "  --schematic-id <id>      Talos schematic ID from factory.talos.dev (64-character hex string)"
    echo "  --id <id>                Short alias for --schematic-id"
    echo ""
    echo "Optional Arguments:"
    echo "  --version <version>      Talos version to download (default: v1.10.3)"
    echo "  --image-type <type>      Image type to download (default: nocloud-amd64)"
    echo "  --force                  Overwrite existing ISO file if it exists"
    echo "  --storage <storage>      Proxmox storage to use (default: auto-detect ISO storage)"
    echo ""
    echo "Examples:"
    echo "  $0 --schematic-id ce4c9805...c7515"
    echo "  $0 --id ce4c9805...c7515 --version v1.9.0"
    echo "  $0 --id ce4c9805...c7515 --image-type metal-amd64"
    echo "  $0 --id ce4c9805...c7515 --force"
    echo ""
    echo "Note: Get schematic IDs from https://factory.talos.dev/"
    exit 1
}

# Default configuration values
DEFAULT_VERSION="v1.10.4"
DEFAULT_IMAGE_TYPE="metal-amd64"
SCHEMATIC_ID=""
VERSION="$DEFAULT_VERSION"
IMAGE_TYPE="$DEFAULT_IMAGE_TYPE"
FORCE_MODE=false
STORAGE=""

# Parse and validate command-line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --schematic-id|--id)
            if [[ -z "$2" ]]; then
                echo "Error: $1 flag requires a value" >&2
                exit 1
            fi
            SCHEMATIC_ID="$2"
            shift 2
            ;;
        --version)
            if [[ -z "$2" ]]; then
                echo "Error: --version flag requires a value" >&2
                exit 1
            fi
            VERSION="$2"
            shift 2
            ;;
        --image-type)
            if [[ -z "$2" ]]; then
                echo "Error: --image-type flag requires a value" >&2
                exit 1
            fi
            IMAGE_TYPE="$2"
            shift 2
            ;;
        --force)
            FORCE_MODE=true
            shift
            ;;
        --storage)
            if [[ -z "$2" ]]; then
                echo "Error: --storage flag requires a value" >&2
                exit 1
            fi
            STORAGE="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage
            ;;
    esac
done

# Validate required arguments
if [[ -z "$SCHEMATIC_ID" ]]; then
    echo "Error: --schematic-id is required" >&2
    usage
fi

# Validate schematic ID format (64-character hex string)
if [[ ! "$SCHEMATIC_ID" =~ ^[a-f0-9]{64}$ ]]; then
    echo "Error: Invalid schematic ID format. Must be a 64-character hexadecimal string." >&2
    echo "Example: ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515" >&2
    exit 1
fi

# Exit immediately if a command exits with a non-zero status
set -euo pipefail

echo "=== Talos Linux ISO Download Script ==="
echo "Schematic ID: $SCHEMATIC_ID"
echo "Version: $VERSION"
echo "Image Type: $IMAGE_TYPE"
if [[ "$FORCE_MODE" == "true" ]]; then
    echo "Force mode enabled - existing files will be overwritten"
fi
echo "Downloading from factory.talos.dev..."
echo "======================================="

# Function for preflight checks
preflight_checks() {
    echo "Performing preflight checks..."

    if ! command -v curl &> /dev/null; then
        echo "Error: 'curl' command not found. Please install curl." >&2
        echo "To install curl on Debian/Ubuntu systems: 'apt update && apt install -y curl'" >&2
        exit 1
    fi

    if ! command -v pvesm &> /dev/null; then
        echo "Error: 'pvesm' command not found. Please ensure Proxmox VE CLI tools are installed." >&2
        exit 1
    fi

    if ! command -v jq &> /dev/null; then
        echo "Error: 'jq' command not found. Please install jq for JSON parsing." >&2
        echo "To install jq on Debian/Ubuntu systems: 'apt update && apt install -y jq'" >&2
        exit 1
    fi

    # Test internet connectivity to factory.talos.dev
    if ! curl -s --connect-timeout 10 --retry 3 --retry-delay 5 https://factory.talos.dev/ >/dev/null; then
        echo "Error: Cannot connect to factory.talos.dev. Check internet connectivity." >&2
        exit 1
    fi

    echo "✓ Required tools are available and connectivity verified"
}

# Function to restore cursor visibility
restore_cursor() {
    printf "\033[?25h"  # Show cursor
}

# Ensure cursor is restored on script exit
trap restore_cursor EXIT

# Function to display spinner while command executes
spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    printf "\033[?25l"  # Hide cursor
    while kill -0 $pid 2>/dev/null; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
    printf "\033[?25h"  # Show cursor
}

# Function to run command with spinner and log output
run_with_spinner() {
    local desc=$1
    local cmd=$2
    printf "%-50s" "$desc"
    echo "$(date): $desc - COMMAND: $cmd" >> "$LOG_FILE"
    bash -c "$cmd" >> "$LOG_FILE" 2>&1 &
    local pid=$!
    spinner $pid
    wait $pid
    local status=$?
    if [ $status -eq 0 ]; then
        echo "[DONE]"
    else
        echo "[FAILED] - Check $LOG_FILE for details"
        exit 1
    fi
}

# Function to detect ISO storage in Proxmox
detect_iso_storage() {
    echo "Detecting Proxmox ISO storage..." >&2

    # Get all storage with ISO content type
    local iso_storages=$(pvesm status --content iso 2>/dev/null | tail -n +2 | awk '{print $1}' || echo "")

    if [[ -z "$iso_storages" ]]; then
        echo "Error: No ISO storage found in Proxmox configuration." >&2
        echo "Please configure at least one storage with 'iso' content type." >&2
        exit 1
    fi

    # Use the first available ISO storage
    local selected_storage=$(echo "$iso_storages" | head -n 1)
    echo "✓ Using ISO storage: $selected_storage" >&2
    echo "$selected_storage"
}

# Function to get storage path
get_storage_path() {
    local storage_name=$1
    echo "Getting storage path for $storage_name..." >&2

    # Get storage config and extract path
    local storage_path=$(pvesh get /storage/$storage_name --output-format=json 2>/dev/null | jq -r '.path // .export' 2>/dev/null || echo "")

    if [[ -z "$storage_path" ]]; then
        echo "Error: Could not determine path for storage '$storage_name'." >&2
        echo "Please check storage configuration with: pvesh get /storage/$storage_name" >&2
        exit 1
    fi

    # Ensure the iso subdirectory exists
    local iso_path="${storage_path}/template/iso"
    if [[ ! -d "$iso_path" ]]; then
        echo "Creating ISO directory: $iso_path" >&2
        if ! mkdir -p "$iso_path" 2>/dev/null; then
            echo "Error: Failed to create ISO directory. Check permissions or disk space." >&2
            echo "Attempted path: $iso_path" >&2
            exit 1
        fi
    fi

    echo "✓ Storage path: $iso_path" >&2
    echo "$iso_path"
}

# Function to verify schematic exists on factory.talos.dev
verify_schematic() {
    local schematic_id=$1
    local version=$2
    local image_type=$3

    echo "Verifying schematic and version availability..."

    # Test if the schematic/version combination exists by checking the URL
    local test_url="https://factory.talos.dev/image/${schematic_id}/${version}/${image_type}.iso"

    if ! curl -s --head --fail "$test_url" >/dev/null 2>&1; then
        echo "Error: Schematic ID '$schematic_id' with version '$version' and image type '$image_type' not found on factory.talos.dev" >&2
        echo "Please verify the schematic ID, version, and image type at https://factory.talos.dev/" >&2
        exit 1
    fi

    echo "✓ Schematic and version verified on factory.talos.dev"
}

# Function to download ISO with progress
download_iso() {
    local schematic_id=$1
    local version=$2
    local storage_path=$3
    local force_mode=$4
    local image_type=$5

    local download_url="https://factory.talos.dev/image/${schematic_id}/${version}/${image_type}.iso"
    # Extract filename from URL (last part after the last slash)
    local filename=$(basename "$download_url")
    local full_path="${storage_path}/${filename}"
    local id_file="${full_path}.id"

    echo "Download URL: $download_url"
    echo "Target file: $full_path"
    echo "Schematic ID file: $id_file"

    # Check if file already exists
    if [[ -f "$full_path" && "$force_mode" != "true" ]]; then
        echo "Error: File already exists: $full_path" >&2
        echo "Use --force to overwrite existing files." >&2
        exit 1
    fi

    if [[ -f "$full_path" && "$force_mode" == "true" ]]; then
        echo "Warning: Overwriting existing file due to --force flag"
        echo "$(date): Overwriting existing file: $full_path" >> "$LOG_FILE"
    fi

    echo "Starting download..."
    echo "$(date): Starting download from $download_url to $full_path" >> "$LOG_FILE"

    # Download with progress bar - separate progress display from error handling
    echo "Downloading ISO..."
    if ! curl -L --fail --progress-bar -o "$full_path" "$download_url"; then
        echo ""
        echo "Error: Download failed. Check network connectivity and URL." >&2
        [[ -f "$full_path" ]] && rm -f "$full_path"  # Clean up partial download
        exit 1
    fi

    echo ""
    echo "✓ Download completed successfully"

    # Verify file size
    local file_size=$(stat -f%z "$full_path" 2>/dev/null || stat -c%s "$full_path" 2>/dev/null || echo "0")
    if [[ "$file_size" -lt 1000000 ]]; then  # Less than 1MB suggests an error
        echo "Error: Downloaded file appears to be too small ($file_size bytes). Download may have failed." >&2
        rm -f "$full_path"
        exit 1
    fi

    echo "File size: $(numfmt --to=iec-i --suffix=B "$file_size")"
    echo "$(date): Download completed. File size: $file_size bytes" >> "$LOG_FILE"

    # Create schematic ID file
    echo "Creating schematic ID file..."
    echo "$schematic_id" > "$id_file"
    if [[ $? -eq 0 ]]; then
        echo "✓ Schematic ID saved to $id_file"
        echo "$(date): Schematic ID saved to $id_file" >> "$LOG_FILE"
    else
        echo "Warning: Could not create schematic ID file $id_file" >&2
        echo "$(date): Warning: Could not create schematic ID file $id_file" >> "$LOG_FILE"
    fi

    echo "$full_path"
}

# Function to register ISO with Proxmox
register_iso() {
    local storage_name=$1
    local iso_path=$2
    local filename=$(basename "$iso_path")

    echo "Registering ISO with Proxmox storage..."
    local retries=5
    local delay=5
    local attempt=1

    while [[ $attempt -le $retries ]]; do
        if pvesm list "$storage_name" --content iso | grep -q "$filename"; then
            echo "✓ ISO successfully registered with Proxmox"
            echo "$(date): ISO registered with Proxmox storage: $storage_name:iso/$filename" >> "$LOG_FILE"
            return
        fi
        echo "Attempt $attempt/$retries: ISO not yet visible in Proxmox. Retrying in $delay seconds..."
        sleep $delay
        attempt=$((attempt + 1))
    done

    echo "Warning: ISO file exists but may not be visible to Proxmox yet" >&2
    echo "You may need to refresh the storage or wait a moment for it to appear" >&2
    echo "$(date): Warning: ISO file exists but not immediately visible in Proxmox storage listing" >> "$LOG_FILE"
    # For local directory storage, files are immediately visible
    # No scanning is needed, just verify the ISO is now visible to Proxmox
    sleep 2  # Give Proxmox a moment to detect the new file

    if pvesm list "$storage_name" --content iso | grep -q "$filename"; then
        echo "✓ ISO successfully registered with Proxmox"
        echo "$(date): ISO registered with Proxmox storage: $storage_name:iso/$filename" >> "$LOG_FILE"
    else
        echo "Warning: ISO file exists but may not be visible to Proxmox yet" >&2
        echo "You may need to refresh the storage or wait a moment for it to appear" >&2
        echo "$(date): Warning: ISO file exists but not immediately visible in Proxmox storage listing" >> "$LOG_FILE"
    fi
}

# Execute preflight checks
preflight_checks

# Create output log file
LOG_FILE="talos_download_output.log"
if ! touch "$LOG_FILE" 2>/dev/null; then
    echo "Error: Cannot write to log file $LOG_FILE. Check permissions or disk space." >&2
    exit 1
fi
echo "$(date): Starting Talos ISO download - Schematic: $SCHEMATIC_ID, Version: $VERSION" > "$LOG_FILE"

# Detect or use specified storage
if [[ -n "$STORAGE" ]]; then
    DETECTED_STORAGE="$STORAGE"
    echo "Using specified storage: $DETECTED_STORAGE"
else
    DETECTED_STORAGE=$(detect_iso_storage)
fi

# Get storage path
STORAGE_PATH=$(get_storage_path "$DETECTED_STORAGE")

# Verify schematic exists
verify_schematic "$SCHEMATIC_ID" "$VERSION" "$IMAGE_TYPE"

# Download the ISO
FINAL_PATH=$(download_iso "$SCHEMATIC_ID" "$VERSION" "$STORAGE_PATH" "$FORCE_MODE" "$IMAGE_TYPE")

# Register with Proxmox
register_iso "$DETECTED_STORAGE" "$FINAL_PATH"

echo "===== Talos ISO Download Complete ====="
echo "Successfully downloaded Talos Linux ISO:"
echo "  Schematic ID: $SCHEMATIC_ID"
echo "  Version: $VERSION"
echo "  Image Type: $IMAGE_TYPE"
echo "  Storage: $DETECTED_STORAGE"
echo "  Final path: $FINAL_PATH"
echo ""
echo "The ISO is now available in Proxmox for VM creation."
echo "$(date): Talos ISO download completed successfully: $FINAL_PATH" >> "$LOG_FILE"
