#!/bin/bash
# viban sync - Core sync engine (provider-agnostic)
# Orchestrates two-way sync between viban board and external issue trackers.
#
# Environment variables (set by bin/viban cmd_sync):
#   VIBAN_JSON       - Path to viban.json
#   VIBAN_DATA_DIR   - Path to viban data directory
#   VIBAN_PROVIDER   - Provider name (e.g., "github")
#   VIBAN_SCRIPT_DIR - Path to viban install directory

set -euo pipefail

SYNC_JSON="${VIBAN_DATA_DIR}/sync.json"
PROVIDER_SCRIPT="${VIBAN_SCRIPT_DIR}/scripts/providers/${VIBAN_PROVIDER}.sh"

# ============================================================
# Provider Loading
# ============================================================

load_provider() {
    if [[ ! -f "$PROVIDER_SCRIPT" ]]; then
        echo "Error: Provider script not found: $PROVIDER_SCRIPT"
        return 1
    fi
    # shellcheck source=/dev/null
    source "$PROVIDER_SCRIPT"

    # Validate provider interface
    local required_funcs=(
        provider_name provider_check_deps provider_check_auth
        provider_detect_config provider_fetch_issues provider_create_issue
        provider_update_issue provider_close_issue provider_ensure_labels
        provider_push_comment
    )
    for func in "${required_funcs[@]}"; do
        if ! declare -f "$func" &>/dev/null; then
            echo "Error: Provider '${VIBAN_PROVIDER}' missing required function: $func"
            return 1
        fi
    done
}

# ============================================================
# Sync Metadata (sync.json)
# ============================================================

read_sync_meta() {
    if [[ -f "$SYNC_JSON" ]]; then
        cat "$SYNC_JSON"
    else
        echo '{}'
    fi
}

write_sync_meta() {
    local data="$1"
    echo "$data" > "${SYNC_JSON}.tmp" && mv "${SYNC_JSON}.tmp" "$SYNC_JSON"
}

get_issue_meta() {
    local viban_id="$1"
    read_sync_meta | jq -r --arg id "$viban_id" '.issues[$id] // empty'
}

set_issue_meta() {
    local viban_id="$1" remote_id="$2" remote_updated="$3" viban_updated="$4"
    local meta
    meta=$(read_sync_meta)
    meta=$(echo "$meta" | jq --arg vid "$viban_id" --arg rid "$remote_id" \
        --arg ru "$remote_updated" --arg vu "$viban_updated" \
        '.issues[$vid] = {remote_id: $rid, remote_updated_at: $ru, viban_updated_at: $vu}')
    write_sync_meta "$meta"
}

# ============================================================
# Body Enrichment (blocked_by, sub-tasks)
# ============================================================

