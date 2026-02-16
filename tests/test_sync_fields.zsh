#!/bin/zsh
# Test: sync new fields (blocked_by, sub-tasks, comments)

SCRIPT_DIR="${0:A:h}"
PROJECT_ROOT="${SCRIPT_DIR:h}"

TESTS_RUN=0
TESTS_PASSED=0

pass() { ((TESTS_PASSED++)); echo "  ✓ $1"; }
fail() { ((TESTS_PASSED+=0)); echo "  ✗ $1"; echo "    Expected: $2"; echo "    Got: $3"; }
run_test() { ((TESTS_RUN++)); }

VIBAN_DATA_DIR=$(mktemp -d)
export VIBAN_DATA_DIR
VIBAN_JSON="$VIBAN_DATA_DIR/viban.json"
export VIBAN_JSON
SYNC_JSON="$VIBAN_DATA_DIR/sync.json"
export SYNC_JSON

trap "rm -rf $VIBAN_DATA_DIR" EXIT

# Helper: run bash function from sync.sh
run_sync_func() {
    bash -c "
        export VIBAN_JSON='$VIBAN_JSON'
        export VIBAN_DATA_DIR='$VIBAN_DATA_DIR'
        export SYNC_JSON='$SYNC_JSON'
        export VIBAN_PROVIDER='github'
        export VIBAN_SCRIPT_DIR='$PROJECT_ROOT'
        source '$PROJECT_ROOT/scripts/sync.sh' 2>/dev/null
        # Mock provider_push_comment for testing
        provider_push_comment() { echo \"\$3\" >> '$VIBAN_DATA_DIR/pushed_comments.log'; }
        $@
    " 2>/dev/null
}

echo "Testing sync new fields..."
echo ""

# ============================================================
# Test 1: build_enriched_body with blocked_by
# ============================================================
echo "Test 1: enriched body with blocked_by"
cat > "$VIBAN_JSON" << 'EOF'
{
  "version": 2,
  "next_id": 4,
  "issues": [
    {"id": 1, "title": "Task A", "description": "Desc A", "status": "backlog", "priority": "P1", "external_id": "github:10"},
    {"id": 2, "title": "Task B", "description": "Desc B", "status": "backlog", "priority": "P2", "blocked_by": [1]},
    {"id": 3, "title": "Task C", "description": "Desc C", "status": "backlog", "priority": "P3", "blocked_by": [1, 2]}
  ]
}
EOF
run_test
output=$(run_sync_func 'build_enriched_body 2')
if [[ "$output" == *"Blocked by"* && "$output" == *"#10"* ]]; then
    pass "blocked_by includes GitHub reference"
else
    fail "should include blocked_by with GH ref" "#10" "$output"
fi

# ============================================================
# Test 2: enriched body with multiple blocked_by (mixed refs)
# ============================================================
echo ""
echo "Test 2: blocked_by with mixed references"
run_test
output=$(run_sync_func 'build_enriched_body 3')
if [[ "$output" == *"#10"* && "$output" == *"viban:#2"* ]]; then
    pass "mixed GitHub and viban references"
else
    fail "should have #10 and viban:#2" "#10, viban:#2" "$output"
fi

# ============================================================
# Test 3: build_enriched_body with sub-tasks
# ============================================================
echo ""
echo "Test 3: enriched body with sub-tasks"
cat > "$VIBAN_JSON" << 'EOF'
{
  "version": 2,
  "next_id": 5,
  "issues": [
    {"id": 1, "title": "Parent Task", "description": "Parent desc", "status": "in_progress", "priority": "P1"},
    {"id": 2, "title": "Child A", "description": "", "status": "done", "priority": "P2", "parent_id": 1},
    {"id": 3, "title": "Child B", "description": "", "status": "backlog", "priority": "P2", "parent_id": 1}
  ]
}
EOF
run_test
output=$(run_sync_func 'build_enriched_body 1')
if [[ "$output" == *"Sub-tasks"* && "$output" == *"[x]"* && "$output" == *"[ ]"* ]]; then
    pass "sub-tasks with done/open checkboxes"
else
    fail "should include sub-task checkboxes" "[x] and [ ]" "$output"
fi

# ============================================================
# Test 4: plain body without metadata
# ============================================================
echo ""
echo "Test 4: plain body without metadata"
cat > "$VIBAN_JSON" << 'EOF'
{
  "version": 2,
  "next_id": 2,
  "issues": [
    {"id": 1, "title": "Simple Task", "description": "Just a description", "status": "backlog", "priority": "P3"}
  ]
}
EOF
run_test
output=$(run_sync_func 'build_enriched_body 1')
if [[ "$output" == "Just a description" ]]; then
    pass "no metadata sections for plain card"
else
    fail "should be plain description" "Just a description" "$output"
fi

# ============================================================
# Test 5: strip_viban_meta removes metadata
# ============================================================
echo ""
echo "Test 5: strip viban meta from body"
run_test
output=$(bash -c "
    export VIBAN_JSON='$VIBAN_JSON' VIBAN_DATA_DIR='$VIBAN_DATA_DIR'
    export SYNC_JSON='$SYNC_JSON' VIBAN_PROVIDER=github VIBAN_SCRIPT_DIR='$PROJECT_ROOT'
    source '$PROJECT_ROOT/scripts/sync.sh' 2>/dev/null
    strip_viban_meta 'Original description

<!-- viban:meta:start -->
---
**Blocked by:** #10
<!-- viban:meta:end -->'
" 2>/dev/null)
if [[ "$output" == "Original description" ]]; then
    pass "metadata stripped, description preserved"
else
    fail "should strip metadata" "Original description" "$output"
fi

# ============================================================
# Test 6: strip_viban_meta with no metadata
# ============================================================
echo ""
echo "Test 6: strip viban meta (no metadata present)"
run_test
output=$(bash -c "
    export VIBAN_JSON='$VIBAN_JSON' VIBAN_DATA_DIR='$VIBAN_DATA_DIR'
    export SYNC_JSON='$SYNC_JSON' VIBAN_PROVIDER=github VIBAN_SCRIPT_DIR='$PROJECT_ROOT'
    source '$PROJECT_ROOT/scripts/sync.sh' 2>/dev/null
    strip_viban_meta 'Plain body with no metadata'
" 2>/dev/null)
if [[ "$output" == "Plain body with no metadata" ]]; then
    pass "body unchanged when no metadata"
else
    fail "should return body as-is" "Plain body with no metadata" "$output"
fi

# ============================================================
# Test 7: push_new_comments tracks synced count
# ============================================================
echo ""
echo "Test 7: comment sync tracking"
cat > "$VIBAN_JSON" << 'EOF'
{
  "version": 2,
  "next_id": 2,
  "issues": [
    {"id": 1, "title": "Task", "description": "", "status": "backlog", "priority": "P3",
     "external_id": "github:10",
     "comments": [
       {"text": "First comment", "created_at": "2026-01-01T00:00:00Z"},
       {"text": "Second comment", "created_at": "2026-01-02T00:00:00Z"}
     ]}
  ]
}
EOF
echo '{"provider":"github","provider_config":{"repo":"test/repo"},"issues":{"1":{"remote_id":"10","remote_updated_at":"2026-01-01","viban_updated_at":"2026-01-01","synced_comment_count":0}}}' > "$SYNC_JSON"
run_test
> "$VIBAN_DATA_DIR/pushed_comments.log"
bash -c "
    export VIBAN_JSON='$VIBAN_JSON'
    export VIBAN_DATA_DIR='$VIBAN_DATA_DIR'
    export SYNC_JSON='$SYNC_JSON'
    export VIBAN_PROVIDER=github VIBAN_SCRIPT_DIR='$PROJECT_ROOT'
    source '$PROJECT_ROOT/scripts/sync.sh' 2>/dev/null
    provider_push_comment() { echo \"\$3\" >> '$VIBAN_DATA_DIR/pushed_comments.log'; }
    card=\$(jq '.issues[0]' '$VIBAN_JSON')
    push_new_comments 'test/repo' '10' '1' \"\$card\"
" 2>/dev/null
local pushed_count=$(wc -l < "$VIBAN_DATA_DIR/pushed_comments.log" | tr -d ' ')
local synced=$(jq -r '.issues["1"].synced_comment_count' "$SYNC_JSON")
if [[ "$pushed_count" -eq 2 && "$synced" -eq 2 ]]; then
    pass "pushed 2 comments, synced_count updated to 2"
else
    fail "should push 2 and track" "pushed=2, synced=2" "pushed=$pushed_count, synced=$synced"
fi

# ============================================================
# Test 8: push_new_comments skips already synced
# ============================================================
echo ""
echo "Test 8: comments skip already synced"
jq '.issues[0].comments += [{"text":"Third comment","created_at":"2026-01-03T00:00:00Z"}]' \
    "$VIBAN_JSON" > "${VIBAN_JSON}.tmp" && mv "${VIBAN_JSON}.tmp" "$VIBAN_JSON"
run_test
> "$VIBAN_DATA_DIR/pushed_comments.log"
bash -c "
    export VIBAN_JSON='$VIBAN_JSON'
    export VIBAN_DATA_DIR='$VIBAN_DATA_DIR'
    export SYNC_JSON='$SYNC_JSON'
    export VIBAN_PROVIDER=github VIBAN_SCRIPT_DIR='$PROJECT_ROOT'
    source '$PROJECT_ROOT/scripts/sync.sh' 2>/dev/null
    provider_push_comment() { echo \"\$3\" >> '$VIBAN_DATA_DIR/pushed_comments.log'; }
    card=\$(jq '.issues[0]' '$VIBAN_JSON')
    push_new_comments 'test/repo' '10' '1' \"\$card\"
" 2>/dev/null
pushed_count=$(wc -l < "$VIBAN_DATA_DIR/pushed_comments.log" | tr -d ' ')
synced=$(jq -r '.issues["1"].synced_comment_count' "$SYNC_JSON")
if [[ "$pushed_count" -eq 1 && "$synced" -eq 3 ]]; then
    pass "pushed only 1 new comment, synced_count=3"
else
    fail "should push only new" "pushed=1, synced=3" "pushed=$pushed_count, synced=$synced"
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
