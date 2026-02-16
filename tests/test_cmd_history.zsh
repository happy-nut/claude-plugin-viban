#!/bin/zsh
# Test: cmd_history and archive behavior

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

echo "Testing cmd_history and archive..."
echo ""

# ============================================================
# Test 1: done without --purge archives (keeps in JSON)
# ============================================================
echo "Test 1: done archives issue"

reset_json
$VIBAN_BIN add "Task A" "desc" P2 feat >/dev/null 2>&1
run_test
$VIBAN_BIN done 1 >/dev/null 2>&1
count=$(issue_count)
card_status=$(get_issue_field 1 "status")
if [[ "$count" == "1" && "$card_status" == "done" ]]; then
    pass "issue archived (count=$count, status=$card_status)"
else
    fail "should archive" "count=1 status=done" "count=$count status=$card_status"
fi

# ============================================================
# Test 2: done --purge permanently deletes
# ============================================================
echo ""
echo "Test 2: done --purge deletes"

reset_json
$VIBAN_BIN add "Task A" "desc" P2 feat >/dev/null 2>&1
run_test
$VIBAN_BIN done 1 --purge >/dev/null 2>&1
count=$(issue_count)
if [[ "$count" == "0" ]]; then
    pass "issue purged (count=$count)"
else
    fail "should delete" "0" "$count"
fi

# ============================================================
# Test 3: done --remove still works (backward compat)
# ============================================================
echo ""
echo "Test 3: done --remove backward compat"

reset_json
$VIBAN_BIN add "Task A" "desc" P2 feat >/dev/null 2>&1
run_test
$VIBAN_BIN done 1 --remove >/dev/null 2>&1
count=$(issue_count)
if [[ "$count" == "0" ]]; then
    pass "issue removed (count=$count)"
else
    fail "should delete" "0" "$count"
fi

# ============================================================
# Test 4: history shows done issues
# ============================================================
echo ""
echo "Test 4: history shows done issues"

reset_json
$VIBAN_BIN add "Completed task" "desc" P1 bug >/dev/null 2>&1
$VIBAN_BIN add "Active task" "desc" P2 feat >/dev/null 2>&1
$VIBAN_BIN done 1 >/dev/null 2>&1
run_test
output=$($VIBAN_BIN history 2>&1)
if [[ "$output" == *"Completed task"* && "$output" != *"Active task"* ]]; then
    pass "history shows only done issues"
else
    fail "should show only done" "Completed task" "$output"
fi

# ============================================================
# Test 5: history shows date
# ============================================================
echo ""
echo "Test 5: history shows completion date"

run_test
output=$($VIBAN_BIN history 2>&1)
if [[ "$output" =~ [0-9]{4}-[0-9]{2}-[0-9]{2} ]]; then
    pass "date shown in history"
else
    fail "should show date" "YYYY-MM-DD" "$output"
fi

# ============================================================
# Test 6: history empty when no done issues
# ============================================================
echo ""
echo "Test 6: history empty"

reset_json
$VIBAN_BIN add "Active task" "desc" P2 feat >/dev/null 2>&1
run_test
output=$($VIBAN_BIN history 2>&1)
if [[ "$output" == *"Done (0)"* ]]; then
    pass "empty history shows count 0"
else
    fail "should show 0" "Done (0)" "$output"
fi

# ============================================================
# Test 7: list --status filters by status
# ============================================================
echo ""
echo "Test 7: list --status filter"

reset_json
$VIBAN_BIN add "Backlog task" "desc" P2 feat >/dev/null 2>&1
$VIBAN_BIN add "Done task" "desc" P1 bug >/dev/null 2>&1
$VIBAN_BIN done 2 >/dev/null 2>&1
run_test
output=$($VIBAN_BIN list --status done 2>&1)
if [[ "$output" == *"Done task"* && "$output" != *"Backlog task"* ]]; then
    pass "list --status done shows only done"
else
    fail "should filter to done only" "Done task" "$output"
fi

# ============================================================
# Test 8: list --status backlog works
# ============================================================
echo ""
echo "Test 8: list --status backlog"

run_test
output=$($VIBAN_BIN list --status backlog 2>&1)
if [[ "$output" == *"Backlog task"* && "$output" != *"Done task"* ]]; then
    pass "list --status backlog shows only backlog"
else
    fail "should filter to backlog only" "Backlog task" "$output"
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
