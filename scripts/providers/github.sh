#!/bin/bash
# GitHub provider for viban sync
# Implements the provider interface using the `gh` CLI

# ============================================================
# Provider Interface
# ============================================================

provider_name() {
    echo "github"
}

provider_check_deps() {
    if ! command -v gh &>/dev/null; then
        echo "Error: gh CLI not found"
        echo "  Install: brew install gh"
        echo "  Or visit: https://cli.github.com/"
        return 1
    fi
}

provider_check_auth() {
    if ! gh auth status &>/dev/null; then
        echo "Error: Not authenticated with GitHub"
        echo "  Run: gh auth login"
        return 1
    fi
}

provider_detect_config() {
    local remote_url
    remote_url=$(git remote get-url origin 2>/dev/null) || {
        echo "Error: No git remote 'origin' found"
        return 1
    }

    local repo=""
    # SSH format: git@github.com:owner/repo.git
    if [[ "$remote_url" =~ git@github\.com:([^/]+/[^/.]+)(\.git)?$ ]]; then
        repo="${BASH_REMATCH[1]}"
    # HTTPS format: https://github.com/owner/repo.git
    elif [[ "$remote_url" =~ github\.com/([^/]+/[^/.]+)(\.git)?$ ]]; then
        repo="${BASH_REMATCH[1]}"
    fi

    if [[ -z "$repo" ]]; then
        echo "Error: Could not detect GitHub repo from remote URL: $remote_url"
        return 1
    fi

    echo "{\"repo\":\"$repo\"}"
}

# ============================================================
# Label Mapping
# ============================================================

# Status labels
_gh_status_to_viban() {
    local gh_state="$1" labels="$2"
    if [[ "$gh_state" == "closed" ]]; then
        echo "done"
    elif echo "$labels" | grep -q "review"; then
        echo "review"
    elif echo "$labels" | grep -q "in-progress"; then
        echo "in_progress"
    else
        echo "backlog"
    fi
}

_viban_status_labels() {
    local st="$1"
    case "$st" in
        in_progress) echo "in-progress" ;;
        review)      echo "review" ;;
        *)           echo "" ;;
    esac
}

# Priority mapping
_gh_priority_to_viban() {
    local labels="$1"
    if echo "$labels" | grep -q "P0-critical"; then echo "P0"
    elif echo "$labels" | grep -q "P1-high"; then echo "P1"
    elif echo "$labels" | grep -q "P2-medium"; then echo "P2"
    elif echo "$labels" | grep -q "P3-low"; then echo "P3"
    else echo "P3"
    fi
}

_viban_priority_label() {
    local priority="$1"
    case "$priority" in
        P0) echo "P0-critical" ;;
        P1) echo "P1-high" ;;
        P2) echo "P2-medium" ;;
        P3) echo "P3-low" ;;
        *)  echo "" ;;
    esac
}

# Type mapping
_gh_type_to_viban() {
    local labels="$1"
    if echo "$labels" | grep -q "bug"; then echo "bug"
    elif echo "$labels" | grep -q "enhancement"; then echo "feat"
    elif echo "$labels" | grep -q "chore"; then echo "chore"
    elif echo "$labels" | grep -q "refactor"; then echo "refactor"
    else echo ""
    fi
}

_viban_type_label() {
    local type="$1"
    case "$type" in
        bug)      echo "bug" ;;
        feat)     echo "enhancement" ;;
        chore)    echo "chore" ;;
        refactor) echo "refactor" ;;
        *)        echo "" ;;
    esac
}

# ============================================================
# Core Provider Functions
# ============================================================

provider_fetch_issues() {
    local repo="$1"

    local issues
    issues=$(gh issue list --repo "$repo" --state all --json number,title,body,labels,state,updatedAt --limit 200 2>/dev/null) || {
        echo "Error: Failed to fetch issues from $repo"
        return 1
    }

    # Transform to normalized format
    echo "$issues" | jq '[.[] | {
        remote_id: (.number | tostring),
        title: .title,
        description: (.body // ""),
        status: (
            if .state == "closed" then "done"
            elif ([.labels[].name] | any(. == "review")) then "review"
            elif ([.labels[].name] | any(. == "in-progress")) then "in_progress"
            else "backlog"
            end
        ),
        priority: (
            if ([.labels[].name] | any(. == "P0-critical")) then "P0"
            elif ([.labels[].name] | any(. == "P1-high")) then "P1"
            elif ([.labels[].name] | any(. == "P2-medium")) then "P2"
            elif ([.labels[].name] | any(. == "P3-low")) then "P3"
            else "P3"
            end
        ),
        type: (
            if ([.labels[].name] | any(. == "bug")) then "bug"
            elif ([.labels[].name] | any(. == "enhancement")) then "feat"
            elif ([.labels[].name] | any(. == "chore")) then "chore"
            elif ([.labels[].name] | any(. == "refactor")) then "refactor"
            else null
            end
        ),
        updated_at: .updatedAt
    }]'
}

