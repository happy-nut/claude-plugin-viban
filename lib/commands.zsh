# lib/commands.zsh - CLI command implementations
cmd_list() {
    init_json
    local _done_ids=$(jq '[.issues[]|select(.status=="done")|.id]' "$VIBAN_JSON")
    local filter_status="" filter_priority="" filter_type="" filter_search=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --status)   filter_status="$2"; shift 2;;
            --priority) filter_priority="$2"; shift 2;;
            --type)     filter_type="$2"; shift 2;;
            --search)   filter_search="$2"; shift 2;;
            *) shift;;
        esac
    done

    local has_filter=false
    [[ -n "$filter_status" || -n "$filter_priority" || -n "$filter_type" || -n "$filter_search" ]] && has_filter=true

    echo ""
    if $has_filter; then
        # Build jq filter expression
        local jq_filter='.issues | map(select(1==1'
        [[ -n "$filter_status" ]] && jq_filter+=' and .status==$fst'
        [[ -n "$filter_priority" ]] && jq_filter+=' and ([.priority // "P3"] | inside($fpr | split(",")))'
        [[ -n "$filter_type" ]] && jq_filter+=' and ([.type // ""] | inside($fty | split(",")))'
        [[ -n "$filter_search" ]] && jq_filter+=' and ((.title | ascii_downcase | contains($fsrc)) or ((.description // "") | ascii_downcase | contains($fsrc)))'
        jq_filter+='))'

        local count
        count=$(jq -r --arg fst "$filter_status" --arg fpr "$filter_priority" --arg fty "$filter_type" --arg fsrc "${(L)filter_search}" \
            "$jq_filter | length" "$VIBAN_JSON")

        local label_parts=()
        [[ -n "$filter_status" ]] && label_parts+=("status=$filter_status")
        [[ -n "$filter_priority" ]] && label_parts+=("priority=$filter_priority")
        [[ -n "$filter_type" ]] && label_parts+=("type=$filter_type")
        [[ -n "$filter_search" ]] && label_parts+=("search=\"$filter_search\"")
        echo "● Filtered: ${(j:, :)label_parts} ($count)"

        jq -r --arg fst "$filter_status" --arg fpr "$filter_priority" --arg fty "$filter_type" --arg fsrc "${(L)filter_search}" --argjson done "$_done_ids" \
            "$jq_filter | sort_by(.updated_at) | reverse | .[] |
            \"  \(if .external_id then .external_id else \"#\\(.id)\" end) [\\(.priority // \"P3\")]\(if .type then \" [\\(.type | ascii_upcase)]\" else \"\" end)\(if ((.blocked_by // []) | length > 0 and any(. as \$b | \$done | index(\$b) == null)) then \" [BLOCKED]\" else \"\" end) \\(.title)\"" "$VIBAN_JSON"
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

    # Apply templates: .viban/templates.json defaults per issue type
    local templates_file="$VIBAN_DATA_DIR/templates.json"
    if [[ -f "$templates_file" && -n "$issue_type" ]]; then
        local tmpl=$(jq -r --arg t "$issue_type" '.[$t] // empty' "$templates_file" 2>/dev/null)
        if [[ -n "$tmpl" ]]; then
            [[ "$priority" == "P3" ]] && {
                local tmpl_priority=$(echo "$tmpl" | jq -r '.priority // empty')
                [[ -n "$tmpl_priority" ]] && priority="$tmpl_priority"
            }
            [[ -z "$desc" ]] && {
                local tmpl_desc=$(echo "$tmpl" | jq -r '.description // empty')
                [[ -n "$tmpl_desc" ]] && desc="$tmpl_desc"
            }
        fi
    fi

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
    [[ -z "$1" ]] && { echo "Usage: viban done <id> [--purge] [--dry-run]"; exit 1; }
    local id="$1"
    local remove=false dry_run=false
    shift
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --remove|--purge) remove=true; shift;;
            --dry-run) dry_run=true; shift;;
            *) shift;;
        esac
    done

    if $dry_run; then
        local title=$(jq -r --argjson id "$id" '.issues[]|select((.id|tonumber)==$id)|.title//empty' "$VIBAN_JSON")
        [[ -z "$title" ]] && { echo "Error: Issue #$id not found"; return 1; }
        if $remove; then
            echo "[dry-run] Would permanently delete #$id \"$title\""
        else
            echo "[dry-run] Would mark #$id \"$title\" as done"
        fi
        local wt_dir="$VIBAN_DATA_DIR/worktrees/$id"
        [[ -d "$wt_dir" ]] && echo "[dry-run] Would remove worktree at $wt_dir"
        return 0
    fi

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
    [[ -z "$1" || "$2" != "blocks" || -z "$3" ]] && { echo "Usage: viban unlink <id> blocks <id> [--dry-run]"; exit 1; }
    local blocker_id="$1" blocked_id="$3"
    local dry_run=false
    [[ "$4" == "--dry-run" ]] && dry_run=true

    if $dry_run; then
        echo "[dry-run] Would remove link: #$blocker_id blocks #$blocked_id"
        return 0
    fi

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

