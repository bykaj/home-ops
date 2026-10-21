#!/usr/bin/env bash
# Report pinned container images whose tag or digest has disappeared from the
# registry. Upstreams rarely delete a published tag; when they do it is often
# because the release was compromised (BerriAI/litellm#47826).
#
# Usage: check-yanked-images.sh <file with one image reference per line>
# Prints one tab-separated line per finding: missing|error <TAB> ref <TAB> detail
# Exit code: 0 = nothing missing, 1 = at least one image missing, 2 = usage
set -uo pipefail

if [[ $# -ne 1 || ! -r "$1" ]]; then
    echo "usage: $0 <image-list-file>" >&2
    exit 2
fi

missing=0

# Check one reference: "missing" only for explicit registry not-found answers,
# "error" for anything else (auth, rate limit, network), so a flaky registry
# never opens an issue
check() {
    local ref="$1" out
    for attempt in 1 2; do
        if out=$(crane digest "$ref" 2>&1); then
            return 0
        fi
        if grep -qE 'MANIFEST_UNKNOWN|NAME_UNKNOWN' <<<"$out"; then
            printf 'missing\t%s\t%s\n' "$ref" "$(tail -n 1 <<<"$out")"
            missing=1
            return 0
        fi
        [[ $attempt -eq 1 ]] && sleep 5
    done
    printf 'error\t%s\t%s\n' "$ref" "$(tail -n 1 <<<"$out")"
}

while IFS= read -r image || [[ -n "$image" ]]; do
    [[ -z "$image" || "$image" == \#* ]] && continue
    name="${image%@*}"
    if [[ "$image" == *@sha256:* ]]; then
        check "${name%:*}@${image#*@}"
    fi
    # A tag is present when the last path segment contains a colon
    if [[ "${name##*/}" == *:* ]]; then
        check "$name"
    fi
done < <(sort -u "$1")

exit "$missing"