# Build enriched body with blocked_by and sub-task metadata for push
build_enriched_body() {
    local card_id="$1"
    jq -r --argjson cid "$card_id" '
        . as $root |
        ($root.issues[] | select((.id|tonumber)==$cid)) as $card |
        ($card.description // "") as $desc |
        ([$card.blocked_by // [] | .[] | . as $bid |
            ($root.issues[] | select((.id|tonumber)==($bid|tonumber)) | .external_id // null) as $ext |
            if ($ext != null and ($ext | startswith("github:"))) then
                "#" + ($ext | ltrimstr("github:"))
            else
                "viban:#" + ($bid|tostring)
            end
        ] | join(", ")) as $blocked_refs |
        ([$root.issues[] | select((.parent_id // -1) == $cid) |
            (if .external_id != null and (.external_id | startswith("github:")) then
                "#" + (.external_id | ltrimstr("github:"))
            else
                "viban:#" + (.id|tostring)
            end) as $ref |
            if .status == "done" then "- [x] " + $ref + ": " + .title
            else "- [ ] " + $ref + ": " + .title
            end
        ]) as $subtask_lines |
        if ($blocked_refs == "" and ($subtask_lines | length) == 0) then
            $desc
        else
            $desc + "\n\n<!-- viban:meta:start -->\n---\n" +
            (if $blocked_refs != "" then "**Blocked by:** " + $blocked_refs + "\n" else "" end) +
            (if ($subtask_lines | length) > 0 then "**Sub-tasks:**\n" + ($subtask_lines | join("\n")) + "\n" else "" end) +
            "<!-- viban:meta:end -->"
        end
    ' "$VIBAN_JSON"
}

# Strip viban metadata sections from body (used during pull)
strip_viban_meta() {
    local body="$1"
    if [[ "$body" != *"<!-- viban:meta:start -->"* ]]; then
        printf '%s' "$body"
        return
    fi
    printf '%s\n' "$body" | awk '
        /<!-- viban:meta:start -->/ { exit }
        { lines[++n] = $0 }
        END {
            while (n > 0 && lines[n] ~ /^[[:space:]]*$/) n--
            for (i = 1; i <= n; i++) print lines[i]
        }
    '
}

# Push new comments to remote issue (tracks count to avoid duplicates)
push_new_comments() {
    local repo="$1" remote_id="$2" viban_id="$3" card_json="$4"
    local comment_count
    comment_count=$(echo "$card_json" | jq '.comments // [] | length')
    [[ "$comment_count" -eq 0 ]] && return 0
    local meta synced_count
    meta=$(get_issue_meta "$viban_id")
    synced_count=$(echo "$meta" | jq -r '.synced_comment_count // 0')

    if [[ "$comment_count" -gt "$synced_count" ]]; then
        local comments
        comments=$(echo "$card_json" | jq '.comments // []')
        for ci in $(seq "$synced_count" $((comment_count - 1))); do
            local comment_text comment_at
            comment_text=$(echo "$comments" | jq -r ".[$ci].text")
            comment_at=$(echo "$comments" | jq -r ".[$ci].created_at")
            provider_push_comment "$repo" "$remote_id" "**[viban @ ${comment_at}]** ${comment_text}" || true
        done
        local meta_full
        meta_full=$(read_sync_meta)
        meta_full=$(echo "$meta_full" | jq --arg vid "$viban_id" --argjson cc "$comment_count" \
            '.issues[$vid].synced_comment_count = $cc')
        write_sync_meta "$meta_full"
    fi
}

# ============================================================
# Sync Init
# ============================================================

sync_init() {
    local repo_override="$1"

    echo "Initializing sync..."

    # Check provider dependencies and auth
    provider_check_deps || exit 1
    provider_check_auth || exit 1

    # Detect or use provided config
    local config
    if [[ -n "$repo_override" ]]; then
        config="{\"repo\":\"$repo_override\"}"
    else
        config=$(provider_detect_config) || exit 1
    fi

    local repo
    repo=$(echo "$config" | jq -r '.repo')
    echo "Detected $(provider_name) repo: $repo"

    # Ensure required labels exist
    echo "Ensuring labels..."
    provider_ensure_labels "$repo"

    # Initialize sync.json
    local now
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    write_sync_meta "$(jq -n \
        --arg provider "$(provider_name)" \
        --argjson config "$config" \
        --arg now "$now" \
        '{provider: $provider, provider_config: $config, last_sync_at: $now, issues: {}}')"

    echo "Sync initialized for $(provider_name) ($repo)"
}

# ============================================================
# Sync Pull (remote -> viban)
# ============================================================

sync_pull() {
    local repo="$1" dry_run="${2:-false}"
    local pulled=0 updated=0 unchanged=0

    local remote_issues
    remote_issues=$(provider_fetch_issues "$repo") || exit 1

    local provider_prefix
    provider_prefix="$(provider_name):"

    local count
    count=$(echo "$remote_issues" | jq 'length')

    for i in $(seq 0 $((count - 1))); do
        local issue
        issue=$(echo "$remote_issues" | jq ".[$i]")

        local remote_id title description status priority type remote_updated
        remote_id=$(echo "$issue" | jq -r '.remote_id')
        title=$(echo "$issue" | jq -r '.title')
        description=$(strip_viban_meta "$(echo "$issue" | jq -r '.description // ""')")
        status=$(echo "$issue" | jq -r '.status')
        priority=$(echo "$issue" | jq -r '.priority // "P3"')
        type=$(echo "$issue" | jq -r '.type // ""')
        remote_updated=$(echo "$issue" | jq -r '.updated_at')

        local ext_id="${provider_prefix}${remote_id}"

        # Find existing viban card with this external_id
        local viban_card
        viban_card=$(jq -r --arg eid "$ext_id" \
            '.issues[] | select(.external_id == $eid)' "$VIBAN_JSON" 2>/dev/null)

        if [[ -z "$viban_card" || "$viban_card" == "null" ]]; then
            # New remote issue -> import (skip already-closed issues)
            if [[ "$status" == "done" ]]; then
                echo "  == ${ext_id} \"${title}\" (closed, skipped)"
                ((unchanged++))
                continue
            fi
            if [[ "$dry_run" == "true" ]]; then
                echo "  <- ${ext_id} \"${title}\" (new card to create)"
            else
                # Use jq to add card directly
                local now viban_id
                now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
                viban_id=$(jq -r '.next_id // (([.issues[].id] | max // 0) + 1)' "$VIBAN_JSON")

                local type_val="null"
                [[ -n "$type" && "$type" != "null" ]] && type_val="\"$type\""

                jq --arg id "$viban_id" --arg title "$title" --arg desc "$description" \
                    --arg status "$status" --arg priority "$priority" \
                    --arg ext_id "$ext_id" --arg now "$now" --argjson type_val "$type_val" \
                    '.next_id = ((.next_id // 0) + 1) |
                    .issues += [{
                        id: ($id | tonumber),
                        title: $title,
                        description: $desc,
                        status: $status,
                        priority: $priority,
                        type: $type_val,
                        external_id: $ext_id,
                        attachments: [],
                        assigned_to: null,
                        created_at: $now,
                        updated_at: $now
                    }]' "$VIBAN_JSON" > "${VIBAN_JSON}.tmp" && mv "${VIBAN_JSON}.tmp" "$VIBAN_JSON"

                set_issue_meta "$viban_id" "$remote_id" "$remote_updated" "$now"
                echo "  <- ${ext_id} \"${title}\" (new card created)"
            fi
            ((pulled++))
        else
            # Existing card - check for changes
            local viban_id viban_updated
            viban_id=$(echo "$viban_card" | jq -r '.id')
            viban_updated=$(echo "$viban_card" | jq -r '.updated_at')

            # Remote issue closed -> remove card from viban
            if [[ "$status" == "done" ]]; then
                if [[ "$dry_run" == "true" ]]; then
                    echo "  <- ${ext_id} \"${title}\" (closed remotely, will remove card)"
                else
                    jq --argjson id "$viban_id" 'del(.issues[]|select((.id|tonumber)==$id))' \
                        "$VIBAN_JSON" > "${VIBAN_JSON}.tmp" && mv "${VIBAN_JSON}.tmp" "$VIBAN_JSON"
                    # Remove sync metadata for this card
                    local meta_tmp
                    meta_tmp=$(read_sync_meta)
                    meta_tmp=$(echo "$meta_tmp" | jq --arg vid "$viban_id" 'del(.issues[$vid])')
                    write_sync_meta "$meta_tmp"
                    echo "  <- ${ext_id} \"${title}\" (closed remotely, card removed)"
                fi
                ((pulled++))
                continue
            fi

            # Get last known sync timestamps
            local meta
            meta=$(get_issue_meta "$viban_id")

            if [[ -z "$meta" ]]; then
                # First time seeing this linked card in sync - record and skip
                set_issue_meta "$viban_id" "$remote_id" "$remote_updated" "$viban_updated"
                echo "  == ${ext_id} \"${title}\" (tracking started)"
                ((unchanged++))
                continue
            fi

            local last_remote_updated last_viban_updated
            last_remote_updated=$(echo "$meta" | jq -r '.remote_updated_at')
            last_viban_updated=$(echo "$meta" | jq -r '.viban_updated_at')

            local remote_changed=false viban_changed=false
            [[ "$remote_updated" != "$last_remote_updated" ]] && remote_changed=true
            [[ "$viban_updated" != "$last_viban_updated" ]] && viban_changed=true

            if [[ "$remote_changed" == "false" && "$viban_changed" == "false" ]]; then
                echo "  == ${ext_id} \"${title}\" (no changes)"
                ((unchanged++))
            elif [[ "$remote_changed" == "true" && "$viban_changed" == "false" ]]; then
                # Only remote changed -> pull
                if [[ "$dry_run" == "true" ]]; then
                    echo "  <- ${ext_id} \"${title}\" (remote updated, will pull)"
                else
                    local now
                    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

                    local type_val="null"
                    [[ -n "$type" && "$type" != "null" ]] && type_val="\"$type\""

                    jq --argjson vid "$viban_id" --arg title "$title" --arg desc "$description" \
                        --arg status "$status" --arg priority "$priority" \
                        --arg now "$now" --argjson type_val "$type_val" \
                        '(.issues[] | select((.id | tonumber) == $vid)) |=
                        . + {title: $title, description: $desc, status: $status,
                             priority: $priority, type: $type_val, updated_at: $now}' \
                        "$VIBAN_JSON" > "${VIBAN_JSON}.tmp" && mv "${VIBAN_JSON}.tmp" "$VIBAN_JSON"

                    set_issue_meta "$viban_id" "$remote_id" "$remote_updated" "$now"
                    echo "  <- ${ext_id} \"${title}\" (pulled remote changes)"
                fi
                ((updated++))
            elif [[ "$remote_changed" == "false" && "$viban_changed" == "true" ]]; then
                # Only viban changed -> will be handled in push phase
                echo "  == ${ext_id} \"${title}\" (local changes, will push)"
                ((unchanged++))
            else
                # Both changed -> conflict resolution (remote wins by default)
                if [[ "$dry_run" == "true" ]]; then
                    echo "  !! ${ext_id} \"${title}\" (conflict: remote wins)"
                else
                    local now
                    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

                    local type_val="null"
                    [[ -n "$type" && "$type" != "null" ]] && type_val="\"$type\""

                    jq --argjson vid "$viban_id" --arg title "$title" --arg desc "$description" \
                        --arg status "$status" --arg priority "$priority" \
                        --arg now "$now" --argjson type_val "$type_val" \
                        '(.issues[] | select((.id | tonumber) == $vid)) |=
                        . + {title: $title, description: $desc, status: $status,
                             priority: $priority, type: $type_val, updated_at: $now}' \
                        "$VIBAN_JSON" > "${VIBAN_JSON}.tmp" && mv "${VIBAN_JSON}.tmp" "$VIBAN_JSON"

                    set_issue_meta "$viban_id" "$remote_id" "$remote_updated" "$now"
                    echo "  !! ${ext_id} \"${title}\" (conflict: remote wins)"
                fi
                ((pulled++))
            fi
        fi
    done

    echo "Pull: $pulled new/conflict, $updated updated, $unchanged unchanged"
}

# ============================================================
# Sync Push (viban -> remote)
# ============================================================

sync_push() {
    local repo="$1" dry_run="${2:-false}" push_new="${3:-false}"
    local pushed=0 closed=0 unchanged=0

    local provider_prefix
    provider_prefix="$(provider_name):"

    # Get all viban cards with this provider's external_id
    local linked_cards
    linked_cards=$(jq -r --arg prefix "$provider_prefix" \
        '[.issues[] | select(.external_id != null and (.external_id | startswith($prefix)))]' \
        "$VIBAN_JSON")

    local count
    count=$(echo "$linked_cards" | jq 'length')

    for i in $(seq 0 $((count - 1))); do
        local card
        card=$(echo "$linked_cards" | jq ".[$i]")

        local viban_id ext_id remote_id title status viban_updated
        viban_id=$(echo "$card" | jq -r '.id')
        ext_id=$(echo "$card" | jq -r '.external_id')
        remote_id="${ext_id#"${provider_prefix}"}"
        title=$(echo "$card" | jq -r '.title')
        status=$(echo "$card" | jq -r '.status')
        viban_updated=$(echo "$card" | jq -r '.updated_at')

        # Get last known sync timestamps
        local meta
        meta=$(get_issue_meta "$viban_id")
        if [[ -z "$meta" ]]; then
            ((unchanged++))
            continue
        fi

        local last_viban_updated
        last_viban_updated=$(echo "$meta" | jq -r '.viban_updated_at')

        if [[ "$viban_updated" == "$last_viban_updated" ]]; then
            ((unchanged++))
            continue
        fi

        # Viban card changed since last sync -> push
        if [[ "$dry_run" == "true" ]]; then
            echo "  -> ${ext_id} \"${title}\" (will push local changes)"
            ((pushed++))
        else
            local enriched_body
            enriched_body=$(build_enriched_body "$viban_id")
            echo "$card" | jq --arg body "$enriched_body" '{
                title: .title,
                description: $body,
                status: .status,
                priority: (.priority // "P3"),
                type: (.type // "")
            }' | provider_update_issue "$repo" "$remote_id"

            # Push new comments
            push_new_comments "$repo" "$remote_id" "$viban_id" "$card"

            local now remote_updated
            now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
            # Fetch updated remote timestamp
            remote_updated="$now"

            set_issue_meta "$viban_id" "$remote_id" "$remote_updated" "$viban_updated"
            echo "  -> ${ext_id} \"${title}\" (pushed)"
            ((pushed++))
        fi
    done

    # Handle push-new: viban cards without external_id
    if [[ "$push_new" == "true" ]]; then
        local unlinked_cards
        unlinked_cards=$(jq -r \
            '[.issues[] | select(.external_id == null or .external_id == "")]' \
            "$VIBAN_JSON")

        local unlinked_count
        unlinked_count=$(echo "$unlinked_cards" | jq 'length')

        for i in $(seq 0 $((unlinked_count - 1))); do
            local card
            card=$(echo "$unlinked_cards" | jq ".[$i]")

            local viban_id title
            viban_id=$(echo "$card" | jq -r '.id')
            title=$(echo "$card" | jq -r '.title')

            if [[ "$dry_run" == "true" ]]; then
                echo "  -> (new) #${viban_id} \"${title}\" (will create remote issue)"
                ((pushed++))
            else
                local new_remote_id
                local enriched_body
                enriched_body=$(build_enriched_body "$viban_id")
                new_remote_id=$(echo "$card" | jq --arg body "$enriched_body" '{
                    title: .title,
                    description: $body,
                    status: .status,
                    priority: (.priority // "P3"),
                    type: (.type // "")
                }' | provider_create_issue "$repo") || {
                    echo "  !! Failed to create remote issue for #${viban_id}"
                    continue
                }

                local ext_id="${provider_prefix}${new_remote_id}"
                local now
                now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

                # Update viban card with external_id
                jq --argjson vid "$viban_id" --arg eid "$ext_id" --arg now "$now" \
                    '(.issues[] | select((.id | tonumber) == $vid)) |= . + {external_id: $eid, updated_at: $now}' \
                    "$VIBAN_JSON" > "${VIBAN_JSON}.tmp" && mv "${VIBAN_JSON}.tmp" "$VIBAN_JSON"

                set_issue_meta "$viban_id" "$new_remote_id" "$now" "$now"
                # Push comments for newly created issue
                push_new_comments "$repo" "$new_remote_id" "$viban_id" "$card"
                echo "  -> ${ext_id} #${viban_id} \"${title}\" (created remote issue)"
                ((pushed++))
            fi
        done
    fi

    echo "Push: $pushed pushed, $closed closed, $unchanged unchanged"
}

# ============================================================
# Sync Status
# ============================================================

sync_status() {
    if [[ ! -f "$SYNC_JSON" ]]; then
        echo "Sync not configured. Run: viban sync --init"
        return 1
    fi

    local meta
    meta=$(read_sync_meta)

    local provider repo last_sync tracked_count
    provider=$(echo "$meta" | jq -r '.provider')
    repo=$(echo "$meta" | jq -r '.provider_config.repo // "unknown"')
    last_sync=$(echo "$meta" | jq -r '.last_sync_at // "never"')
    tracked_count=$(echo "$meta" | jq '.issues | length')

    local provider_prefix="${provider}:"
    local total_cards linked_cards unlinked_cards
    total_cards=$(jq '.issues | length' "$VIBAN_JSON")
    linked_cards=$(jq --arg prefix "$provider_prefix" \
        '[.issues[] | select(.external_id != null and (.external_id | startswith($prefix)))] | length' \
        "$VIBAN_JSON")
    unlinked_cards=$((total_cards - linked_cards))

    echo "Sync status:"
    echo "  Provider: $provider ($repo)"
    echo "  Last sync: $last_sync"
    echo "  Tracked: $tracked_count issues"
    echo "  Linked cards: $linked_cards"
    echo "  Unlinked cards: $unlinked_cards"
}

# ============================================================
# Full Sync
# ============================================================

sync_full() {
    local repo="$1" dry_run="${2:-false}" push_new="${3:-false}"

    echo "Syncing with $(provider_name) ($repo)..."
    sync_pull "$repo" "$dry_run"
    sync_push "$repo" "$dry_run" "$push_new"

    if [[ "$dry_run" == "false" ]]; then
        # Update last_sync_at
        local now
        now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        local meta
        meta=$(read_sync_meta)
        meta=$(echo "$meta" | jq --arg now "$now" '.last_sync_at = $now')
        write_sync_meta "$meta"
    fi
}

# ============================================================
# Main CLI Parser
# ============================================================

main() {
    local action="full"
    local dry_run=false
    local push_new=false
    local pull_only=false
    local push_only=false
    local auto_mode=false
    local repo_override=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --init)      action="init"; shift ;;
            --status)    action="status"; shift ;;
            --dry-run)   dry_run=true; shift ;;
            --push-new)  push_new=true; shift ;;
            --pull-only) pull_only=true; shift ;;
            --push-only) push_only=true; shift ;;
            --auto)      auto_mode=true; shift ;;
            --repo)      repo_override="$2"; shift 2 ;;
            --provider)  shift 2 ;;  # Already handled by bin/viban
            *)           echo "Unknown option: $1"; exit 1 ;;
        esac
    done

    # Load provider
    load_provider || exit 1

    # Handle init
    if [[ "$action" == "init" ]]; then
        sync_init "$repo_override"
        return
    fi

    # Handle status
    if [[ "$action" == "status" ]]; then
        sync_status
        return
    fi

    # For sync operations, check that sync is configured
    if [[ ! -f "$SYNC_JSON" ]]; then
        echo "Sync not configured. Run: viban sync --init"
        exit 1
    fi

    # Check provider deps and auth
    provider_check_deps || exit 1
    provider_check_auth || exit 1

    # Get repo from sync config or override
    local repo
    if [[ -n "$repo_override" ]]; then
        repo="$repo_override"
    else
        repo=$(jq -r '.provider_config.repo' "$SYNC_JSON")
    fi

    if [[ -z "$repo" || "$repo" == "null" ]]; then
        echo "Error: No repo configured. Run: viban sync --init"
        exit 1
    fi

    # Auto mode: silent pull-only for TUI background use
    if [[ "$auto_mode" == "true" ]]; then
        sync_pull "$repo" false >/dev/null 2>&1
        local now
        now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        local meta
        meta=$(read_sync_meta)
        meta=$(echo "$meta" | jq --arg now "$now" '.last_sync_at = $now')
        write_sync_meta "$meta"
        exit 0
    fi

    # Execute sync
    if [[ "$pull_only" == "true" ]]; then
        echo "Pulling from $(provider_name) ($repo)..."
        sync_pull "$repo" "$dry_run"
    elif [[ "$push_only" == "true" ]]; then
        echo "Pushing to $(provider_name) ($repo)..."
        sync_push "$repo" "$dry_run" "$push_new"
    else
        sync_full "$repo" "$dry_run" "$push_new"
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