cmd_backup() {
    init_json
    local backup_dir="$VIBAN_DATA_DIR/backups"
    mkdir -p "$backup_dir"
    local ts=$(date +"%Y%m%d_%H%M%S")
    local backup_file="$backup_dir/viban_${ts}.json"
    cp "$VIBAN_JSON" "$backup_file"
    echo "✓ Backup saved: $backup_file"
}

cmd_restore() {
    init_json
    local backup_dir="$VIBAN_DATA_DIR/backups"
    if [[ ! -d "$backup_dir" ]] || [[ -z "$(ls -A "$backup_dir" 2>/dev/null)" ]]; then
        echo "No backups found in $backup_dir"
        return 1
    fi

    if [[ -n "$1" ]]; then
        # Restore specific file
        local target="$backup_dir/$1"
        [[ ! -f "$target" ]] && { echo "Error: Backup '$1' not found"; return 1; }
        cp "$target" "$VIBAN_JSON"
        echo "✓ Restored from $1"
    else
        # List available backups
        echo "Available backups:"
        local count=0
        for f in "$backup_dir"/viban_*.json(On); do
            ((count++))
            local size=$(wc -c < "$f" | tr -d ' ')
            local issues=$(jq '.issues|length' "$f" 2>/dev/null || echo "?")
            echo "  ${f:t}  (${issues} issues, ${size} bytes)"
        done
        [[ $count -eq 0 ]] && echo "  (none)"
        echo ""
        echo "Usage: viban restore <filename>"
    fi
}

