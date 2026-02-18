#!/bin/zsh
# Test: cmd_link/cmd_unlink issue dependencies

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

echo "Testing cmd_link/cmd_unlink..."
echo ""

# ============================================================
# Test 1: link adds blocked_by
# ============================================================
echo "Test 1: link adds blocked_by"

reset_json
$VIBAN_BIN add "Task A" "desc" P1 feat >/dev/null 2>&1
$VIBAN_BIN add "Task B" "desc" P2 feat >/dev/null 2>&1
run_test
$VIBAN_BIN link 1 blocks 2 >/dev/null 2>&1
blocked_by=$(jq -r '.issues[1].blocked_by // [] | length' "$VIBAN_JSON")
if [[ "$blocked_by" == "1" ]]; then
    pass "issue 2 has 1 blocker"
else
    fail "issue 2 should have 1 blocker" "1" "$blocked_by"
fi

# ============================================================
# Test 2: blocked_by contains correct ID
# ============================================================
echo ""
echo "Test 2: blocked_by contains correct ID"

run_test
blocker_id=$(jq -r '.issues[1].blocked_by[0]' "$VIBAN_JSON")
if [[ "$blocker_id" == "1" ]]; then
    pass "blocker id = $blocker_id"
else
    fail "blocker should be 1" "1" "$blocker_id"
fi

# ============================================================
# Test 3: assign skips blocked issues
# ============================================================
echo ""
echo "Test 3: assign skips blocked issues"

reset_json
$VIBAN_BIN add "Task A" "desc" P1 feat >/dev/null 2>&1
$VIBAN_BIN add "Task B" "desc" P0 feat >/dev/null 2>&1
# B is higher priority but blocked by A
$VIBAN_BIN link 1 blocks 2 >/dev/null 2>&1
run_test
assign_output=$($VIBAN_BIN assign 2>&1 | tail -1 | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' | tr -d '[:space:]')
# Should assign A (id=1) not B (id=2) because B is blocked
assigned_status=$(get_issue_field 1 "status")
if [[ "$assigned_status" == "in_progress" ]]; then
    pass "assigned unblocked issue 1 (not blocked issue 2)"
else
    fail "should assign issue 1" "in_progress" "$assigned_status"
fi

# ============================================================
# Test 4: unlink removes blocked_by
# ============================================================
echo ""
echo "Test 4: unlink removes blocked_by"

reset_json
$VIBAN_BIN add "Task A" "desc" P1 feat >/dev/null 2>&1
$VIBAN_BIN add "Task B" "desc" P2 feat >/dev/null 2>&1
$VIBAN_BIN link 1 blocks 2 >/dev/null 2>&1
run_test
$VIBAN_BIN unlink 1 blocks 2 >/dev/null 2>&1
blocked_by=$(jq -r '.issues[1].blocked_by // [] | length' "$VIBAN_JSON")
if [[ "$blocked_by" == "0" ]]; then
    pass "blocked_by cleared"
else
    fail "blocked_by should be empty" "0" "$blocked_by"
fi

# ============================================================
# Test 5: duplicate link is idempotent
# ============================================================
echo ""
echo "Test 5: duplicate link is idempotent"

reset_json
$VIBAN_BIN add "Task A" "desc" P1 feat >/dev/null 2>&1
$VIBAN_BIN add "Task B" "desc" P2 feat >/dev/null 2>&1
$VIBAN_BIN link 1 blocks 2 >/dev/null 2>&1
$VIBAN_BIN link 1 blocks 2 >/dev/null 2>&1
run_test
blocked_by=$(jq -r '.issues[1].blocked_by | length' "$VIBAN_JSON")
if [[ "$blocked_by" == "1" ]]; then
    pass "still 1 blocker after duplicate link"
else
    fail "should have exactly 1 blocker" "1" "$blocked_by"
fi

# ============================================================
# Test 6: self-block shows error
# ============================================================
echo ""
echo "Test 6: self-block shows error"

reset_json
$VIBAN_BIN add "Task A" "desc" P1 feat >/dev/null 2>&1
run_test
output=$($VIBAN_BIN link 1 blocks 1 2>&1)
if [[ "$output" == *"Cannot block self"* ]]; then
    pass "self-block rejected"
else
    fail "should reject self-block" "Cannot block self" "$output"
fi

# ============================================================
# Test 7: link nonexistent issue shows error
# ============================================================
echo ""
echo "Test 7: nonexistent issue shows error"

reset_json
$VIBAN_BIN add "Task A" "desc" P1 feat >/dev/null 2>&1
run_test
output=$($VIBAN_BIN link 1 blocks 999 2>&1)
if [[ "$output" == *"not found"* ]]; then
    pass "not found error shown"
else
    fail "should show not found" "not found" "$output"
fi

# ============================================================
# Test 8: missing args shows usage
# ============================================================
echo ""
echo "Test 8: missing args shows usage"

run_test
output=$($VIBAN_BIN link 2>&1)
if [[ "$output" == *"Usage:"* ]]; then
    pass "usage message shown"
else
    fail "should show usage" "Usage:" "$output"
fi

# ============================================================
# Test 9: blocked issue assignable after blocker is done
# ============================================================
echo ""
echo "Test 9: blocked issue assignable after blocker done"

reset_json
$VIBAN_BIN add "Task A" "desc" P1 feat >/dev/null 2>&1
$VIBAN_BIN add "Task B" "desc" P0 feat >/dev/null 2>&1
$VIBAN_BIN link 1 blocks 2 >/dev/null 2>&1
$VIBAN_BIN review 1 >/dev/null 2>&1
$VIBAN_BIN done 1 >/dev/null 2>&1
run_test
$VIBAN_BIN assign >/dev/null 2>&1
assigned_status=$(get_issue_field 2 "status")
if [[ "$assigned_status" == "in_progress" ]]; then
    pass "issue 2 assignable after blocker done"
else
    fail "should assign issue 2" "in_progress" "$assigned_status"
fi

# ============================================================
# Test 10: get shows blocked_by in output
# ============================================================
echo ""
echo "Test 10: get shows blocked_by"

reset_json
$VIBAN_BIN add "Task A" "desc" P1 feat >/dev/null 2>&1
$VIBAN_BIN add "Task B" "desc" P2 feat >/dev/null 2>&1
$VIBAN_BIN link 1 blocks 2 >/dev/null 2>&1
run_test
get_output=$($VIBAN_BIN get 2 2>&1)
if [[ "$get_output" == *"blocked_by"* ]]; then
    pass "get shows blocked_by field"
else
    fail "should show blocked_by" "blocked_by" "$get_output"
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
