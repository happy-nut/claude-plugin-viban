#!/bin/bash
# viban sync_create - Create a remote issue from a viban card
# Called by cmd_add when sync is configured.
#
# Usage: sync_create.sh <card_id>
# Output: external_id string (e.g., "github:42") on success, empty on failure
#
# Environment variables (set by caller):
#   VIBAN_JSON       - Path to viban.json
#   VIBAN_DATA_DIR   - Path to viban data directory
#   VIBAN_PROVIDER   - Provider name (e.g., "github")
#   VIBAN_SCRIPT_DIR - Path to viban install directory

set -euo pipefail

card_id="$1"
SYNC_JSON="${VIBAN_DATA_DIR}/sync.json"
PROVIDER_SCRIPT="${VIBAN_SCRIPT_DIR}/scripts/providers/${VIBAN_PROVIDER}.sh"

# Load provider
if [[ ! -f "$PROVIDER_SCRIPT" ]]; then
    exit 1
fi
source "$PROVIDER_SCRIPT"

# Read card from viban.json
card=$(jq --argjson id "$card_id" '.issues[] | select((.id|tonumber)==$id)' "$VIBAN_JSON" 2>/dev/null) || exit 1
if [[ -z "$card" || "$card" == "null" ]]; then exit 1; fi

# Get repo from sync config
repo=$(jq -r '.provider_config.repo' "$SYNC_JSON" 2>/dev/null) || exit 1
if [[ -z "$repo" || "$repo" == "null" ]]; then exit 1; fi

# Check provider auth (silent)
provider_check_deps &>/dev/null || exit 1
provider_check_auth &>/dev/null || exit 1

# Create remote issue (split pipeline to avoid SIGPIPE with pipefail)
issue_json=$(echo "$card" | jq '{
    title: .title,
    description: (.description // ""),
    status: .status,
    priority: (.priority // "P3"),
    type: (.type // "")
}') || exit 1
new_remote_id=$(echo "$issue_json" | provider_create_issue "$repo" 2>/dev/null) || exit 1

if [[ -z "$new_remote_id" ]]; then exit 1; fi

# Build external_id
provider_prefix="$(provider_name):"
ext_id="${provider_prefix}${new_remote_id}"

# Update card with external_id
now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
jq --argjson vid "$card_id" --arg eid "$ext_id" --arg now "$now" \
    '(.issues[] | select((.id|tonumber)==$vid)) |= . + {external_id: $eid, updated_at: $now}' \
    "$VIBAN_JSON" > "${VIBAN_JSON}.tmp" && mv "${VIBAN_JSON}.tmp" "$VIBAN_JSON"

# Record sync metadata
sync_meta=$(cat "$SYNC_JSON")
sync_meta=$(echo "$sync_meta" | jq --arg vid "$card_id" --arg rid "$new_remote_id" \
    --arg now "$now" \
    '.issues[$vid] = {remote_id: $rid, remote_updated_at: $now, viban_updated_at: $now}')
echo "$sync_meta" > "${SYNC_JSON}.tmp" && mv "${SYNC_JSON}.tmp" "$SYNC_JSON"

# Output external_id for caller
echo "$ext_id"
