#!/bin/zsh
# Test: cmd_done non-destructive behavior and --remove flag

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

echo "Testing cmd_done..."
echo ""

# ============================================================
# Test 1: viban done moves card to "done" status
# ============================================================
echo "Test 1: done sets status to 'done'"

reset_json
$VIBAN_BIN add "Test task" "desc" P2 feat >/dev/null 2>&1
$VIBAN_BIN review 1 >/dev/null 2>&1
run_test
$VIBAN_BIN done 1 >/dev/null 2>&1
card_status=$(get_issue_field 1 "status")
if [[ "$card_status" == "done" ]]; then
    pass "status = '$card_status'"
else
    fail "status should be 'done'" "done" "$card_status"
fi

# ============================================================
# Test 2: viban done clears assigned_to
# ============================================================
echo ""
echo "Test 2: done clears assigned_to"

reset_json
$VIBAN_BIN add "Test task" "desc" P2 feat >/dev/null 2>&1
# Set assigned_to and move to review
jq '(.issues[0]) |= . + {assigned_to:"agent-1",status:"review"}' \
    "$VIBAN_JSON" > "$VIBAN_JSON.tmp" && mv "$VIBAN_JSON.tmp" "$VIBAN_JSON"
run_test
$VIBAN_BIN done 1 >/dev/null 2>&1
assigned=$(get_issue_field 1 "assigned_to")
if [[ "$assigned" == "null" ]]; then
    pass "assigned_to = null"
else
    fail "assigned_to should be null" "null" "$assigned"
fi

# ============================================================
# Test 3: viban done --remove deletes the card
# ============================================================
echo ""
echo "Test 3: done --remove deletes card"

reset_json
$VIBAN_BIN add "Test task" "desc" P2 feat >/dev/null 2>&1
$VIBAN_BIN review 1 >/dev/null 2>&1
run_test
$VIBAN_BIN done 1 --remove >/dev/null 2>&1
count=$(issue_count)
if [[ "$count" == "0" ]]; then
    pass "card deleted, count = $count"
else
    fail "card should be deleted" "0" "$count"
fi

# ============================================================
# Test 4: viban done with no ID shows usage error
# ============================================================
echo ""
echo "Test 4: no ID shows usage error"

reset_json
run_test
output=$($VIBAN_BIN done 2>&1)
if [[ "$output" == *"Usage:"* ]]; then
    pass "usage message shown"
else
    fail "should show usage" "Usage: viban done <id> [--remove]" "$output"
fi

# ============================================================
# Test 5: Card count unchanged after done (without --remove)
# ============================================================
echo ""
echo "Test 5: card count unchanged after done"

reset_json
$VIBAN_BIN add "Task A" "desc" P2 feat >/dev/null 2>&1
$VIBAN_BIN add "Task B" "desc" P1 bug >/dev/null 2>&1
$VIBAN_BIN review 1 >/dev/null 2>&1
run_test
$VIBAN_BIN done 1 >/dev/null 2>&1
count=$(issue_count)
if [[ "$count" == "2" ]]; then
    pass "count still 2 after done"
else
    fail "count should remain 2" "2" "$count"
fi

# ============================================================
# Test 6: Card count decremented after done --remove
# ============================================================
echo ""
echo "Test 6: card count decremented after done --remove"

reset_json
$VIBAN_BIN add "Task A" "desc" P2 feat >/dev/null 2>&1
$VIBAN_BIN add "Task B" "desc" P1 bug >/dev/null 2>&1
$VIBAN_BIN review 1 >/dev/null 2>&1
run_test
$VIBAN_BIN done 1 --remove >/dev/null 2>&1
count=$(issue_count)
if [[ "$count" == "1" ]]; then
    pass "count = 1 after --remove"
else
    fail "count should be 1" "1" "$count"
fi

# ============================================================
# Test 7: done rejects non-review issues
# ============================================================
echo ""
echo "Test 7: done rejects non-review status"

reset_json
$VIBAN_BIN add "Task A" "desc" P2 feat >/dev/null 2>&1
run_test
output=$($VIBAN_BIN done 1 2>&1)
if [[ "$output" == *"not 'review'"* ]]; then
    pass "rejects backlog issue"
else
    fail "should reject non-review" "not 'review'" "$output"
fi

# ============================================================
# Test 8: done --force bypasses review guard
# ============================================================
echo ""
echo "Test 8: done --force bypasses guard"

reset_json
$VIBAN_BIN add "Task A" "desc" P2 feat >/dev/null 2>&1
run_test
$VIBAN_BIN done 1 --force >/dev/null 2>&1
card_status=$(get_issue_field 1 "status")
if [[ "$card_status" == "done" ]]; then
    pass "force bypassed guard, status = '$card_status'"
else
    fail "force should work" "done" "$card_status"
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
