#!/bin/zsh
# Test: duplicate detection in cmd_add

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

echo "Testing duplicate detection in cmd_add..."
echo ""

# ============================================================
# Test 1: Warns on exact title duplicate
# ============================================================
echo "Test 1: warns on exact duplicate"

reset_json
$VIBAN_BIN add "Login fails after reset" "desc" P1 bug >/dev/null 2>&1
run_test
output=$($VIBAN_BIN add "Login fails after reset" "different desc" P2 bug 2>&1)
if [[ "$output" == *"Potential duplicate"* ]]; then
    pass "duplicate warning shown"
else
    fail "should warn on exact duplicate" "Potential duplicate" "$output"
fi

# ============================================================
# Test 2: Warns on similar title (high word overlap)
# ============================================================
echo ""
echo "Test 2: warns on similar title"

reset_json
$VIBAN_BIN add "Login fails after password reset" "desc" P1 bug >/dev/null 2>&1
run_test
output=$($VIBAN_BIN add "Login fails after reset" "desc" P2 bug 2>&1)
if [[ "$output" == *"Potential duplicate"* ]]; then
    pass "similar title warning shown"
else
    fail "should warn on similar title" "Potential duplicate" "$output"
fi

# ============================================================
# Test 3: No warning on different title
# ============================================================
echo ""
echo "Test 3: no warning on different title"

reset_json
$VIBAN_BIN add "Login fails after reset" "desc" P1 bug >/dev/null 2>&1
run_test
output=$($VIBAN_BIN add "Dashboard chart rendering broken" "desc" P2 bug 2>&1)
if [[ "$output" != *"Potential duplicate"* ]]; then
    pass "no false positive"
else
    fail "should not warn on different title" "no warning" "$output"
fi

# ============================================================
# Test 4: Still creates the issue despite warning
# ============================================================
echo ""
echo "Test 4: issue created despite warning"

reset_json
$VIBAN_BIN add "Login fails" "desc" P1 bug >/dev/null 2>&1
run_test
$VIBAN_BIN add "Login fails" "other desc" P2 bug >/dev/null 2>&1
count=$(jq '.issues | length' "$VIBAN_JSON")
if [[ "$count" == "2" ]]; then
    pass "both issues created (count=$count)"
else
    fail "should create both issues" "2" "$count"
fi

# ============================================================
# Test 5: Ignores done issues
# ============================================================
echo ""
echo "Test 5: ignores done issues"

reset_json
$VIBAN_BIN add "Login fails after reset" "desc" P1 bug >/dev/null 2>&1
$VIBAN_BIN review 1 >/dev/null 2>&1
$VIBAN_BIN done 1 >/dev/null 2>&1
run_test
output=$($VIBAN_BIN add "Login fails after reset" "desc" P2 bug 2>&1)
if [[ "$output" != *"Potential duplicate"* ]]; then
    pass "done issues ignored"
else
    fail "should not warn on done issues" "no warning" "$output"
fi

# ============================================================
# Test 6: Shows duplicate ID in warning
# ============================================================
echo ""
echo "Test 6: shows duplicate ID"

reset_json
$VIBAN_BIN add "API timeout on dashboard" "desc" P1 bug >/dev/null 2>&1
run_test
output=$($VIBAN_BIN add "API timeout on dashboard load" "desc" P2 bug 2>&1)
if [[ "$output" == *"#1"* ]]; then
    pass "shows issue ID in warning"
else
    fail "should show issue ID" "#1" "$output"
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