cmd_export() {
    init_json
    local format="${1:-md}"

    case "$format" in
        md|markdown)
            echo "# Viban Board"
            echo ""
            local status_label
            for st in backlog in_progress review done; do
                local count=$(jq --arg s "$st" '[.issues[]|select(.status==$s)]|length' "$VIBAN_JSON")
                [[ "$count" -eq 0 ]] && continue
                case "$st" in
                    backlog) status_label="Backlog";;
                    in_progress) status_label="In Progress";;
                    review) status_label="Review";;
                    done) status_label="Done";;
                esac
                echo "## $status_label ($count)"
                echo ""
                echo "| ID | Priority | Type | Title |"
                echo "|---|---|---|---|"
                jq -r --arg s "$st" '
                    .issues | map(select(.status==$s)) |
                    sort_by(if .order != null then [0, .order] else [1, ({"P0":0,"P1":1,"P2":2,"P3":3}[.priority // "P3"] // 3), .id] end) |
                    .[] | "| #\(.id) | \(.priority // "P3") | \(.type // "-") | \(.title) |"
                ' "$VIBAN_JSON"
                echo ""
            done
            ;;
        html)
            echo "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>Viban Board</title>"
            echo "<style>body{font-family:system-ui;max-width:900px;margin:2em auto;padding:0 1em}"
            echo "table{border-collapse:collapse;width:100%;margin:1em 0}th,td{border:1px solid #ddd;padding:8px;text-align:left}"
            echo "th{background:#f5f5f5}h2{margin-top:1.5em}.P0{color:#d00}.P1{color:#e60}.P2{color:#c90}.P3{color:#090}</style></head><body>"
            echo "<h1>Viban Board</h1>"
            for st in backlog in_progress review done; do
                local count=$(jq --arg s "$st" '[.issues[]|select(.status==$s)]|length' "$VIBAN_JSON")
                [[ "$count" -eq 0 ]] && continue
                case "$st" in
                    backlog) status_label="Backlog";;
                    in_progress) status_label="In Progress";;
                    review) status_label="Review";;
                    done) status_label="Done";;
                esac
                echo "<h2>$status_label ($count)</h2>"
                echo "<table><tr><th>ID</th><th>Priority</th><th>Type</th><th>Title</th></tr>"
                jq -r --arg s "$st" '
                    .issues | map(select(.status==$s)) |
                    sort_by(if .order != null then [0, .order] else [1, ({"P0":0,"P1":1,"P2":2,"P3":3}[.priority // "P3"] // 3), .id] end) |
                    .[] | "<tr><td>#\(.id)</td><td class=\"\(.priority // "P3")\">\(.priority // "P3")</td><td>\(.type // "-")</td><td>\(.title)</td></tr>"
                ' "$VIBAN_JSON"
                echo "</table>"
            done
            echo "</body></html>"
            ;;
        *) echo "Usage: viban export [md|html]"; exit 1;;
    esac
}

cmd_changelog() {
    local range="$1"

    # Determine commit range
    if [[ -z "$range" ]]; then
        # Default: from last tag to HEAD
        local last_tag=$(git describe --tags --abbrev=0 2>/dev/null)
        if [[ -n "$last_tag" ]]; then
            range="${last_tag}..HEAD"
        else
            range=""
        fi
    fi

    # Get commits
    local log_output
    if [[ -n "$range" ]]; then
        log_output=$(git log "$range" --pretty=format:"%s" 2>/dev/null)
    else
        log_output=$(git log --pretty=format:"%s" 2>/dev/null)
    fi

    if [[ -z "$log_output" ]]; then
        echo "No commits found${range:+ in $range}"
        return 0
    fi

    # Group by type
    local -a feats fixes refactors chores others
    while IFS= read -r line; do
        case "$line" in
            feat:*|feat\(*) feats+=("${line#*: }");;
            fix:*|fix\(*)   fixes+=("${line#*: }");;
            refactor:*|refactor\(*) refactors+=("${line#*: }");;
            chore:*|chore\(*) chores+=("${line#*: }");;
            test:*|test\(*) chores+=("${line#*: }");;
            docs:*|docs\(*) chores+=("${line#*: }");;
            Merge\ pull*|Merge\ branch*) ;;  # skip merge commits
            [0-9]*) ;;  # skip version-only commits like "1.3.12"
            *) others+=("$line");;
        esac
    done <<< "$log_output"

    # Output markdown
    echo "# Changelog${range:+ ($range)}"
    echo ""

    if (( ${#feats[@]} > 0 )); then
        echo "## Features"
        for item in "${feats[@]}"; do echo "- $item"; done
        echo ""
    fi
    if (( ${#fixes[@]} > 0 )); then
        echo "## Bug Fixes"
        for item in "${fixes[@]}"; do echo "- $item"; done
        echo ""
    fi
    if (( ${#refactors[@]} > 0 )); then
        echo "## Refactors"
        for item in "${refactors[@]}"; do echo "- $item"; done
        echo ""
    fi
    if (( ${#chores[@]} > 0 )); then
        echo "## Chores"
        for item in "${chores[@]}"; do echo "- $item"; done
        echo ""
    fi
    if (( ${#others[@]} > 0 )); then
        echo "## Other"
        for item in "${others[@]}"; do echo "- $item"; done
        echo ""
    fi
}

# Archive done issues older than N days (default 30)
cmd_archive() {
    init_json
    local days=30 dry_run=false

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --days) days="$2"; shift 2;;
            --dry-run) dry_run=true; shift;;
            *) shift;;
        esac
    done

    local archive_file="$VIBAN_DATA_DIR/archive.json"
    local cutoff=$(date -u -v-${days}d +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || \
                   date -u -d "$days days ago" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null)
    [[ -z "$cutoff" ]] && { echo "Error: could not compute date cutoff"; return 1; }

    # Find done issues older than cutoff
    local to_archive=$(jq --arg cutoff "$cutoff" \
        '[.issues[] | select(.status == "done" and .updated_at < $cutoff)]' "$VIBAN_JSON")
    local count=$(printf '%s' "$to_archive" | jq 'length')

    if (( count == 0 )); then
        echo "No done issues older than $days days to archive"
        return 0
    fi

    if $dry_run; then
        echo "[dry-run] Would archive $count done issue(s) older than $days days:"
        printf '%s' "$to_archive" | jq -r '.[] | "  #\(.id) \(.title) (done \(.updated_at | split("T")[0]))"'
        return 0
    fi

    # Append to archive file
    if [[ -f "$archive_file" ]]; then
        local merged=$(jq --argjson new "$to_archive" '. + $new' "$archive_file")
        printf '%s\n' "$merged" > "$archive_file"
    else
        printf '%s\n' "$to_archive" > "$archive_file"
    fi

    # Remove archived issues from viban.json
    jq --arg cutoff "$cutoff" \
        '.issues |= map(select(.status != "done" or .updated_at >= $cutoff))' \
        "$VIBAN_JSON" > "$VIBAN_JSON.tmp" && mv "$VIBAN_JSON.tmp" "$VIBAN_JSON"

    echo "✓ Archived $count done issue(s) older than $days days"
}
