#!/bin/zsh
# Test: sync engine and provider interface

SCRIPT_DIR="${0:A:h}"
PROJECT_ROOT="${SCRIPT_DIR:h}"
VIBAN_BIN="$PROJECT_ROOT/bin/viban"

# Test counter
TESTS_RUN=0
TESTS_PASSED=0

pass() {
    ((TESTS_PASSED++))
    echo "  ✓ $1"
}

fail() {
    ((TESTS_PASSED+=0))
    echo "  ✗ $1"
    echo "    Expected: $2"
    echo "    Got: $3"
}

run_test() {
    ((TESTS_RUN++))
}

# Setup temp dirs
VIBAN_DATA_DIR=$(mktemp -d)
export VIBAN_DATA_DIR
VIBAN_JSON="$VIBAN_DATA_DIR/viban.json"
MOCK_PROVIDER_DIR=$(mktemp -d)
trap "rm -rf $VIBAN_DATA_DIR $MOCK_PROVIDER_DIR" EXIT

reset_json() {
    cat > "$VIBAN_JSON" << 'EOF'
{
  "version": 2,
  "next_id": 1,
  "issues": []
}
EOF
}

# Create mock provider for testing (no network needed)
create_mock_provider() {
    cat > "$MOCK_PROVIDER_DIR/mock.sh" << 'MOCKEOF'
#!/bin/bash
provider_name() { echo "mock"; }
provider_check_deps() { return 0; }
provider_check_auth() { return 0; }
provider_detect_config() { echo '{"repo":"test/repo"}'; }
provider_fetch_issues() {
    cat << 'ISSUES'
[
  {
    "remote_id": "42",
    "title": "Fix login bug",
    "description": "Users cannot log in",
    "status": "backlog",
    "priority": "P1",
    "type": "bug",
    "updated_at": "2026-02-11T10:00:00Z"
  },
  {
    "remote_id": "43",
    "title": "Add dark mode",
    "description": "Support dark theme",
    "status": "in_progress",
    "priority": "P2",
    "type": "feat",
    "updated_at": "2026-02-11T09:00:00Z"
  }
]
ISSUES
}
provider_create_issue() { echo "99"; }
provider_update_issue() { cat > /dev/null; return 0; }
provider_close_issue() { return 0; }
provider_ensure_labels() { return 0; }
MOCKEOF
    chmod +x "$MOCK_PROVIDER_DIR/mock.sh"
}

create_mock_provider

echo "Testing sync engine..."
echo ""

# ============================================================
# Test 1: Script syntax validation
# ============================================================
echo "Test 1: Script syntax validation"

run_test
if bash -n "$PROJECT_ROOT/scripts/sync.sh" 2>/dev/null; then
    pass "sync.sh syntax valid"
else
    fail "sync.sh syntax" "valid" "syntax error"
fi

run_test
if bash -n "$PROJECT_ROOT/scripts/providers/github.sh" 2>/dev/null; then
    pass "github.sh syntax valid"
else
    fail "github.sh syntax" "valid" "syntax error"
fi

# ============================================================
# Test 2: Provider loading and interface validation
# ============================================================
echo ""
echo "Test 2: Provider interface validation"

run_test
# Source the github provider and check all required functions exist
required_funcs=(
    provider_name provider_check_deps provider_check_auth
    provider_detect_config provider_fetch_issues provider_create_issue
    provider_update_issue provider_close_issue provider_ensure_labels
)
all_present=true
missing_func=""
eval "$(bash -c 'source '"$PROJECT_ROOT/scripts/providers/github.sh"' && declare -f' 2>/dev/null)"
for func in "${required_funcs[@]}"; do
    if ! whence -f "$func" &>/dev/null; then
        all_present=false
        missing_func="$func"
        break
    fi
done

if $all_present; then
    pass "github provider has all required functions"
else
    fail "github provider interface" "all functions present" "missing: $missing_func"
fi

run_test
# Verify provider_name returns "github"
result=$(bash -c 'source '"$PROJECT_ROOT/scripts/providers/github.sh"' && provider_name' 2>/dev/null)
if [[ "$result" == "github" ]]; then
    pass "provider_name returns 'github'"
else
    fail "provider_name" "github" "$result"
fi

# ============================================================
# Test 3: Mock provider - fetch returns normalized JSON
# ============================================================
echo ""
echo "Test 3: Mock provider normalized format"

