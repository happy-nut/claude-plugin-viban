# lib/commands.zsh - CLI command implementations
cmd_list() {
    init_json
    local _done_ids=$(jq '[.issues[]|select(.status=="done")|.id]' "$VIBAN_JSON")
    local filter_status=""
    [[ "$1" == "--status" && -n "$2" ]] && filter_status="$2"

    echo ""
    if [[ -n "$filter_status" ]]; then
        local count=$(jq -r --arg s "$filter_status" '[.issues[]|select(.status==$s)]|length' "$VIBAN_JSON")
        echo "● $filter_status ($count)"
        jq -r --arg s "$filter_status" --argjson done "$_done_ids" '.issues|map(select(.status==$s))|sort_by(.updated_at)|reverse|.[]|"  \(if .external_id then .external_id else "#\(.id)" end) [\(.priority // "P3")]\(if .type then " [\(.type | ascii_upcase)]" else "" end)\(if ((.blocked_by // []) | length > 0 and any(. as $b | $done | index($b) == null)) then " [BLOCKED]" else "" end) \(.title)"' "$VIBAN_JSON"
        echo ""
    else
        for st in $VIBAN_STATUSES; do
            gum style --foreground "${STATUS_COLOR[$st]}" --bold "● ${STATUS_LABEL[$st]} ($(count_issues_by_status "$st"))"
            get_issues_by_status "$st" | jq -r '.[]|"  \(if .external_id then .external_id else "#\(.id)" end) [\(.priority // "P3")]\(if .type then " [\(.type | ascii_upcase)]" else "" end) \(.title)"'
            echo ""
        done
    fi
}

cmd_history() {
    init_json
    local count=$(jq '[.issues[]|select(.status=="done")]|length' "$VIBAN_JSON")
    echo ""
    echo "● Done ($count)"
    jq -r '.issues|map(select(.status=="done"))|sort_by(.updated_at)|reverse|.[]|"  \(if .external_id then .external_id else "#\(.id)" end) [\(.priority // "P3")]\(if .type then " [\(.type | ascii_upcase)]" else "" end) \(.title)  (\(.updated_at | split("T")[0]))"' "$VIBAN_JSON"
    echo ""
}

cmd_priority() {
    init_json
    [[ -z "$1" ]] && { echo "Usage: viban priority <id> <P0|P1|P2|P3>"; exit 1; }
    local id="$1"
    local new_priority="${2:-}"

    # Validate priority
    if [[ ! "$new_priority" =~ ^P[0-3]$ ]]; then
        echo "Error: Priority must be P0, P1, P2, or P3"
        exit 1
    fi

    # Check if issue exists
    local exists=$(jq --argjson id "$id" '[.issues[]|select((.id|tonumber)==$id)]|length' "$VIBAN_JSON")
    [[ "$exists" == "0" ]] && { echo "Error: Issue #$id not found"; exit 1; }

    local now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    jq --argjson id "$id" --arg priority "$new_priority" --arg now "$now" \
        '(.issues[]|select((.id|tonumber)==$id)) |= . + {priority:$priority,updated_at:$now}' \
        "$VIBAN_JSON" > "$VIBAN_JSON.tmp" && mv "$VIBAN_JSON.tmp" "$VIBAN_JSON"

    echo "✓ $(display_id "$id" "$(get_ext_id "$id")") priority → $new_priority"
}

