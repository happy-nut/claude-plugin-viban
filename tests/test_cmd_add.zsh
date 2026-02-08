#!/bin/zsh
# Test: cmd_add argument parsing (positional and named args)

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

echo "Testing cmd_add argument parsing..."
echo ""

# ============================================================
# Test 1: Positional args
# ============================================================
echo "Test 1: Positional arguments"

reset_json
run_test
$VIBAN_BIN add "My title" "My description" P1 bug >/dev/null 2>&1
title=$(get_issue_field 1 "title")
if [[ "$title" == "My title" ]]; then
    pass "positional: title = '$title'"
else
    fail "positional title" "My title" "$title"
fi

run_test
desc=$(get_issue_field 1 "description")
if [[ "$desc" == "My description" ]]; then
    pass "positional: description = '$desc'"
else
    fail "positional description" "My description" "$desc"
fi

run_test
priority=$(get_issue_field 1 "priority")
if [[ "$priority" == "P1" ]]; then
    pass "positional: priority = $priority"
else
    fail "positional priority" "P1" "$priority"
fi

run_test
issue_type=$(get_issue_field 1 "type")
if [[ "$issue_type" == "bug" ]]; then
    pass "positional: type = $issue_type"
else
    fail "positional type" "bug" "$issue_type"
fi

# ============================================================
# Test 2: Named args (--title, --description, etc.)
# ============================================================
echo ""
echo "Test 2: Named arguments"

reset_json
run_test
$VIBAN_BIN add --title "Named title" --description "Named desc" --priority P0 --type feat >/dev/null 2>&1
title=$(get_issue_field 1 "title")
if [[ "$title" == "Named title" ]]; then
    pass "named: title = '$title'"
else
    fail "named title" "Named title" "$title"
fi

run_test
desc=$(get_issue_field 1 "description")
if [[ "$desc" == "Named desc" ]]; then
    pass "named: description = '$desc'"
else
    fail "named description" "Named desc" "$desc"
fi

run_test
priority=$(get_issue_field 1 "priority")
if [[ "$priority" == "P0" ]]; then
    pass "named: priority = $priority"
else
    fail "named priority" "P0" "$priority"
fi

run_test
issue_type=$(get_issue_field 1 "type")
if [[ "$issue_type" == "feat" ]]; then
    pass "named: type = $issue_type"
else
    fail "named type" "feat" "$issue_type"
fi

# ============================================================
# Test 3: --title flag value is not literally "--title"
# ============================================================
echo ""
echo "Test 3: --title flag not stored as literal '--title'"

reset_json
run_test
$VIBAN_BIN add --title "Real title here" >/dev/null 2>&1
title=$(get_issue_field 1 "title")
if [[ "$title" != "--title" ]]; then
    pass "title is not '--title', got: '$title'"
else
    fail "title should not be '--title'" "Real title here" "$title"
fi

# ============================================================
# Test 4: Mixed positional and named args
# ============================================================
echo ""
echo "Test 4: Positional title with named priority"

reset_json
run_test
$VIBAN_BIN add "Positional title" --priority P2 --type chore >/dev/null 2>&1
title=$(get_issue_field 1 "title")
if [[ "$title" == "Positional title" ]]; then
    pass "mixed: title = '$title'"
else
    fail "mixed title" "Positional title" "$title"
fi

run_test
priority=$(get_issue_field 1 "priority")
if [[ "$priority" == "P2" ]]; then
    pass "mixed: priority = $priority"
else
    fail "mixed priority" "P2" "$priority"
fi

run_test
issue_type=$(get_issue_field 1 "type")
if [[ "$issue_type" == "chore" ]]; then
    pass "mixed: type = $issue_type"
else
    fail "mixed type" "chore" "$issue_type"
fi

# ============================================================
# Test 5: Short desc flag
# ============================================================
echo ""
echo "Test 5: Short --desc flag"

reset_json
run_test
$VIBAN_BIN add --title "Short flag" --desc "Short desc" >/dev/null 2>&1
desc=$(get_issue_field 1 "description")
if [[ "$desc" == "Short desc" ]]; then
    pass "--desc shorthand works: '$desc'"
else
    fail "--desc shorthand" "Short desc" "$desc"
fi

# ============================================================
# Test 6: Default priority when not specified
# ============================================================
echo ""
echo "Test 6: Default priority P3"

reset_json
run_test
$VIBAN_BIN add "Just title" >/dev/null 2>&1
priority=$(get_issue_field 1 "priority")
if [[ "$priority" == "P3" ]]; then
    pass "default priority = P3"
else
    fail "default priority" "P3" "$priority"
fi

# ============================================================
# Test 7: Korean title with named args
# ============================================================
echo ""
echo "Test 7: Korean title with named args"

reset_json
run_test
$VIBAN_BIN add --title "백테스트 차트 로딩 오류" --priority P1 --type bug >/dev/null 2>&1
title=$(get_issue_field 1 "title")
if [[ "$title" == "백테스트 차트 로딩 오류" ]]; then
    pass "Korean named title: '$title'"
else
    fail "Korean named title" "백테스트 차트 로딩 오류" "$title"
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