provider_create_issue() {
    local repo="$1"
    # Read normalized JSON from stdin
    local issue_json
    issue_json=$(cat)

    local title body labels_args
    title=$(echo "$issue_json" | jq -r '.title')
    body=$(echo "$issue_json" | jq -r '.description // ""')

    # Build labels
    local labels=()
    local status_label priority_label type_label

    status_label=$(_viban_status_labels "$(echo "$issue_json" | jq -r '.status // "backlog"')")
    [[ -n "$status_label" ]] && labels+=("$status_label")

    priority_label=$(_viban_priority_label "$(echo "$issue_json" | jq -r '.priority // "P3"')")
    [[ -n "$priority_label" ]] && labels+=("$priority_label")

    type_label=$(_viban_type_label "$(echo "$issue_json" | jq -r '.type // ""')")
    [[ -n "$type_label" ]] && labels+=("$type_label")

    local label_args=()
    for l in "${labels[@]}"; do
        label_args+=(--label "$l")
    done

    local result
    result=$(gh issue create --repo "$repo" --title "$title" --body "$body" "${label_args[@]}" 2>/dev/null) || {
        echo "Error: Failed to create issue '$title'"
        return 1
    }

    # Extract issue number from URL (gh returns URL like https://github.com/owner/repo/issues/42)
    echo "$result" | grep -o '[0-9]*$'
}

provider_update_issue() {
    local repo="$1" remote_id="$2"
    # Read normalized JSON from stdin
    local issue_json
    issue_json=$(cat)

    local title body
    title=$(echo "$issue_json" | jq -r '.title')
    body=$(echo "$issue_json" | jq -r '.description // ""')

    # Collect all desired labels
    local labels=()
    local status_label priority_label type_label

    status_label=$(_viban_status_labels "$(echo "$issue_json" | jq -r '.status // "backlog"')")
    [[ -n "$status_label" ]] && labels+=("$status_label")

    priority_label=$(_viban_priority_label "$(echo "$issue_json" | jq -r '.priority // "P3"')")
    [[ -n "$priority_label" ]] && labels+=("$priority_label")

    type_label=$(_viban_type_label "$(echo "$issue_json" | jq -r '.type // ""')")
    [[ -n "$type_label" ]] && labels+=("$type_label")

    # Remove old status/priority/type labels, then add new ones
    local remove_labels="in-progress,review,P0-critical,P1-high,P2-medium,P3-low,bug,enhancement,chore,refactor"
    gh issue edit "$remote_id" --repo "$repo" --title "$title" --body "$body" \
        --remove-label "$remove_labels" 2>/dev/null

    if [[ ${#labels[@]} -gt 0 ]]; then
        local add_labels
        add_labels=$(IFS=,; echo "${labels[*]}")
        gh issue edit "$remote_id" --repo "$repo" --add-label "$add_labels" 2>/dev/null
    fi
}

provider_close_issue() {
    local repo="$1" remote_id="$2"
    gh issue close "$remote_id" --repo "$repo" 2>/dev/null || {
        echo "Error: Failed to close issue #$remote_id"
        return 1
    }
}

provider_ensure_labels() {
    local repo="$1"

    local required_labels=(
        "in-progress:Status: In Progress:0E8A16"
        "review:Status: In Review:FBCA04"
        "P0-critical:Priority: Critical:B60205"
        "P1-high:Priority: High:D93F0B"
        "P2-medium:Priority: Medium:FBCA04"
        "P3-low:Priority: Low:0E8A16"
        "chore:Type: Chore:EEEEEE"
        "refactor:Type: Refactor:C5DEF5"
    )

    for label_def in "${required_labels[@]}"; do
        IFS=: read -r name desc color <<< "$label_def"
        gh label create "$name" --repo "$repo" --description "$desc" --color "$color" 2>/dev/null || true
    done
}