cmd_add() {
    init_json
    [[ -z "$1" ]] && { echo "Usage: viban add \"title\" [\"description\"] [priority] [type] [attachments...]"; exit 1; }

    # Support both positional and named args (--title, --description, --priority, --type, --ext-id)
    local title="" desc="" priority="P3" issue_type="" ext_id="" parent_id=""
    local -a attachments=()
    local positional=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --title)     title="$2"; shift 2 ;;
            --desc|--description) desc="$2"; shift 2 ;;
            --desc-file) [[ -f "$2" ]] && desc="$(cat "$2")"; shift 2 ;;
            --priority)  priority="$2"; shift 2 ;;
            --type)      issue_type="$2"; shift 2 ;;
            --ext-id|--external-id) ext_id="$2"; shift 2 ;;
            --parent)    parent_id="$2"; shift 2 ;;
            --attach|--attachments) shift; while [[ $# -gt 0 && "$1" != --* ]]; do attachments+=("$1"); shift; done ;;
            --*)         shift 2 2>/dev/null || shift ;; # skip unknown flags
            *)           positional+=("$1"); shift ;;
        esac
    done

    # Fall back to positional args if named args not used
    [[ -z "$title" ]] && title="${positional[1]:-}"
    [[ -z "$desc" ]] && desc="${positional[2]:-}"
    [[ "$priority" == "P3" && -n "${positional[3]:-}" ]] && priority="${positional[3]}"
    [[ -z "$issue_type" && -n "${positional[4]:-}" ]] && issue_type="${positional[4]}"
    if [[ ${#attachments[@]} -eq 0 && ${#positional[@]} -gt 4 ]]; then
        attachments=("${positional[@]:5}")
    fi

    [[ -z "$title" ]] && { echo "Usage: viban add \"title\" [\"description\"] [priority] [type]"; exit 1; }

    # Duplicate detection: warn on similar titles (word-level Jaccard >= 0.5)
    local duplicates=$(jq -r --arg title "$title" '
        def words: ascii_downcase | gsub("[^a-z0-9가-힣\\s]"; " ") | split(" ") | map(select(length > 1)) | unique;
        ($title | words) as $new_words |
        if ($new_words | length) == 0 then empty else
            .issues[] | select(.status != "done") |
            (.title | words) as $existing_words |
            ([$new_words[] | select(. as $w | $existing_words | index($w) != null)] | length) as $overlap |
            ([$new_words[], $existing_words[]] | unique | length) as $union |
            select($union > 0 and ($overlap / $union) >= 0.5) |
            "\(.id)\t\(.title)"
        end
    ' "$VIBAN_JSON")
    if [[ -n "$duplicates" ]]; then
        echo "⚠ Potential duplicate(s):"
        while IFS=$'\t' read -r dup_id dup_title; do
            echo "  #$dup_id $dup_title"
        done <<< "$duplicates"
    fi

    # Validate parent exists if specified
    if [[ -n "$parent_id" ]]; then
        local parent_exists=$(jq -r --argjson id "$parent_id" '.issues[]|select((.id|tonumber)==$id)|.id//empty' "$VIBAN_JSON")
        [[ -z "$parent_exists" ]] && { echo "Error: Parent issue #$parent_id not found"; exit 1; }
    fi

    local id=$(get_next_id) now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    # Validate priority
    [[ ! "$priority" =~ ^P[0-3]$ ]] && priority="P3"
    # Validate type (bug, feat, chore, refactor)
    [[ -n "$issue_type" && ! "$issue_type" =~ ^(bug|feat|chore|refactor)$ ]] && issue_type=""
    # Build attachments JSON array
    local attachments_json="[]"
    if [[ ${#attachments[@]} -gt 0 ]]; then
        attachments_json=$(printf '%s\n' "${attachments[@]}" | jq -R . | jq -s .)
    fi
    # New cards don't have order - they follow priority-based sorting
    # Order is only assigned when manually moved
    local tmpjson=$(mktemp)
    printf '%s' "$desc" > "$tmpjson"
    jq --arg id "$id" --arg title "$title" --rawfile desc "$tmpjson" --arg priority "$priority" --arg issue_type "$issue_type" --arg ext_id "$ext_id" --arg parent "$parent_id" --argjson attachments "$attachments_json" --arg now "$now" '
        .next_id = ((.next_id // 0) + 1) |
        .issues += [{
            id:($id|tonumber),
            title:$title,
            description:$desc,
            status:"backlog",
            priority:$priority,
            type:(if $issue_type == "" then null else $issue_type end),
            external_id:(if $ext_id == "" then null else $ext_id end),
            parent_id:(if $parent == "" then null else ($parent|tonumber) end),
            attachments:$attachments,
            assigned_to:null,
            created_at:$now,
            updated_at:$now
        }]' "$VIBAN_JSON" > "$VIBAN_JSON.tmp" && mv "$VIBAN_JSON.tmp" "$VIBAN_JSON"
    rm -f "$tmpjson"

    # Auto-create remote issue if sync is configured and no ext_id provided
    if [[ -z "$ext_id" && -f "$VIBAN_DATA_DIR/sync.json" ]]; then
        local provider
        provider=$(jq -r '.provider // ""' "$VIBAN_DATA_DIR/sync.json" 2>/dev/null)
        if [[ -n "$provider" && "$provider" != "null" ]]; then
            local created_ext_id
            created_ext_id=$(VIBAN_JSON="$VIBAN_JSON" VIBAN_DATA_DIR="$VIBAN_DATA_DIR" \
                VIBAN_PROVIDER="$provider" VIBAN_SCRIPT_DIR="$VIBAN_SCRIPT_DIR" \
                bash "$VIBAN_SCRIPT_DIR/scripts/sync_create.sh" "$id" 2>/dev/null) || true
            [[ -n "$created_ext_id" ]] && ext_id="$created_ext_id"
        fi
    fi

    local type_info=""
    [[ -n "$issue_type" ]] && type_info=" [$issue_type]"
    local attach_info=""
    [[ ${#attachments[@]} -gt 0 ]] && attach_info=" +${#attachments[@]} files"
    local parent_info=""
    [[ -n "$parent_id" ]] && parent_info=" (child of #$parent_id)"
    echo "✓ $(display_id "$id" "$ext_id") added ($priority)$type_info$attach_info$parent_info"
}

cmd_assign() {
    init_json
    local session="${1:-$(echo $RANDOM | md5 | head -c 8)}"
    local done_ids=$(jq '[.issues[]|select(.status=="done")|.id]' "$VIBAN_JSON")
    local issue=$(jq -r --argjson done "$done_ids" '
        .issues|map(select(.status=="backlog"))|map(select(
            (.blocked_by // []) | length == 0 or all(. as $b | $done | index($b) != null)
        ))|sort_by(if .order != null then [0, .order] else [1, ({"P0":0,"P1":1,"P2":2,"P3":3}[.priority // "P3"] // 3), .id] end)|first' "$VIBAN_JSON")
    [[ "$issue" == "null" || -z "$issue" ]] && { echo "No backlog"; exit 1; }
    local id=$(printf '%s' "$issue" | jq -r '.id') now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local ext_id=$(printf '%s' "$issue" | jq -r '.external_id // ""')

    # Update status to in_progress (no worktree - use branch workflow)
    jq --argjson id "$id" --arg s "$session" --arg now "$now" \
        '(.issues[]|select((.id|tonumber)==$id)) |= . + {status:"in_progress",assigned_to:$s,updated_at:$now}' \
        "$VIBAN_JSON" > "$VIBAN_JSON.tmp" && mv "$VIBAN_JSON.tmp" "$VIBAN_JSON"

    # Set iTerm2 session name to issue display ID
    local did; did=$(display_id "$id" "$ext_id")
    printf '\033]1;%s\007' "$did"

    echo "✓ $did assigned"
    echo "$id"
}

cmd_review() {
    init_json
    local id="${1:-$(jq -r '.issues|map(select(.status=="in_progress"))|first|.id//empty' "$VIBAN_JSON")}"
    [[ -z "$id" ]] && { echo "None"; exit 1; }
    local now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    jq --argjson id "$id" --arg now "$now" \
        '(.issues[]|select((.id|tonumber)==$id)) |= . + {status:"review",assigned_to:null,updated_at:$now}' \
        "$VIBAN_JSON" > "$VIBAN_JSON.tmp" && mv "$VIBAN_JSON.tmp" "$VIBAN_JSON"

    # Clear iTerm2 session name
    printf '\033]1;\007'

    echo "✓ $(display_id "$id" "$(get_ext_id "$id")") → review"
}

cmd_done() {
    init_json
    [[ -z "$1" ]] && { echo "Usage: viban done <id> [--purge]"; exit 1; }
    local id="$1"
    local remove=false
    [[ "$2" == "--remove" || "$2" == "--purge" ]] && remove=true

    # Cleanup worktree if exists
    local repo_root=$(git rev-parse --show-toplevel 2>/dev/null)
    local wt_dir="$VIBAN_DATA_DIR/worktrees/$id"

    local branch="issue-$id"
    local _ext_id=$(get_ext_id "$id")
    if [[ -n "$_ext_id" && "$_ext_id" != "null" ]]; then
        local _issue_num="${_ext_id##*:}"
        if git -C "$repo_root" rev-parse --verify "issue-${_issue_num}" &>/dev/null 2>&1; then
            branch="issue-${_issue_num}"
        fi
    fi

    if [[ -d "$wt_dir" ]]; then
        git -C "$repo_root" worktree remove "$wt_dir" --force 2>/dev/null
        git -C "$repo_root" branch -D "$branch" 2>/dev/null
        echo "✓ worktree removed"
    fi

    if $remove; then
        # Delete card (old behavior)
        jq --argjson id "$id" 'del(.issues[]|select((.id|tonumber)==$id))' \
            "$VIBAN_JSON" > "$VIBAN_JSON.tmp" && mv "$VIBAN_JSON.tmp" "$VIBAN_JSON"
        printf '\033]1;\007'
        echo "✓ $(display_id "$id" "$(get_ext_id "$id")") completed & removed"
    else
        # Move to done status (non-destructive default)
        local now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        jq --argjson id "$id" --arg now "$now" \
            '(.issues[]|select((.id|tonumber)==$id)) |= . + {status:"done",assigned_to:null,updated_at:$now}' \
            "$VIBAN_JSON" > "$VIBAN_JSON.tmp" && mv "$VIBAN_JSON.tmp" "$VIBAN_JSON"
        printf '\033]1;\007'
        echo "✓ $(display_id "$id" "$(get_ext_id "$id")") → done"
    fi
}

cmd_move() {
    init_json
    [[ -z "$1" || -z "$2" ]] && { echo "Usage: viban move <id> <status>"; exit 1; }
    local id="$1"
    local new_status="$2"

    # Validate status
    local valid_statuses="backlog in_progress review done"
    if [[ ! " $valid_statuses " == *" $new_status "* ]]; then
        echo "Error: Invalid status '$new_status'. Valid: backlog, in_progress, review, done"
        exit 1
    fi

    # Verify issue exists
    local cur_status=$(jq -r --argjson id "$id" '.issues[]|select((.id|tonumber)==$id)|.status//empty' "$VIBAN_JSON")
    [[ -z "$cur_status" ]] && { echo "Error: Issue #$id not found"; exit 1; }

    if [[ "$cur_status" == "$new_status" ]]; then
        echo "Issue #$id is already in $new_status"
        return 0
    fi

    local now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    jq --argjson id "$id" --arg s "$new_status" --arg now "$now" \
        '(.issues[]|select((.id|tonumber)==$id)) |= . + {status:$s,updated_at:$now}' \
        "$VIBAN_JSON" > "$VIBAN_JSON.tmp" && mv "$VIBAN_JSON.tmp" "$VIBAN_JSON"

    echo "✓ $(display_id "$id" "$(get_ext_id "$id")") → $new_status"
}

cmd_comment() {
    init_json
    [[ -z "$1" || -z "$2" ]] && { echo "Usage: viban comment <id> \"message\""; exit 1; }
    local id="$1"
    shift
    local message="$*"

    # Verify issue exists
    local exists=$(jq -r --argjson id "$id" '.issues[]|select((.id|tonumber)==$id)|.id//empty' "$VIBAN_JSON")
    [[ -z "$exists" ]] && { echo "Error: Issue #$id not found"; exit 1; }

    local now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    jq --argjson id "$id" --arg msg "$message" --arg now "$now" \
        '(.issues[]|select((.id|tonumber)==$id)) |= . + {comments:((.comments // []) + [{text:$msg,created_at:$now}]),updated_at:$now}' \
        "$VIBAN_JSON" > "$VIBAN_JSON.tmp" && mv "$VIBAN_JSON.tmp" "$VIBAN_JSON"

    local count=$(jq -r --argjson id "$id" '.issues[]|select((.id|tonumber)==$id)|.comments|length' "$VIBAN_JSON")
    echo "✓ comment #$count added to $(display_id "$id" "$(get_ext_id "$id")")"
}

cmd_get() {
    init_json
    local id="$1"
    # Output issue JSON
    jq --argjson id "$id" '.issues[]|select((.id|tonumber)==$id)' "$VIBAN_JSON"
    # Show sub-tasks if any
    local subtasks=$(jq -r --argjson id "$id" '[.issues[]|select(.parent_id==$id)]|length' "$VIBAN_JSON")
    if [[ "$subtasks" -gt 0 ]]; then
        local done_count=$(jq -r --argjson id "$id" '[.issues[]|select(.parent_id==$id and .status=="done")]|length' "$VIBAN_JSON")
        echo ""
        echo "Sub-tasks: $done_count/$subtasks done ($((done_count * 100 / subtasks))%)"
        jq -r --argjson id "$id" '.issues[]|select(.parent_id==$id)|"  #\(.id) [\(.status)] \(.title)"' "$VIBAN_JSON"
    fi
}

cmd_attach() {
    init_json
    [[ -z "$1" || -z "$2" ]] && { echo "Usage: viban attach <id> <file1> [file2...]"; exit 1; }
    local id="$1"
    shift
    local files=("$@")

    # Check if issue exists
    local exists=$(jq --argjson id "$id" '[.issues[]|select((.id|tonumber)==$id)]|length' "$VIBAN_JSON")
    [[ "$exists" == "0" ]] && { echo "Error: Issue #$id not found"; exit 1; }

    # Build new attachments array
    local new_attachments=$(printf '%s\n' "${files[@]}" | jq -R . | jq -s .)
    local now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Merge with existing attachments
    jq --argjson id "$id" --argjson new "$new_attachments" --arg now "$now" '
        (.issues[] | select((.id|tonumber)==$id)) |= . + {
            attachments: ((.attachments // []) + $new | unique),
            updated_at: $now
        }
    ' "$VIBAN_JSON" > "$VIBAN_JSON.tmp" && mv "$VIBAN_JSON.tmp" "$VIBAN_JSON"

    echo "✓ $(display_id "$id" "$(get_ext_id "$id")"): ${#files[@]} file(s) attached"
}

cmd_link() {
    init_json
    [[ -z "$1" || "$2" != "blocks" || -z "$3" ]] && { echo "Usage: viban link <id> blocks <id>"; exit 1; }
    local blocker_id="$1" blocked_id="$3"

    # Verify both issues exist
    local b1=$(jq -r --argjson id "$blocker_id" '.issues[]|select((.id|tonumber)==$id)|.id//empty' "$VIBAN_JSON")
    local b2=$(jq -r --argjson id "$blocked_id" '.issues[]|select((.id|tonumber)==$id)|.id//empty' "$VIBAN_JSON")
    [[ -z "$b1" ]] && { echo "Error: Issue #$blocker_id not found"; exit 1; }
    [[ -z "$b2" ]] && { echo "Error: Issue #$blocked_id not found"; exit 1; }
    [[ "$blocker_id" == "$blocked_id" ]] && { echo "Error: Cannot block self"; exit 1; }

    local now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    jq --argjson bid "$blocked_id" --argjson rid "$blocker_id" --arg now "$now" \
        '(.issues[]|select((.id|tonumber)==$bid)) |= . + {blocked_by:((.blocked_by // []) | if index($rid) then . else . + [$rid] end),updated_at:$now}' \
        "$VIBAN_JSON" > "$VIBAN_JSON.tmp" && mv "$VIBAN_JSON.tmp" "$VIBAN_JSON"

    echo "✓ #$blocker_id blocks #$blocked_id"
}

cmd_unlink() {
    init_json
    [[ -z "$1" || "$2" != "blocks" || -z "$3" ]] && { echo "Usage: viban unlink <id> blocks <id>"; exit 1; }
    local blocker_id="$1" blocked_id="$3"

    local now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    jq --argjson bid "$blocked_id" --argjson rid "$blocker_id" --arg now "$now" \
        '(.issues[]|select((.id|tonumber)==$bid)) |= . + {blocked_by:((.blocked_by // []) - [$rid]),updated_at:$now}' \
        "$VIBAN_JSON" > "$VIBAN_JSON.tmp" && mv "$VIBAN_JSON.tmp" "$VIBAN_JSON"

    echo "✓ #$blocker_id no longer blocks #$blocked_id"
}

cmd_stats() {
    init_json
    local now_epoch=$(date +%s)
    local week_ago_epoch=$((now_epoch - 604800))

    # Total by status
    echo ""
    echo "Board Summary"
    echo "─────────────"
    local backlog_n=$(jq '[.issues[]|select(.status=="backlog")]|length' "$VIBAN_JSON")
    local wip_n=$(jq '[.issues[]|select(.status=="in_progress")]|length' "$VIBAN_JSON")
    local review_n=$(jq '[.issues[]|select(.status=="review")]|length' "$VIBAN_JSON")
    local done_n=$(jq '[.issues[]|select(.status=="done")]|length' "$VIBAN_JSON")
    local total_n=$(jq '.issues|length' "$VIBAN_JSON")
    echo "  Backlog: $backlog_n  In Progress: $wip_n  Review: $review_n  Done: $done_n  Total: $total_n"

    # P0/P1 open count
    local p0_n=$(jq '[.issues[]|select(.status!="done" and .priority=="P0")]|length' "$VIBAN_JSON")
    local p1_n=$(jq '[.issues[]|select(.status!="done" and .priority=="P1")]|length' "$VIBAN_JSON")
    echo "  Open P0: $p0_n  Open P1: $p1_n"

    # Issues added/closed this week
    echo ""
    echo "This Week (last 7 days)"
    echo "───────────────────────"
    local week_ago_iso=$(date -u -r $week_ago_epoch +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -d "@$week_ago_epoch" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null)
    local added_week=$(jq -r --arg since "$week_ago_iso" '[.issues[]|select(.created_at >= $since)]|length' "$VIBAN_JSON")
    local closed_week=$(jq -r --arg since "$week_ago_iso" '[.issues[]|select(.status=="done" and .updated_at >= $since)]|length' "$VIBAN_JSON")
    echo "  Added: $added_week  Completed: $closed_week"

    # Average cycle time (created_at → updated_at for done issues)
    echo ""
    echo "Cycle Time"
    echo "──────────"
    local avg_hours=$(jq -r '
        [.issues[]|select(.status=="done")|
            ((.updated_at|split("T")[0]|split("-")|map(tonumber)) as [$y2,$m2,$d2] |
             (.created_at|split("T")[0]|split("-")|map(tonumber)) as [$y1,$m1,$d1] |
             (($y2-$y1)*365 + ($m2-$m1)*30 + ($d2-$d1)) * 24)
        ] | if length == 0 then null else (add / length | floor) end
    ' "$VIBAN_JSON")
    if [[ "$avg_hours" == "null" || -z "$avg_hours" ]]; then
        echo "  Average: no completed issues"
    elif [[ "$avg_hours" -lt 24 ]]; then
        echo "  Average: <1 day"
    else
        echo "  Average: $((avg_hours / 24)) days"
    fi

    # Oldest open issue
    echo ""
    echo "Oldest Open Issue"
    echo "─────────────────"
    local oldest=$(jq -r '[.issues[]|select(.status!="done")]|sort_by(.created_at)|first|if . then "#\(.id) [\(.priority)] \(.title) (created \(.created_at|split("T")[0]))" else "none" end' "$VIBAN_JSON")
    echo "  $oldest"
    echo ""
}

cmd_migrate() {
    init_json
    echo "Migrating issues..."
    local now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Migration 1: extract [BUG], [FEATURE], [REFACTOR] from title to type field
    # Also strip [P0-P3] from title if present (already in priority field)
    echo "  - Extracting type from titles..."
    jq --arg now "$now" '
        .issues = [.issues[] |
            # Extract type from title
            (if (.title | test("^\\[BUG\\]"; "i")) then "bug"
             elif (.title | test("^\\[FEATURE\\]"; "i")) then "feat"
             elif (.title | test("^\\[FEAT\\]"; "i")) then "feat"
             elif (.title | test("^\\[REFACTOR\\]"; "i")) then "refactor"
             elif (.title | test("^\\[CHORE\\]"; "i")) then "chore"
             else .type // null end) as $extracted_type |

            # Clean title: remove [BUG], [FEATURE], [REFACTOR], [CHORE], [P0-P3] prefixes
            (.title |
                gsub("^\\[BUG\\]\\s*"; "") |
                gsub("^\\[FEATURE\\]\\s*"; "") |
                gsub("^\\[FEAT\\]\\s*"; "") |
                gsub("^\\[REFACTOR\\]\\s*"; "") |
                gsub("^\\[CHORE\\]\\s*"; "") |
                gsub("^\\[P[0-3]\\]\\s*"; "")
            ) as $clean_title |

            # Update issue
            . + {
                title: $clean_title,
                type: (if $extracted_type then $extracted_type else .type end),
                updated_at: $now
            }
        ]
    ' "$VIBAN_JSON" > "$VIBAN_JSON.tmp" && mv "$VIBAN_JSON.tmp" "$VIBAN_JSON"

    # Migration 2: Remove order field from all issues
    # New behavior: order is only set when manually moved, otherwise follows priority
    echo "  - Removing order field (reset to priority-based sorting)..."
    jq --arg now "$now" '
        .issues = [.issues[] | del(.order) | . + {updated_at: $now}]
    ' "$VIBAN_JSON" > "$VIBAN_JSON.tmp" && mv "$VIBAN_JSON.tmp" "$VIBAN_JSON"

    echo "✓ Migration complete"
    echo ""
    echo "Summary:"
    jq -r '
        [.issues[] | select(.type != null)] | group_by(.type) |
        .[] | "  \(.[0].type): \(length) issues"
    ' "$VIBAN_JSON"
    echo "  (no type): $(jq '[.issues[] | select(.type == null)] | length' "$VIBAN_JSON") issues"
    echo ""
    echo "Issues by priority:"
    jq -r '
        [.issues[] | select(.status != "done")] |
        group_by(.priority // "P3") | sort_by(.[0].priority) |
        .[] | "  \(.[0].priority // "P3"): \(length) issues"
    ' "$VIBAN_JSON"
}

cmd_sync() {
    local provider="${VIBAN_SYNC_PROVIDER:-}"
    # Auto-detect provider from existing sync.json or default to github
    if [[ -z "$provider" && -f "$VIBAN_DATA_DIR/sync.json" ]]; then
        provider=$(jq -r '.provider // "github"' "$VIBAN_DATA_DIR/sync.json")
    fi
    provider="${provider:-github}"

    local provider_script="$VIBAN_SCRIPT_DIR/scripts/providers/${provider}.sh"
    if [[ ! -f "$provider_script" ]]; then
        echo "Error: Unknown sync provider '$provider'"
        echo "Available: $(ls "$VIBAN_SCRIPT_DIR/scripts/providers/" 2>/dev/null | sed 's/\.sh$//' | tr '\n' ' ')"
        exit 1
    fi

    VIBAN_JSON="$VIBAN_JSON" VIBAN_DATA_DIR="$VIBAN_DATA_DIR" \
    VIBAN_PROVIDER="$provider" VIBAN_SCRIPT_DIR="$VIBAN_SCRIPT_DIR" \
        bash "$VIBAN_SCRIPT_DIR/scripts/sync.sh" "$@"
}
