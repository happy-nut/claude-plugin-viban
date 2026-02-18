#!/bin/zsh
# Test: cmd_archive and auto_archive behavior

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

# Setup temp viban data dir
VIBAN_DATA_DIR=$(mktemp -d)
export VIBAN_DATA_DIR
VIBAN_JSON="$VIBAN_DATA_DIR/viban.json"
trap "rm -rf $VIBAN_DATA_DIR" EXIT

reset_json() {
    cat > "$VIBAN_JSON" << 'EOF'
{
  "version": 2,
  "next_id": 1,
  "issues": []
}
EOF
}

get_issue_field() {
    local id=$1 field=$2
    jq -r --argjson id "$id" ".issues[] | select(.id == \$id) | .$field" "$VIBAN_JSON"
}

issue_count() {
    jq '.issues | length' "$VIBAN_JSON"
}

echo "Testing cmd_archive..."
echo ""

# ============================================================
# Test 1: archive moves old done issues to archive.json
# ============================================================
echo "Test 1: archive moves old done issues"

reset_json
$VIBAN_BIN add "Old done task" "desc" P2 feat >/dev/null 2>&1
# Set status=done with updated_at 60 days ago
local old_date=$(date -u -v-60d +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || \
                 date -u -d "60 days ago" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null)
jq --arg d "$old_date" '(.issues[0]) |= . + {status:"done",updated_at:$d}' \
    "$VIBAN_JSON" > "$VIBAN_JSON.tmp" && mv "$VIBAN_JSON.tmp" "$VIBAN_JSON"
run_test
$VIBAN_BIN archive >/dev/null 2>&1
count=$(issue_count)
if [[ "$count" == "0" ]]; then
    pass "old done issue removed from viban.json"
else
    fail "should have 0 issues" "0" "$count"
fi

run_test
if [[ -f "$VIBAN_DATA_DIR/archive.json" ]]; then
    archive_count=$(jq 'length' "$VIBAN_DATA_DIR/archive.json")
    if [[ "$archive_count" == "1" ]]; then
        pass "archive.json has 1 issue"
    else
        fail "archive.json should have 1 issue" "1" "$archive_count"
    fi
else
    fail "archive.json should exist" "file exists" "file missing"
fi

# ============================================================
# Test 2: archive does not touch recent done issues
# ============================================================
echo ""
echo "Test 2: archive skips recent done issues"

reset_json
rm -f "$VIBAN_DATA_DIR/archive.json"
$VIBAN_BIN add "Recent done task" "desc" P2 feat >/dev/null 2>&1
# Set status=done with updated_at now (recent)
local now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
jq --arg d "$now" '(.issues[0]) |= . + {status:"done",updated_at:$d}' \
    "$VIBAN_JSON" > "$VIBAN_JSON.tmp" && mv "$VIBAN_JSON.tmp" "$VIBAN_JSON"
run_test
output=$($VIBAN_BIN archive 2>&1)
count=$(issue_count)
if [[ "$count" == "1" ]]; then
    pass "recent done issue still in viban.json"
else
    fail "should have 1 issue" "1" "$count"
fi

# ============================================================
# Test 3: archive --days N respects custom threshold
# ============================================================
echo ""
echo "Test 3: archive --days N custom threshold"

reset_json
rm -f "$VIBAN_DATA_DIR/archive.json"
$VIBAN_BIN add "Task done 10 days ago" "desc" P2 feat >/dev/null 2>&1
local ten_days_ago=$(date -u -v-10d +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || \
                     date -u -d "10 days ago" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null)
jq --arg d "$ten_days_ago" '(.issues[0]) |= . + {status:"done",updated_at:$d}' \
    "$VIBAN_JSON" > "$VIBAN_JSON.tmp" && mv "$VIBAN_JSON.tmp" "$VIBAN_JSON"

# --days 5 should archive it (10 > 5)
run_test
$VIBAN_BIN archive --days 5 >/dev/null 2>&1
count=$(issue_count)
if [[ "$count" == "0" ]]; then
    pass "--days 5 archives 10-day-old issue"
else
    fail "should have archived" "0" "$count"
fi

# ============================================================
# Test 4: archive --days N does not archive if within threshold
# ============================================================
echo ""
echo "Test 4: archive --days N keeps issues within threshold"

