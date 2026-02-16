#!/bin/zsh
# Test: backup and restore commands

SCRIPT_DIR="${0:A:h}"
PROJECT_ROOT="${SCRIPT_DIR:h}"
VIBAN_BIN="$PROJECT_ROOT/bin/viban"

TESTS_RUN=0
TESTS_PASSED=0

pass() { ((TESTS_PASSED++)); echo "  ✓ $1"; }
fail() { ((TESTS_PASSED+=0)); echo "  ✗ $1"; echo "    Expected: $2"; echo "    Got: $3"; }
run_test() { ((TESTS_RUN++)); }

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

echo "Testing backup/restore..."
echo ""

# ============================================================
# Test 1: Backup creates file
# ============================================================
echo "Test 1: backup creates file"
reset_json
$VIBAN_BIN add "Task A" "desc" P1 feat >/dev/null 2>&1
run_test
output=$($VIBAN_BIN backup 2>&1)
local backup_count=$(ls "$VIBAN_DATA_DIR/backups"/viban_*.json 2>/dev/null | wc -l | tr -d ' ')
if [[ "$backup_count" -ge 1 && "$output" == *"Backup saved"* ]]; then
    pass "backup file created"
else
    fail "should create backup" ">=1 file" "count=$backup_count"
fi

# ============================================================
# Test 2: Backup preserves data
# ============================================================
echo ""
echo "Test 2: backup preserves data"
run_test
local backup_file=$(ls -t "$VIBAN_DATA_DIR/backups"/viban_*.json | head -1)
local backup_issues=$(jq '.issues|length' "$backup_file")
if [[ "$backup_issues" -eq 1 ]]; then
    pass "backup has correct issue count"
else
    fail "should have 1 issue" "1" "$backup_issues"
fi

# ============================================================
# Test 3: Restore lists backups
# ============================================================
echo ""
echo "Test 3: restore lists backups"
run_test
output=$($VIBAN_BIN restore 2>&1)
if [[ "$output" == *"Available backups"* && "$output" == *"viban_"* ]]; then
    pass "restore lists available backups"
else
    fail "should list backups" "Available backups" "$output"
fi

# ============================================================
# Test 4: Restore from file
# ============================================================
echo ""
echo "Test 4: restore from specific file"
$VIBAN_BIN add "Task B" "desc" P0 bug >/dev/null 2>&1
local before_count=$(jq '.issues|length' "$VIBAN_JSON")
run_test
local backup_name="${backup_file:t}"
output=$($VIBAN_BIN restore "$backup_name" 2>&1)
local after_count=$(jq '.issues|length' "$VIBAN_JSON")
if [[ "$before_count" -eq 2 && "$after_count" -eq 1 && "$output" == *"Restored"* ]]; then
    pass "restore reverted to backup state"
else
    fail "should restore to 1 issue" "before=2, after=1" "before=$before_count, after=$after_count"
fi

# ============================================================
# Test 5: Restore nonexistent file shows error
# ============================================================
echo ""
echo "Test 5: restore nonexistent file"
run_test
output=$($VIBAN_BIN restore "nonexistent.json" 2>&1)
if [[ "$output" == *"not found"* ]]; then
    pass "error on missing backup"
else
    fail "should show not found" "not found" "$output"
fi

# ============================================================
# Test 6: Restore with no backups
# ============================================================
echo ""
echo "Test 6: no backups available"
rm -rf "$VIBAN_DATA_DIR/backups"
run_test
output=$($VIBAN_BIN restore 2>&1)
if [[ "$output" == *"No backups"* ]]; then
    pass "handles no backups"
else
    fail "should show no backups" "No backups" "$output"
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
