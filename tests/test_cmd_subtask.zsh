#!/bin/zsh
# Test: sub-task support via --parent flag

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

echo "Testing sub-task support..."
echo ""

# ============================================================
# Test 1: Add sub-task with --parent
# ============================================================
echo "Test 1: add sub-task with --parent"

reset_json
$VIBAN_BIN add "Parent task" "parent desc" P1 feat >/dev/null 2>&1
run_test
$VIBAN_BIN add "Sub-task A" "child desc" P2 feat --parent 1 >/dev/null 2>&1
parent_id=$(get_issue_field 2 "parent_id")
if [[ "$parent_id" == "1" ]]; then
    pass "parent_id = $parent_id"
else
    fail "should have parent_id 1" "1" "$parent_id"
fi

# ============================================================
# Test 2: Issue without --parent has null parent_id
# ============================================================
echo ""
echo "Test 2: no --parent gives null"

run_test
parent_id=$(get_issue_field 1 "parent_id")
if [[ "$parent_id" == "null" ]]; then
    pass "parent_id = null"
else
    fail "should be null" "null" "$parent_id"
fi

# ============================================================
# Test 3: get shows sub-tasks
# ============================================================
echo ""
echo "Test 3: get shows sub-tasks"

reset_json
$VIBAN_BIN add "Parent" "desc" P1 feat >/dev/null 2>&1
$VIBAN_BIN add "Child A" "desc" P2 feat --parent 1 >/dev/null 2>&1
$VIBAN_BIN add "Child B" "desc" P2 feat --parent 1 >/dev/null 2>&1
run_test
output=$($VIBAN_BIN get 1 2>&1)
if [[ "$output" == *"Sub-tasks: 0/2 done"* ]]; then
    pass "sub-task summary shown"
else
    fail "should show sub-task count" "Sub-tasks: 0/2 done" "$output"
fi

# ============================================================
# Test 4: get shows completion percentage
# ============================================================
echo ""
echo "Test 4: completion percentage updates"

$VIBAN_BIN review 2 >/dev/null 2>&1
$VIBAN_BIN done 2 >/dev/null 2>&1
run_test
output=$($VIBAN_BIN get 1 2>&1)
if [[ "$output" == *"Sub-tasks: 1/2 done (50%)"* ]]; then
    pass "completion = 50%"
else
    fail "should show 50%" "Sub-tasks: 1/2 done (50%)" "$output"
fi

# ============================================================
# Test 5: get lists individual sub-tasks
# ============================================================
echo ""
echo "Test 5: get lists sub-tasks"

run_test
output=$($VIBAN_BIN get 1 2>&1)
if [[ "$output" == *"Child A"* && "$output" == *"Child B"* ]]; then
    pass "both children listed"
else
    fail "should list children" "Child A + Child B" "$output"
fi

# ============================================================
# Test 6: Invalid parent shows error
# ============================================================
echo ""
echo "Test 6: invalid parent shows error"

reset_json
run_test
output=$($VIBAN_BIN add "Orphan" "desc" P2 feat --parent 999 2>&1)
if [[ "$output" == *"not found"* ]]; then
    pass "parent not found error"
else
    fail "should show not found" "not found" "$output"
fi

# ============================================================
# Test 7: Output shows parent info
# ============================================================
echo ""
echo "Test 7: output shows parent info"

reset_json
$VIBAN_BIN add "Parent" "desc" P1 feat >/dev/null 2>&1
run_test
output=$($VIBAN_BIN add "Child" "desc" P2 feat --parent 1 2>&1)
if [[ "$output" == *"child of #1"* ]]; then
    pass "parent info in output"
else
    fail "should show parent" "child of #1" "$output"
fi

# ============================================================
# Test 8: Issue without sub-tasks shows no sub-task section
# ============================================================
echo ""
echo "Test 8: no sub-tasks = no section"

reset_json
$VIBAN_BIN add "Solo task" "desc" P1 feat >/dev/null 2>&1
run_test
output=$($VIBAN_BIN get 1 2>&1)
if [[ "$output" != *"Sub-tasks"* ]]; then
    pass "no sub-task section"
else
    fail "should not show sub-task section" "no Sub-tasks" "$output"
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
