# lib/helpers.zsh - Utility functions for data operations
check_deps() {
    command -v gum &>/dev/null || { echo "Error: gum required"; exit 1; }
    command -v jq &>/dev/null || { echo "Error: jq required"; exit 1; }
}

init_json() {
    if [[ ! -f "$VIBAN_JSON" ]]; then
        local max_wt_id=0
        if [[ -d "$VIBAN_DATA_DIR/worktrees" ]]; then
            local wt_id
            for d in "$VIBAN_DATA_DIR/worktrees/"*(/N); do
                wt_id="${d:t}"
                [[ "$wt_id" =~ ^[0-9]+$ ]] && (( wt_id > max_wt_id )) && max_wt_id=$wt_id
            done
        fi
        local next_id=$((max_wt_id + 1))
        echo "{\"version\":2,\"next_id\":$next_id,\"issues\":[]}" > "$VIBAN_JSON"
    elif ! jq empty "$VIBAN_JSON" 2>/dev/null; then
        echo "Error: $VIBAN_JSON is not valid JSON"
        echo "Run 'viban restore' to recover from a backup"
        exit 1
    elif [[ $(jq '.version // 1' "$VIBAN_JSON") -lt 2 ]]; then
        jq '{
            version: 2,
            next_id: (([.issues[].id] | max // 0) + 1),
            issues: .issues
        }' "$VIBAN_JSON" > "$VIBAN_JSON.tmp" && mv "$VIBAN_JSON.tmp" "$VIBAN_JSON"
    fi

    # Validate required structure
    if [[ -f "$VIBAN_JSON" ]]; then
        local valid=$(jq -r '
            if (.issues | type) != "array" then "missing_issues"
            elif (.version | type) != "number" then "missing_version"
            elif (.issues | map(select(.id == null or .title == null or .status == null)) | length) > 0 then "invalid_issue"
            else "ok"
            end
        ' "$VIBAN_JSON" 2>/dev/null)
        if [[ "$valid" != "ok" ]]; then
            echo "Error: viban.json validation failed ($valid)"
            echo "  Required: .version (number), .issues (array), each issue needs id, title, status"
            echo "Run 'viban restore' to recover from a backup"
            exit 1
        fi
    fi
}

get_next_id() { jq -r '.next_id // (([.issues[].id] | max // 0) + 1)' "$VIBAN_JSON"; }

# Display ID: show external_id if present, otherwise #id
display_id() { local id="$1" ext_id="${2:-}"; [[ -n "$ext_id" && "$ext_id" != "null" ]] && echo "$ext_id" || echo "#$id"; }

# Get external_id for an issue by internal id
get_ext_id() { jq -r --argjson id "$1" '.issues[]|select((.id|tonumber)==$id)|.external_id//""' "$VIBAN_JSON"; }

# Calculate effective order for sorting (priority-based virtual order for cards without order)
# Used internally for fractional indexing calculations
# Cards with order: use actual order
# Cards without order: P0=1000000, P1=2000000, P2=3000000, P3=4000000 + id
calc_effective_order() {
    local order="$1"
    local priority="${2:-P3}"
    local id="$3"

    if [[ -n "$order" && "$order" != "null" ]]; then
        echo "$order"
    else
        local base_order
        case "$priority" in
            P0) base_order=1000000;;
            P1) base_order=2000000;;
            P2) base_order=3000000;;
            *)  base_order=4000000;;
        esac
        echo $((base_order + id))
    fi
}

