#!/bin/zsh
# Test: cmd_move backward and forward status transitions

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

echo "Testing cmd_move..."
echo ""

# ============================================================
# Test 1: move review → in_progress (backward transition)
# ============================================================
echo "Test 1: move review → in_progress"

reset_json
$VIBAN_BIN add "Test task" "desc" P2 feat >/dev/null 2>&1
jq '(.issues[0]) |= . + {status:"review"}' "$VIBAN_JSON" > "$VIBAN_JSON.tmp" && mv "$VIBAN_JSON.tmp" "$VIBAN_JSON"
run_test
$VIBAN_BIN move 1 in_progress >/dev/null 2>&1
card_status=$(get_issue_field 1 "status")
if [[ "$card_status" == "in_progress" ]]; then
    pass "status = '$card_status'"
else
    fail "should be in_progress" "in_progress" "$card_status"
fi

# ============================================================
# Test 2: move in_progress → backlog (backward transition)
# ============================================================
echo ""
echo "Test 2: move in_progress → backlog"

reset_json
$VIBAN_BIN add "Test task" "desc" P2 feat >/dev/null 2>&1
jq '(.issues[0]) |= . + {status:"in_progress"}' "$VIBAN_JSON" > "$VIBAN_JSON.tmp" && mv "$VIBAN_JSON.tmp" "$VIBAN_JSON"
run_test
$VIBAN_BIN move 1 backlog >/dev/null 2>&1
card_status=$(get_issue_field 1 "status")
if [[ "$card_status" == "backlog" ]]; then
    pass "status = '$card_status'"
else
    fail "should be backlog" "backlog" "$card_status"
fi

# ============================================================
# Test 3: move backlog → review (skip forward)
# ============================================================
echo ""
echo "Test 3: move backlog → review (skip forward)"

reset_json
$VIBAN_BIN add "Test task" "desc" P2 feat >/dev/null 2>&1
run_test
$VIBAN_BIN move 1 review >/dev/null 2>&1
card_status=$(get_issue_field 1 "status")
if [[ "$card_status" == "review" ]]; then
    pass "status = '$card_status'"
else
    fail "should be review" "review" "$card_status"
fi

# ============================================================
# Test 4: move to done
# ============================================================
echo ""
echo "Test 4: move to done"

reset_json
$VIBAN_BIN add "Test task" "desc" P2 feat >/dev/null 2>&1
run_test
$VIBAN_BIN move 1 done --force >/dev/null 2>&1
card_status=$(get_issue_field 1 "status")
if [[ "$card_status" == "done" ]]; then
    pass "status = '$card_status'"
else
    fail "should be done" "done" "$card_status"
fi

# ============================================================
# Test 5: invalid status shows error
# ============================================================
echo ""
echo "Test 5: invalid status shows error"

reset_json
$VIBAN_BIN add "Test task" "desc" P2 feat >/dev/null 2>&1
run_test
output=$($VIBAN_BIN move 1 invalid 2>&1)
if [[ "$output" == *"Invalid status"* ]]; then
    pass "error message shown"
else
    fail "should show invalid status error" "Invalid status" "$output"
fi

# ============================================================
# Test 6: missing args shows usage
# ============================================================
echo ""
echo "Test 6: missing args shows usage"

reset_json
run_test
output=$($VIBAN_BIN move 2>&1)
if [[ "$output" == *"Usage:"* ]]; then
    pass "usage message shown"
else
    fail "should show usage" "Usage: viban move <id> <status>" "$output"
fi

# ============================================================
# Test 7: move same status is no-op
# ============================================================
echo ""
echo "Test 7: move to same status is no-op"

reset_json
$VIBAN_BIN add "Test task" "desc" P2 feat >/dev/null 2>&1
run_test
output=$($VIBAN_BIN move 1 backlog 2>&1)
if [[ "$output" == *"already"* ]]; then
    pass "already message shown"
else
    fail "should say already in status" "already" "$output"
fi

# ============================================================
# Test 8: move nonexistent issue shows error
# ============================================================
echo ""
echo "Test 8: nonexistent issue shows error"

reset_json
run_test
output=$($VIBAN_BIN move 999 review 2>&1)
if [[ "$output" == *"not found"* ]]; then
    pass "not found message shown"
else
    fail "should show not found" "not found" "$output"
fi

# ============================================================
# Test 9: move to done blocked when status is not review
# ============================================================
echo ""
echo "Test 9: move to done blocked when not in review"

reset_json
$VIBAN_BIN add "Test task" "desc" P2 feat >/dev/null 2>&1
jq '(.issues[0]) |= . + {status:"in_progress"}' "$VIBAN_JSON" > "$VIBAN_JSON.tmp" && mv "$VIBAN_JSON.tmp" "$VIBAN_JSON"
run_test
output=$($VIBAN_BIN move 1 done 2>&1)
card_status=$(get_issue_field 1 "status")
if [[ "$card_status" == "in_progress" ]]; then
    pass "status unchanged: '$card_status'"
else
    fail "should stay in_progress" "in_progress" "$card_status"
fi

run_test
if [[ "$output" == *"not 'review'"* ]]; then
    pass "review guard error shown"
else
    fail "should show review guard error" "not 'review'" "$output"
fi

# ============================================================
# Test 10: move to done --force bypasses review guard
# ============================================================
echo ""
echo "Test 10: move to done --force bypasses guard"

reset_json
$VIBAN_BIN add "Test task" "desc" P2 feat >/dev/null 2>&1
jq '(.issues[0]) |= . + {status:"in_progress"}' "$VIBAN_JSON" > "$VIBAN_JSON.tmp" && mv "$VIBAN_JSON.tmp" "$VIBAN_JSON"
run_test
$VIBAN_BIN move 1 done --force >/dev/null 2>&1
card_status=$(get_issue_field 1 "status")
if [[ "$card_status" == "done" ]]; then
    pass "force bypassed guard, status = '$card_status'"
else
    fail "force should move to done" "done" "$card_status"
fi

# ============================================================
# Test 11: move to done from review succeeds without --force
# ============================================================
echo ""
echo "Test 11: move to done from review succeeds"

reset_json
$VIBAN_BIN add "Test task" "desc" P2 feat >/dev/null 2>&1
jq '(.issues[0]) |= . + {status:"review"}' "$VIBAN_JSON" > "$VIBAN_JSON.tmp" && mv "$VIBAN_JSON.tmp" "$VIBAN_JSON"
run_test
$VIBAN_BIN move 1 done >/dev/null 2>&1
card_status=$(get_issue_field 1 "status")
if [[ "$card_status" == "done" ]]; then
    pass "review → done works without --force"
else
    fail "should move to done" "done" "$card_status"
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
