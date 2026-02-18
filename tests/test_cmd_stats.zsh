#!/bin/zsh
# Test: cmd_stats throughput metrics

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

echo "Testing cmd_stats..."
echo ""

# ============================================================
# Test 1: Shows board summary
# ============================================================
echo "Test 1: board summary"

reset_json
$VIBAN_BIN add "Task A" "desc" P1 bug >/dev/null 2>&1
$VIBAN_BIN add "Task B" "desc" P0 feat >/dev/null 2>&1
$VIBAN_BIN add "Task C" "desc" P2 chore >/dev/null 2>&1
$VIBAN_BIN review 3 >/dev/null 2>&1
$VIBAN_BIN done 3 >/dev/null 2>&1
run_test
output=$($VIBAN_BIN stats 2>&1)
if [[ "$output" == *"Backlog: 2"* && "$output" == *"Done: 1"* && "$output" == *"Total: 3"* ]]; then
    pass "board summary correct"
else
    fail "should show correct counts" "Backlog: 2, Done: 1, Total: 3" "$output"
fi

# ============================================================
# Test 2: Shows P0/P1 open count
# ============================================================
echo ""
echo "Test 2: P0/P1 open count"

run_test
if [[ "$output" == *"Open P0: 1"* && "$output" == *"Open P1: 1"* ]]; then
    pass "P0/P1 counts correct"
else
    fail "should show P0: 1, P1: 1" "Open P0: 1  Open P1: 1" "$output"
fi

# ============================================================
# Test 3: Shows this week stats
# ============================================================
echo ""
echo "Test 3: this week stats"

run_test
if [[ "$output" == *"Added: 3"* && "$output" == *"Completed: 1"* ]]; then
    pass "weekly stats correct"
else
    fail "should show Added: 3, Completed: 1" "Added: 3  Completed: 1" "$output"
fi

# ============================================================
# Test 4: Shows cycle time
# ============================================================
echo ""
echo "Test 4: cycle time"

run_test
if [[ "$output" == *"Average:"* ]]; then
    pass "cycle time shown"
else
    fail "should show average" "Average:" "$output"
fi

# ============================================================
# Test 5: Shows oldest open issue
# ============================================================
echo ""
echo "Test 5: oldest open issue"

run_test
if [[ "$output" == *"Oldest Open Issue"* && "$output" == *"Task A"* ]]; then
    pass "oldest open issue shown"
else
    fail "should show oldest" "Task A" "$output"
fi

# ============================================================
# Test 6: Empty board stats
# ============================================================
echo ""
echo "Test 6: empty board"

reset_json
run_test
output=$($VIBAN_BIN stats 2>&1)
if [[ "$output" == *"Total: 0"* && "$output" == *"no completed issues"* ]]; then
    pass "empty board handled"
else
    fail "should handle empty" "Total: 0, no completed" "$output"
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