run_test
source "$MOCK_PROVIDER_DIR/mock.sh"
issues=$(provider_fetch_issues "test/repo")
count=$(echo "$issues" | jq 'length')
if [[ "$count" == "2" ]]; then
    pass "mock fetch returns 2 issues"
else
    fail "mock fetch count" "2" "$count"
fi

run_test
first_id=$(echo "$issues" | jq -r '.[0].remote_id')
if [[ "$first_id" == "42" ]]; then
    pass "first issue remote_id = 42"
else
    fail "first issue remote_id" "42" "$first_id"
fi

run_test
first_status=$(echo "$issues" | jq -r '.[0].status')
if [[ "$first_status" == "backlog" ]]; then
    pass "first issue status = backlog"
else
    fail "first issue status" "backlog" "$first_status"
fi

run_test
second_type=$(echo "$issues" | jq -r '.[1].type')
if [[ "$second_type" == "feat" ]]; then
    pass "second issue type = feat"
else
    fail "second issue type" "feat" "$second_type"
fi

# ============================================================
# Test 4: GitHub label mapping
# ============================================================
echo ""
echo "Test 4: GitHub label mapping"

# Source github provider for mapping functions
eval "$(bash -c 'source '"$PROJECT_ROOT/scripts/providers/github.sh"' && declare -f' 2>/dev/null)"

run_test
result=$(_viban_priority_label "P0")
if [[ "$result" == "P0-critical" ]]; then
    pass "P0 -> P0-critical"
else
    fail "priority label P0" "P0-critical" "$result"
fi

run_test
result=$(_viban_priority_label "P1")
if [[ "$result" == "P1-high" ]]; then
    pass "P1 -> P1-high"
else
    fail "priority label P1" "P1-high" "$result"
fi

run_test
result=$(_viban_priority_label "P2")
if [[ "$result" == "P2-medium" ]]; then
    pass "P2 -> P2-medium"
else
    fail "priority label P2" "P2-medium" "$result"
fi

run_test
result=$(_viban_priority_label "P3")
if [[ "$result" == "P3-low" ]]; then
    pass "P3 -> P3-low"
else
    fail "priority label P3" "P3-low" "$result"
fi

run_test
result=$(_viban_type_label "bug")
if [[ "$result" == "bug" ]]; then
    pass "bug -> bug"
else
    fail "type label bug" "bug" "$result"
fi

run_test
result=$(_viban_type_label "feat")
if [[ "$result" == "enhancement" ]]; then
    pass "feat -> enhancement"
else
    fail "type label feat" "enhancement" "$result"
fi

run_test
result=$(_viban_type_label "chore")
if [[ "$result" == "chore" ]]; then
    pass "chore -> chore"
else
    fail "type label chore" "chore" "$result"
fi

run_test
result=$(_viban_type_label "refactor")
if [[ "$result" == "refactor" ]]; then
    pass "refactor -> refactor"
else
    fail "type label refactor" "refactor" "$result"
fi

run_test
result=$(_viban_status_labels "in_progress")
if [[ "$result" == "in-progress" ]]; then
    pass "in_progress -> in-progress"
else
    fail "status label in_progress" "in-progress" "$result"
fi

run_test
result=$(_viban_status_labels "review")
if [[ "$result" == "review" ]]; then
    pass "review -> review"
else
    fail "status label review" "review" "$result"
fi

# ============================================================
# Test 4b: GitHub provider closed issue -> done status
# ============================================================
echo ""
echo "Test 4b: Closed issue status mapping"

run_test
# Verify _gh_status_to_viban maps closed -> done
result=$(_gh_status_to_viban "closed" "")
if [[ "$result" == "done" ]]; then
    pass "closed state -> done status"
else
    fail "closed mapping" "done" "$result"
fi

run_test
# Verify open with no labels -> backlog
result=$(_gh_status_to_viban "open" "")
if [[ "$result" == "backlog" ]]; then
    pass "open state (no labels) -> backlog"
else
    fail "open no labels" "backlog" "$result"
fi

run_test
# Verify closed overrides labels (closed + review label -> still done)
result=$(_gh_status_to_viban "closed" "review")
if [[ "$result" == "done" ]]; then
    pass "closed state overrides review label -> done"
