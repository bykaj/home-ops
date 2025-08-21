#!/usr/bin/env bash
# LibVersion: 1.0.0
#
# Generic utility functions for Bash scripts.
# Relies on VERBOSE_FLAG being set in the calling script.
# Relies on logging functions (log_info, log_error etc.) being defined in the calling script.

# Helper execution functions
run_quiet() {
    if [[ "${VERBOSE_FLAG:-false}" == "true" ]]; then
        "$@"
    else
        "$@" >/dev/null 2>&1
    fi
}

run_with_output() {
    if [[ "${VERBOSE_FLAG:-false}" == "true" ]]; then
        "$@"
    else
        "$@" 2>/dev/null # Suppresses stderr in non-verbose. Exit status is still checked.
    fi
}

run_with_warnings() {
    local temp_output
    temp_output=$(mktemp)
    local exit_code

    if [[ "${VERBOSE_FLAG:-false}" == "true" ]]; then
        "$@" 2>&1 | tee "$temp_output"
        exit_code=${PIPESTATUS[0]}
    else
        if "$@" >"$temp_output" 2>&1; then
            exit_code=0
        else
            exit_code=$?
        fi

        if grep -i "WARNING" "$temp_output" >/dev/null 2>&1; then
            echo ""
            log_warning "Storage warnings detected:" # Assumes log_warning is defined in main script
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
    if [[ "${VERBOSE_FLAG:-false}" == "true" ]]; then
        "$@"
    else
        local temp_output
        temp_output=$(mktemp)
        if "$@" >"$temp_output" 2>&1; then
            rm -f "$temp_output"
            return 0
        else
            local exit_code=$?
            log_error "Command failed. Error details:" # Assumes log_error is defined
            cat "$temp_output" >&2
            rm -f "$temp_output"
            return $exit_code
        fi
    fi
}

# Version comparison function
# Usage: compare_versions "1.0.0" "1.0.1" -> returns 0 (v1 < v2)
#        compare_versions "1.0.1" "1.0.0" -> returns 2 (v1 > v2)
#        compare_versions "1.0.0" "1.0.0" -> returns 1 (v1 == v2)
compare_versions() {
    local v1=$1
    local v2=$2
    if [[ "$v1" == "$v2" ]]; then return 1; fi
    if [[ "$(printf '%s\n' "$v1" "$v2" | sort -V | head -n1)" == "$v1" ]]; then
        return 0 # v1 < v2
    else
        return 2 # v1 > v2
    fi
}