add_issue() {
    local title=$(gum input --placeholder "Enter task title..." --width 50 \
        --prompt.foreground "${C[accent]}" --cursor.foreground "${C[selected]}")
    [[ -z "$title" ]] && return

    # Select type
    local issue_type=$(gum choose "bug (BUG)" "feat (FEATURE)" "chore (CHORE)" "refactor (REFACTOR)" \
        --header "Select type:" --cursor.foreground "${C[selected]}")
    issue_type="${issue_type%% *}"  # Extract bug, feat, chore, or refactor
    [[ -z "$issue_type" ]] && issue_type="feat"

    # Select priority
    local priority=$(gum choose "P0 (CRITICAL)" "P1 (HIGH)" "P2 (MEDIUM)" "P3 (LOW)" \
        --header "Select priority:" --cursor.foreground "${C[selected]}")
    priority="${priority%% *}"  # Extract P0, P1, P2, or P3
    [[ -z "$priority" ]] && priority="P3"

    local desc=""
    if gum confirm "Add description?" --affirmative "Yes (open editor)" --negative "No" \
        --selected.foreground="#000000" --selected.background "${C[accent]}"; then
        local tmpfile=$(mktemp)
        local editor="${EDITOR:-${VISUAL:-vim}}"
        local next_id=$(get_next_id)
        local today=$(date +"%Y-%m-%d")
        cat > "$tmpfile" <<TEMPLATE
# ─────────────────────────────────────────────
# VIBAN Issue #${next_id}
# ─────────────────────────────────────────────
# Title: $title
# Priority: $priority
# Created: $today
# Status: backlog
# ─────────────────────────────────────────────

# ▼ Write description below (content below this line will be saved)

TEMPLATE
        $editor "$tmpfile"
        desc=$(sed '/^#/d' "$tmpfile" | sed '/./,$!d')
        rm -f "$tmpfile"
    fi

    local id=$(get_next_id) now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    # New cards don't have order - they follow priority-based sorting
    # Order is only assigned when manually moved
    local tmpjson=$(mktemp)
    printf '%s' "$desc" > "$tmpjson"
    jq --arg id "$id" --arg title "$title" --rawfile desc "$tmpjson" --arg priority "$priority" --arg issue_type "$issue_type" --arg now "$now" '
        .next_id = ((.next_id // 0) + 1) |
        .issues += [{
            id:($id|tonumber),
            title:$title,
            description:$desc,
            status:"backlog",
            priority:$priority,
            type:$issue_type,
            assigned_to:null,
            created_at:$now,
            updated_at:$now
        }]' "$VIBAN_JSON" > "$VIBAN_JSON.tmp" && mv "$VIBAN_JSON.tmp" "$VIBAN_JSON"
    rm -f "$tmpjson"
}

# Sort: backlog/in_progress by effective order, review by updated_at desc
# Effective order: if .order exists -> use it (manually positioned)
#                  if .order is null -> priority-based virtual order (P0=1M, P1=2M, P2=3M, P3=4M) + id
# This ensures: manually ordered cards stay fixed, others follow priority order
get_issues_by_status() {
    local st="$1"
    if [[ "$st" == "review" ]]; then
        jq -r --arg s "$st" '.issues|map(select(.status==$s))|sort_by(.updated_at)|reverse' "$VIBAN_JSON"
    else
        jq -r --arg s "$st" '
            .issues | map(select(.status==$s)) | sort_by(
                if .order != null then [0, .order]
                else [1, ({"P0":0,"P1":1,"P2":2,"P3":3}[.priority // "P3"] // 3), .id]
                end
            )
        ' "$VIBAN_JSON"
    fi
}
count_issues_by_status() { jq -r --arg s "$1" '[.issues[]|select(.status==$s)]|length' "$VIBAN_JSON"; }

# Get jq sort expression for status (review uses updated_at, others use order/priority)
get_sort_expr() {
    local st="$1"
    if [[ "$st" == "review" ]]; then
        echo 'sort_by(.updated_at) | reverse'
    else
        echo 'sort_by(if .order != null then [0, .order] else [1, ({"P0":0,"P1":1,"P2":2,"P3":3}[.priority // "P3"] // 3), .id] end)'
    fi
}

# Get issue ID by status and card index (uses correct sort order per status)
get_issue_id_at_index() {
    local st="$1" idx="$2" json_data="$3"
    local sort_expr=$(get_sort_expr "$st")
    printf '%s' "$json_data" | jq -r --arg s "$st" --argjson i "$idx" \
        ".issues | map(select(.status==\$s)) | $sort_expr | .[\$i].id // empty"
}

# Find card index by ID after reorder (uses correct sort order per status)
get_card_index_by_id() {
    local st="$1" card_id="$2" json_data="$3"
    local sort_expr=$(get_sort_expr "$st")
    printf '%s' "$json_data" | jq -r --arg s "$st" --argjson id "$card_id" \
        ".issues | map(select(.status==\$s)) | $sort_expr | to_entries | map(select(.value.id == \$id)) | .[0].key // 0"
}

get_term_width() {
    # Try multiple methods to get terminal width
    if [[ -n "$COLUMNS" ]]; then
        echo "$COLUMNS"
    elif command -v stty &>/dev/null; then
        stty size 2>/dev/null | cut -d' ' -f2
    else
        tput cols 2>/dev/null || echo 100
    fi
}
get_term_height() {
    if [[ -n "$LINES" ]]; then
        echo "$LINES"
    elif command -v stty &>/dev/null; then
        stty size 2>/dev/null | cut -d' ' -f1
    else
        tput lines 2>/dev/null || echo 30
    fi
}