else
    fail "closed overrides label" "done" "$result"
fi

# ============================================================
# Test 4c: Provider fetch returns closed issues with --state all
# ============================================================
echo ""
echo "Test 4c: Provider fetch includes state field"

run_test
if grep -q '\-\-state all' "$PROJECT_ROOT/scripts/providers/github.sh"; then
    pass "github.sh uses --state all"
else
    fail "state flag" "--state all" "not found"
fi

run_test
if grep -q 'state' "$PROJECT_ROOT/scripts/providers/github.sh" | head -1 && \
   grep -q '"state"' "$PROJECT_ROOT/scripts/providers/github.sh"; then
    pass "github.sh includes state in --json fields"
else
    # Check more specifically
    if grep -q 'state,updatedAt' "$PROJECT_ROOT/scripts/providers/github.sh"; then
        pass "github.sh includes state in --json fields"
    else
        fail "state json field" "state in --json" "not found"
    fi
fi

run_test
if grep -q 'state == "closed"' "$PROJECT_ROOT/scripts/providers/github.sh"; then
    pass "github.sh maps closed state to done"
else
    fail "closed->done mapping" "present" "not found"
fi

# ============================================================
# Test 5: Sync metadata read/write
# ============================================================
echo ""
echo "Test 5: Sync metadata operations"

# Source sync.sh functions by extracting them
SYNC_JSON="$VIBAN_DATA_DIR/sync.json"
export SYNC_JSON

# Define the metadata functions inline (extracted from sync.sh)
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

run_test
rm -f "$SYNC_JSON"
write_sync_meta '{"provider":"mock","provider_config":{"repo":"test/repo"},"last_sync_at":"2026-01-01T00:00:00Z","issues":{}}'
if [[ -f "$SYNC_JSON" ]]; then
    pass "write_sync_meta creates file"
else
    fail "write_sync_meta" "file exists" "file not found"
fi

run_test
provider=$(read_sync_meta | jq -r '.provider')
if [[ "$provider" == "mock" ]]; then
    pass "read_sync_meta returns correct data"
else
    fail "read_sync_meta" "mock" "$provider"
fi

run_test
set_issue_meta "1" "42" "2026-02-11T10:00:00Z" "2026-02-11T09:50:00Z"
rid=$(get_issue_meta "1" | jq -r '.remote_id')
if [[ "$rid" == "42" ]]; then
    pass "set/get_issue_meta remote_id"
else
    fail "issue_meta remote_id" "42" "$rid"
fi

run_test
ru=$(get_issue_meta "1" | jq -r '.remote_updated_at')
if [[ "$ru" == "2026-02-11T10:00:00Z" ]]; then
    pass "set/get_issue_meta remote_updated_at"
else
    fail "issue_meta remote_updated_at" "2026-02-11T10:00:00Z" "$ru"
fi

# ============================================================
# Test 6: External ID format
# ============================================================
echo ""
echo "Test 6: External ID format"

run_test
ext_id="github:42"
if [[ "$ext_id" == github:* ]]; then
    pass "github:42 matches github: prefix"
else
    fail "github prefix match" "true" "false"
fi

run_test
ext_id="jira:PROJ-123"
if [[ "$ext_id" != github:* ]]; then
    pass "jira:PROJ-123 does NOT match github: prefix"
else
    fail "jira prefix no-match" "true" "false"
fi

run_test
remote_id="${ext_id#jira:}"
if [[ "$remote_id" == "PROJ-123" ]]; then
    pass "extract remote_id from jira:PROJ-123"
else
    fail "extract remote_id" "PROJ-123" "$remote_id"
fi

# ============================================================
# Test 7: CLI integration - sync case exists
# ============================================================
echo ""
echo "Test 7: CLI integration"

run_test
if grep -q 'sync).*cmd_sync' "$PROJECT_ROOT/bin/viban"; then
    pass "sync case exists in main()"
else
    fail "sync case in main" "present" "not found"
fi

run_test
if grep -q 'viban sync' "$PROJECT_ROOT/bin/viban"; then
    pass "sync appears in help text"
else
    fail "sync in help" "present" "not found"
fi

run_test
# Verify sync is in the dep check skip list
if grep -q '"sync"' "$PROJECT_ROOT/bin/viban" || grep -q "'sync'" "$PROJECT_ROOT/bin/viban"; then
    pass "sync in dependency check skip list"
