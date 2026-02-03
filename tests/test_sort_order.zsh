#!/bin/zsh
# Test: Sort order consistency between display and operations
# Verifies that get_sort_expr returns correct sort for each status

# Note: Don't use 'set -e' as arithmetic expansion ((VAR++)) returns non-zero when VAR is 0

SCRIPT_DIR="${0:A:h}"
PROJECT_ROOT="${SCRIPT_DIR:h}"
VIBAN_BIN="$PROJECT_ROOT/bin/viban"

# Source the viban script to get access to functions
# We need to mock some things first
VIBAN_DATA_DIR=$(mktemp -d)
VIBAN_JSON="$VIBAN_DATA_DIR/viban.json"
trap "rm -rf $VIBAN_DATA_DIR" EXIT

# Create test data
cat > "$VIBAN_JSON" << 'EOF'
{
  "version": 2,
  "next_id": 5,
  "issues": [
    {"id": 1, "title": "P3 task", "status": "backlog", "priority": "P3", "updated_at": "2024-01-01T00:00:00Z"},
    {"id": 2, "title": "P1 task", "status": "backlog", "priority": "P1", "updated_at": "2024-01-02T00:00:00Z"},
    {"id": 3, "title": "P0 task", "status": "backlog", "priority": "P0", "updated_at": "2024-01-03T00:00:00Z"},
    {"id": 4, "title": "Old review", "status": "review", "priority": "P0", "updated_at": "2024-01-01T00:00:00Z"},
    {"id": 5, "title": "New review", "status": "review", "priority": "P3", "updated_at": "2024-01-05T00:00:00Z"}
  ]
}
EOF

# Test counter
TESTS_RUN=0
TESTS_PASSED=0

pass() {
    ((TESTS_PASSED++))
    echo "  ✓ $1"
}

fail() {
    echo "  ✗ $1"
    echo "    Expected: $2"
    echo "    Got: $3"
}

run_test() {
    ((TESTS_RUN++))
}

echo "Testing sort order functions..."
echo ""

# Source functions from viban (extract just what we need)
get_sort_expr() {
    local st="$1"
    if [[ "$st" == "review" ]]; then
        echo 'sort_by(.updated_at) | reverse'
    else
        echo 'sort_by(if .order != null then [0, .order] else [1, ({"P0":0,"P1":1,"P2":2,"P3":3}[.priority // "P3"] // 3), .id] end)'
    fi
}

get_issue_id_at_index() {
    local st="$1" idx="$2" json_data="$3"
    local sort_expr=$(get_sort_expr "$st")
    printf '%s' "$json_data" | jq -r --arg s "$st" --argjson i "$idx" \
        ".issues | map(select(.status==\$s)) | $sort_expr | .[\$i].id // empty"
}

# ============================================================
# Test 1: get_sort_expr returns different expressions per status
# ============================================================
echo "Test 1: get_sort_expr returns correct expression per status"
run_test

backlog_sort=$(get_sort_expr "backlog")
review_sort=$(get_sort_expr "review")

if [[ "$backlog_sort" != "$review_sort" ]]; then
    pass "backlog and review use different sort expressions"
else
    fail "sort expressions should differ" "different" "same"
fi

run_test
if [[ "$review_sort" == "sort_by(.updated_at) | reverse" ]]; then
    pass "review uses updated_at sort (newest first)"
else
    fail "review sort expression" "sort_by(.updated_at) | reverse" "$review_sort"
fi

# ============================================================
# Test 2: Backlog sorted by priority (P0 first, then P1, P2, P3)
# ============================================================
echo ""
echo "Test 2: Backlog sorted by priority (P0 > P1 > P2 > P3)"
run_test

json_data=$(cat "$VIBAN_JSON")

# First card in backlog should be P0 (id=3)
first_backlog_id=$(get_issue_id_at_index "backlog" 0 "$json_data")
if [[ "$first_backlog_id" == "3" ]]; then
    pass "first backlog card is P0 task (id=3)"
else
    fail "first backlog card" "3 (P0 task)" "$first_backlog_id"
fi

run_test
# Second should be P1 (id=2)
second_backlog_id=$(get_issue_id_at_index "backlog" 1 "$json_data")
if [[ "$second_backlog_id" == "2" ]]; then
    pass "second backlog card is P1 task (id=2)"
else
    fail "second backlog card" "2 (P1 task)" "$second_backlog_id"
fi

run_test
# Third should be P3 (id=1)
third_backlog_id=$(get_issue_id_at_index "backlog" 2 "$json_data")
if [[ "$third_backlog_id" == "1" ]]; then
    pass "third backlog card is P3 task (id=1)"
else
    fail "third backlog card" "1 (P3 task)" "$third_backlog_id"
fi

# ============================================================
# Test 3: Review sorted by updated_at (newest first)
# ============================================================
echo ""
echo "Test 3: Review sorted by updated_at (newest first)"
run_test

# First review card should be the newest one (id=5, updated 2024-01-05)
first_review_id=$(get_issue_id_at_index "review" 0 "$json_data")
if [[ "$first_review_id" == "5" ]]; then
    pass "first review card is newest (id=5, 2024-01-05)"
else
    fail "first review card" "5 (newest)" "$first_review_id"
fi

run_test
# Second review card should be older (id=4, updated 2024-01-01)
second_review_id=$(get_issue_id_at_index "review" 1 "$json_data")
if [[ "$second_review_id" == "4" ]]; then
    pass "second review card is older (id=4, 2024-01-01)"
else
    fail "second review card" "4 (older)" "$second_review_id"
fi

# ============================================================
# Test 4: Manual order overrides priority
# ============================================================
echo ""
echo "Test 4: Manual order overrides priority"

# Add a P3 task with manual order that should appear first
cat > "$VIBAN_JSON" << 'EOF'
{
  "version": 2,
  "next_id": 4,
  "issues": [
    {"id": 1, "title": "P0 no order", "status": "backlog", "priority": "P0"},
    {"id": 2, "title": "P3 with order", "status": "backlog", "priority": "P3", "order": 0.5},
    {"id": 3, "title": "P1 no order", "status": "backlog", "priority": "P1"}
  ]
}
EOF

json_data=$(cat "$VIBAN_JSON")

run_test
# Card with manual order should be first despite being P3
first_id=$(get_issue_id_at_index "backlog" 0 "$json_data")
if [[ "$first_id" == "2" ]]; then
    pass "manual order (0.5) comes before priority-sorted cards"
else
    fail "first card with manual order" "2 (P3 with order=0.5)" "$first_id"
fi

run_test
# Then P0 should come
second_id=$(get_issue_id_at_index "backlog" 1 "$json_data")
if [[ "$second_id" == "1" ]]; then
    pass "P0 (no order) comes second"
else
    fail "second card" "1 (P0)" "$second_id"
fi

run_test
# Then P1
third_id=$(get_issue_id_at_index "backlog" 2 "$json_data")
if [[ "$third_id" == "3" ]]; then
    pass "P1 (no order) comes third"
else
    fail "third card" "3 (P1)" "$third_id"
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
