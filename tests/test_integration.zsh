#!/bin/zsh
# Test: Integration tests for feature combinations

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

echo "Testing feature integrations..."
echo ""

# ============================================================
# Test 1: Blocked issue with sub-tasks
# ============================================================
echo "Test 1: blocked issue with sub-tasks"

reset_json
$VIBAN_BIN add "Parent task" "desc" P1 feat >/dev/null 2>&1
$VIBAN_BIN add "Blocker task" "desc" P0 feat >/dev/null 2>&1
$VIBAN_BIN add "Child of parent" "desc" P2 feat --parent 1 >/dev/null 2>&1
$VIBAN_BIN link 2 blocks 1 >/dev/null 2>&1
run_test
# Parent should be blocked AND have sub-tasks
local parent_blocked=$(jq '[.issues[]|select(.id==1)|.blocked_by//[]|length]|.[0]' "$VIBAN_JSON")
local child_count=$(jq '[.issues[]|select(.parent_id==1)]|length' "$VIBAN_JSON")
if [[ "$parent_blocked" -gt 0 && "$child_count" -eq 1 ]]; then
    pass "blocked parent has sub-tasks"
else
    fail "should have blocker and child" "blocked=1, children=1" "blocked=$parent_blocked, children=$child_count"
fi

# ============================================================
# Test 2: Comment on done issue
# ============================================================
echo ""
echo "Test 2: comment on done issue"

reset_json
$VIBAN_BIN add "Task A" "desc" P1 bug >/dev/null 2>&1
$VIBAN_BIN review 1 >/dev/null 2>&1
$VIBAN_BIN done 1 >/dev/null 2>&1
run_test
output=$($VIBAN_BIN comment 1 "Post-mortem note" 2>&1)
local comment_count=$(jq '.issues[0].comments|length' "$VIBAN_JSON")
if [[ "$comment_count" -eq 1 ]]; then
    pass "can comment on done issue"
else
    fail "should allow comment on done" "1" "$comment_count"
fi

# ============================================================
# Test 3: Move blocked issue shows it still blocked
# ============================================================
echo ""
echo "Test 3: assign skips blocked even after move"

reset_json
$VIBAN_BIN add "Blocker" "desc" P0 feat >/dev/null 2>&1
$VIBAN_BIN add "Blocked" "desc" P1 feat >/dev/null 2>&1
$VIBAN_BIN link 1 blocks 2 >/dev/null 2>&1
$VIBAN_BIN move 2 in_progress >/dev/null 2>&1
$VIBAN_BIN move 2 backlog >/dev/null 2>&1
run_test
output=$($VIBAN_BIN assign 2>&1)
if [[ "$output" == *"#1"* ]]; then
    pass "assign picks unblocked issue"
else
    fail "should assign #1 (unblocked)" "#1" "$output"
fi

# ============================================================
# Test 4: Duplicate detection ignores sub-tasks of done parents
# ============================================================
echo ""
echo "Test 4: duplicate detection with done issues"

reset_json
$VIBAN_BIN add "Fix login bug" "desc" P1 bug >/dev/null 2>&1
$VIBAN_BIN review 1 >/dev/null 2>&1
$VIBAN_BIN done 1 >/dev/null 2>&1
run_test
output=$($VIBAN_BIN add "Fix login bug" "desc" P1 bug 2>&1)
if [[ "$output" != *"duplicate"* && "$output" != *"Potential"* ]]; then
    pass "no duplicate warning for done issues"
else
    fail "should ignore done issues" "no warning" "$output"
fi

# ============================================================
# Test 5: Stats reflect blocked issues correctly
# ============================================================
echo ""
echo "Test 5: stats with mixed states"

reset_json
$VIBAN_BIN add "Task A" "desc" P0 bug >/dev/null 2>&1
$VIBAN_BIN add "Task B" "desc" P1 feat >/dev/null 2>&1
$VIBAN_BIN add "Task C" "desc" P2 chore >/dev/null 2>&1
$VIBAN_BIN link 1 blocks 2 >/dev/null 2>&1
$VIBAN_BIN review 3 >/dev/null 2>&1
$VIBAN_BIN done 3 >/dev/null 2>&1
$VIBAN_BIN comment 1 "Working on it" >/dev/null 2>&1
run_test
output=$($VIBAN_BIN stats 2>&1)
if [[ "$output" == *"Total: 3"* && "$output" == *"Open P0: 1"* && "$output" == *"Completed: 1"* ]]; then
    pass "stats correct with mixed features"
else
    fail "should show correct stats" "Total: 3, P0: 1, Completed: 1" "$output"
fi

# ============================================================
# Test 6: History shows done sub-tasks
# ============================================================
echo ""
echo "Test 6: history includes done sub-tasks"

reset_json
$VIBAN_BIN add "Parent" "desc" P1 feat >/dev/null 2>&1
$VIBAN_BIN add "Child" "desc" P2 feat --parent 1 >/dev/null 2>&1
$VIBAN_BIN review 2 >/dev/null 2>&1
$VIBAN_BIN done 2 >/dev/null 2>&1
run_test
output=$($VIBAN_BIN history 2>&1)
if [[ "$output" == *"Child"* ]]; then
    pass "history shows done sub-task"
else
    fail "should show child in history" "Child" "$output"
fi

# ============================================================
# Test 7: Unlink then assign works
# ============================================================
echo ""
echo "Test 7: unlink makes issue assignable"

reset_json
$VIBAN_BIN add "Blocker" "desc" P1 feat >/dev/null 2>&1
$VIBAN_BIN add "Was blocked" "desc" P0 feat >/dev/null 2>&1
$VIBAN_BIN link 1 blocks 2 >/dev/null 2>&1
$VIBAN_BIN unlink 1 blocks 2 >/dev/null 2>&1
run_test
output=$($VIBAN_BIN assign 2>&1)
if [[ "$output" == *"#2"* ]]; then
    pass "unlinked issue is assignable (P0 first)"
else
    fail "should assign #2 (P0, unblocked)" "#2" "$output"
fi

# ============================================================
# Test 8: Move to done + history + stats consistency
# ============================================================
echo ""
echo "Test 8: move to done updates history and stats"

reset_json
$VIBAN_BIN add "Task X" "desc" P1 feat >/dev/null 2>&1
$VIBAN_BIN move 1 done --force >/dev/null 2>&1
run_test
local hist=$($VIBAN_BIN history 2>&1)
local stats=$($VIBAN_BIN stats 2>&1)
if [[ "$hist" == *"Task X"* && "$stats" == *"Done: 1"* ]]; then
    pass "move to done reflected in history and stats"
else
    fail "should show in both" "history+stats" "hist=$hist stats=$stats"
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