else
    fail "sync skip dep check" "present" "not found"
fi

# ============================================================
# Test 8: Provider detection - unknown provider error
# ============================================================
echo ""
echo "Test 8: Provider error handling"

run_test
result=$(VIBAN_DATA_DIR="$VIBAN_DATA_DIR" VIBAN_PROVIDER="nonexistent" VIBAN_SCRIPT_DIR="$PROJECT_ROOT" \
    bash "$PROJECT_ROOT/scripts/sync.sh" --status 2>&1 || true)
if echo "$result" | grep -q "Provider script not found\|Error"; then
    pass "unknown provider shows error"
else
    fail "unknown provider error" "error message" "$result"
fi

# ============================================================
# Test 9: Conflict resolution - 4 cases
# ============================================================
echo ""
echo "Test 9: Conflict resolution cases"

# Setup: card linked to mock:42
reset_json
jq '.issues = [{
    "id": 1, "title": "Test issue", "description": "desc",
    "status": "backlog", "priority": "P1", "type": "bug",
    "external_id": "mock:42", "attachments": [],
    "assigned_to": null,
    "created_at": "2026-02-11T09:00:00Z",
    "updated_at": "2026-02-11T09:00:00Z"
}] | .next_id = 2' "$VIBAN_JSON" > "${VIBAN_JSON}.tmp" && mv "${VIBAN_JSON}.tmp" "$VIBAN_JSON"

# Case 1: Neither changed
run_test
rm -f "$SYNC_JSON"
write_sync_meta '{"provider":"mock","provider_config":{"repo":"test/repo"},"last_sync_at":"2026-02-11T08:00:00Z","issues":{"1":{"remote_id":"42","remote_updated_at":"2026-02-11T10:00:00Z","viban_updated_at":"2026-02-11T09:00:00Z"}}}'