reset_json
rm -f "$VIBAN_DATA_DIR/archive.json"
$VIBAN_BIN add "Task done 10 days ago" "desc" P2 feat >/dev/null 2>&1
jq --arg d "$ten_days_ago" '(.issues[0]) |= . + {status:"done",updated_at:$d}' \
    "$VIBAN_JSON" > "$VIBAN_JSON.tmp" && mv "$VIBAN_JSON.tmp" "$VIBAN_JSON"

# --days 15 should NOT archive it (10 < 15)
run_test
$VIBAN_BIN archive --days 15 >/dev/null 2>&1
count=$(issue_count)
if [[ "$count" == "1" ]]; then
    pass "--days 15 keeps 10-day-old issue"
else
    fail "should keep issue" "1" "$count"
fi

# ============================================================
# Test 5: archive --dry-run does not modify data
# ============================================================
echo ""
echo "Test 5: archive --dry-run is non-destructive"

reset_json
rm -f "$VIBAN_DATA_DIR/archive.json"
$VIBAN_BIN add "Old task for dry-run" "desc" P2 feat >/dev/null 2>&1
jq --arg d "$old_date" '(.issues[0]) |= . + {status:"done",updated_at:$d}' \
    "$VIBAN_JSON" > "$VIBAN_JSON.tmp" && mv "$VIBAN_JSON.tmp" "$VIBAN_JSON"
run_test
output=$($VIBAN_BIN archive --dry-run 2>&1)
count=$(issue_count)
if [[ "$count" == "1" ]]; then
    pass "dry-run: issue still in viban.json"
else
    fail "dry-run should not remove issues" "1" "$count"
fi

run_test
if [[ "$output" == *"dry-run"* ]]; then
    pass "dry-run: output contains 'dry-run'"
else
    fail "output should mention dry-run" "dry-run" "$output"
fi

run_test
if [[ ! -f "$VIBAN_DATA_DIR/archive.json" ]]; then
    pass "dry-run: archive.json not created"
else
    fail "dry-run should not create archive.json" "no file" "file exists"
fi

# ============================================================
# Test 6: archive --dry-run shows what would be archived
# ============================================================
echo ""
echo "Test 6: archive --dry-run shows issue info"

run_test
if [[ "$output" == *"Would archive"* ]]; then
    pass "dry-run: shows 'Would archive' message"
else
    fail "should show what would be archived" "Would archive" "$output"
fi

# ============================================================
# Test 7: archive does not touch non-done issues
# ============================================================
echo ""
echo "Test 7: archive ignores non-done issues"

reset_json
rm -f "$VIBAN_DATA_DIR/archive.json"
$VIBAN_BIN add "In-progress task" "desc" P2 feat >/dev/null 2>&1
jq --arg d "$old_date" '(.issues[0]) |= . + {status:"in_progress",updated_at:$d}' \
    "$VIBAN_JSON" > "$VIBAN_JSON.tmp" && mv "$VIBAN_JSON.tmp" "$VIBAN_JSON"
run_test
$VIBAN_BIN archive >/dev/null 2>&1
count=$(issue_count)
if [[ "$count" == "1" ]]; then
    pass "in_progress issue not archived"
else
    fail "should keep non-done issues" "1" "$count"
fi

# ============================================================
# Test 8: auto_archive runs on non-archive commands
# ============================================================
echo ""
echo "Test 8: auto_archive runs on list command"

reset_json
$VIBAN_BIN add "Old done for auto" "desc" P2 feat >/dev/null 2>&1
local very_old_date=$(date -u -v-60d +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || \
                      date -u -d "60 days ago" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null)
jq --arg d "$very_old_date" '(.issues[0]) |= . + {status:"done",updated_at:$d}' \
    "$VIBAN_JSON" > "$VIBAN_JSON.tmp" && mv "$VIBAN_JSON.tmp" "$VIBAN_JSON"
run_test
$VIBAN_BIN list >/dev/null 2>&1
count=$(issue_count)
if [[ "$count" == "0" ]]; then
    pass "auto_archive removed old done issue on list"
else
    fail "auto_archive should run on list" "0" "$count"
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
