#!/bin/zsh
# Test: cmd_comment for progress tracking

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

echo "Testing cmd_comment..."
echo ""

# ============================================================
# Test 1: Add a comment to an issue
# ============================================================
echo "Test 1: add comment"

reset_json
$VIBAN_BIN add "Test task" "desc" P2 feat >/dev/null 2>&1
run_test
output=$($VIBAN_BIN comment 1 "First note" 2>&1)
comment_count=$(jq -r '.issues[0].comments | length' "$VIBAN_JSON")
if [[ "$comment_count" == "1" ]]; then
    pass "comment count = $comment_count"
else
    fail "should have 1 comment" "1" "$comment_count"
fi

# ============================================================
# Test 2: Comment text is stored correctly
# ============================================================
echo ""
echo "Test 2: comment text stored"

run_test
comment_text=$(jq -r '.issues[0].comments[0].text' "$VIBAN_JSON")
if [[ "$comment_text" == "First note" ]]; then
    pass "text = '$comment_text'"
else
    fail "text should be 'First note'" "First note" "$comment_text"
fi

# ============================================================
# Test 3: Comment has timestamp
# ============================================================
echo ""
echo "Test 3: comment has timestamp"

run_test
comment_ts=$(jq -r '.issues[0].comments[0].created_at' "$VIBAN_JSON")
if [[ "$comment_ts" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]]; then
    pass "created_at = '$comment_ts'"
else
    fail "should have ISO timestamp" "YYYY-MM-DDT..." "$comment_ts"
fi

# ============================================================
# Test 4: Multiple comments append
# ============================================================
echo ""
echo "Test 4: multiple comments append"

run_test
$VIBAN_BIN comment 1 "Second note" >/dev/null 2>&1
$VIBAN_BIN comment 1 "Third note" >/dev/null 2>&1
comment_count=$(jq -r '.issues[0].comments | length' "$VIBAN_JSON")
if [[ "$comment_count" == "3" ]]; then
    pass "comment count = $comment_count"
else
    fail "should have 3 comments" "3" "$comment_count"
fi

# ============================================================
# Test 5: Comments visible in get output
# ============================================================
echo ""
echo "Test 5: comments visible in get"

run_test
get_output=$($VIBAN_BIN get 1 2>&1)
if [[ "$get_output" == *"First note"* && "$get_output" == *"Third note"* ]]; then
    pass "get shows comments"
else
    fail "get should show comments" "First note + Third note" "$get_output"
fi

# ============================================================
# Test 6: Missing args shows usage
# ============================================================
echo ""
echo "Test 6: missing args shows usage"

reset_json
run_test
output=$($VIBAN_BIN comment 2>&1)
if [[ "$output" == *"Usage:"* ]]; then
    pass "usage message shown"
else
    fail "should show usage" "Usage: viban comment <id> \"message\"" "$output"
fi

# ============================================================
# Test 7: Comment on nonexistent issue shows error
# ============================================================
echo ""
echo "Test 7: nonexistent issue shows error"

reset_json
run_test
output=$($VIBAN_BIN comment 999 "note" 2>&1)
if [[ "$output" == *"not found"* ]]; then
    pass "not found message shown"
else
    fail "should show not found" "not found" "$output"
fi

# ============================================================
# Test 8: Output message format
# ============================================================
echo ""
echo "Test 8: output message format"

reset_json
$VIBAN_BIN add "Test task" "desc" P2 feat >/dev/null 2>&1
run_test
output=$($VIBAN_BIN comment 1 "A note" 2>&1)
if [[ "$output" == *"comment #1 added"* ]]; then
    pass "output = '$output'"
else
    fail "should show comment number" "comment #1 added" "$output"
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