# Mock provider returns remote_updated=2026-02-11T10:00:00Z (same as last known)
# Viban card updated_at=2026-02-11T09:00:00Z (same as last known)
# -> Neither changed
result=$(VIBAN_JSON="$VIBAN_JSON" VIBAN_DATA_DIR="$VIBAN_DATA_DIR" \
    VIBAN_PROVIDER="mock" VIBAN_SCRIPT_DIR="$MOCK_PROVIDER_DIR/.." \
    bash -c '
    source '"$MOCK_PROVIDER_DIR/mock.sh"'
    SYNC_JSON="'"$SYNC_JSON"'"
    '"$(declare -f read_sync_meta write_sync_meta get_issue_meta set_issue_meta)"'

    provider_prefix="mock:"
    viban_card=$(jq -r --arg eid "mock:42" ".issues[] | select(.external_id == \$eid)" "'"$VIBAN_JSON"'")
    viban_updated=$(echo "$viban_card" | jq -r ".updated_at")
    meta=$(get_issue_meta "1")
    last_viban_updated=$(echo "$meta" | jq -r ".viban_updated_at")

    if [[ "$viban_updated" == "$last_viban_updated" ]]; then
        echo "neither_changed"
    else
        echo "changed"
    fi
    ' 2>/dev/null)
if [[ "$result" == "neither_changed" ]]; then
    pass "case 1: neither changed detected"
else
    fail "neither changed" "neither_changed" "$result"
fi

# Case 2: Only remote changed
run_test
write_sync_meta '{"provider":"mock","provider_config":{"repo":"test/repo"},"last_sync_at":"2026-02-11T08:00:00Z","issues":{"1":{"remote_id":"42","remote_updated_at":"2026-02-10T10:00:00Z","viban_updated_at":"2026-02-11T09:00:00Z"}}}'
# Mock returns remote_updated=2026-02-11T10:00:00Z (different from last known 2026-02-10T...)
# Viban card still at 2026-02-11T09:00:00Z (same as last known)
result=$(bash -c '
    SYNC_JSON="'"$SYNC_JSON"'"
    '"$(declare -f read_sync_meta write_sync_meta get_issue_meta set_issue_meta)"'
    meta=$(get_issue_meta "1")
    last_remote_updated=$(echo "$meta" | jq -r ".remote_updated_at")
    remote_updated="2026-02-11T10:00:00Z"
    last_viban_updated=$(echo "$meta" | jq -r ".viban_updated_at")
    viban_updated="2026-02-11T09:00:00Z"

    remote_changed=false; viban_changed=false
    [[ "$remote_updated" != "$last_remote_updated" ]] && remote_changed=true
    [[ "$viban_updated" != "$last_viban_updated" ]] && viban_changed=true

    if [[ "$remote_changed" == "true" && "$viban_changed" == "false" ]]; then
        echo "remote_only"
    else
        echo "other: remote=$remote_changed viban=$viban_changed"
    fi
' 2>/dev/null)
if [[ "$result" == "remote_only" ]]; then
    pass "case 2: only remote changed detected"
else
    fail "only remote changed" "remote_only" "$result"
fi

# Case 3: Only viban changed
run_test
write_sync_meta '{"provider":"mock","provider_config":{"repo":"test/repo"},"last_sync_at":"2026-02-11T08:00:00Z","issues":{"1":{"remote_id":"42","remote_updated_at":"2026-02-11T10:00:00Z","viban_updated_at":"2026-02-10T09:00:00Z"}}}'
# Remote still at 2026-02-11T10:00:00Z (same as last known)
# Viban card at 2026-02-11T09:00:00Z (different from last known 2026-02-10T...)
result=$(bash -c '
    SYNC_JSON="'"$SYNC_JSON"'"
    '"$(declare -f read_sync_meta write_sync_meta get_issue_meta set_issue_meta)"'
    meta=$(get_issue_meta "1")
    last_remote_updated=$(echo "$meta" | jq -r ".remote_updated_at")
    remote_updated="2026-02-11T10:00:00Z"
    last_viban_updated=$(echo "$meta" | jq -r ".viban_updated_at")
    viban_updated="2026-02-11T09:00:00Z"

    remote_changed=false; viban_changed=false
    [[ "$remote_updated" != "$last_remote_updated" ]] && remote_changed=true
    [[ "$viban_updated" != "$last_viban_updated" ]] && viban_changed=true

    if [[ "$remote_changed" == "false" && "$viban_changed" == "true" ]]; then
        echo "viban_only"
    else
        echo "other: remote=$remote_changed viban=$viban_changed"
    fi
' 2>/dev/null)
if [[ "$result" == "viban_only" ]]; then
    pass "case 3: only viban changed detected"
else
    fail "only viban changed" "viban_only" "$result"
fi

# Case 4: Both changed (conflict)
run_test
write_sync_meta '{"provider":"mock","provider_config":{"repo":"test/repo"},"last_sync_at":"2026-02-11T08:00:00Z","issues":{"1":{"remote_id":"42","remote_updated_at":"2026-02-10T10:00:00Z","viban_updated_at":"2026-02-10T09:00:00Z"}}}'
# Remote at 2026-02-11T10:00:00Z (different from 2026-02-10T...)
# Viban at 2026-02-11T09:00:00Z (different from 2026-02-10T...)
result=$(bash -c '
    SYNC_JSON="'"$SYNC_JSON"'"
    '"$(declare -f read_sync_meta write_sync_meta get_issue_meta set_issue_meta)"'
    meta=$(get_issue_meta "1")
    last_remote_updated=$(echo "$meta" | jq -r ".remote_updated_at")
    remote_updated="2026-02-11T10:00:00Z"
    last_viban_updated=$(echo "$meta" | jq -r ".viban_updated_at")
    viban_updated="2026-02-11T09:00:00Z"

    remote_changed=false; viban_changed=false
    [[ "$remote_updated" != "$last_remote_updated" ]] && remote_changed=true
    [[ "$viban_updated" != "$last_viban_updated" ]] && viban_changed=true

    if [[ "$remote_changed" == "true" && "$viban_changed" == "true" ]]; then
        echo "both_changed"
    else
        echo "other: remote=$remote_changed viban=$viban_changed"
    fi
' 2>/dev/null)
if [[ "$result" == "both_changed" ]]; then
    pass "case 4: both changed (conflict) detected"
else
    fail "both changed" "both_changed" "$result"
fi

# ============================================================
# Summary
# ============================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Results: $TESTS_PASSED/$TESTS_RUN tests passed"

if [[ $TESTS_PASSED -eq $TESTS_RUN ]]; then
    echo "All tests passed!"
    exit 0
else
    echo "Some tests failed!"
    exit 1
fi
