#!/bin/zsh
# Test: auto-sync features (sync_create, --auto flag, closed issue handling)

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

# Setup temp dirs
VIBAN_DATA_DIR=$(mktemp -d)
export VIBAN_DATA_DIR
VIBAN_JSON="$VIBAN_DATA_DIR/viban.json"
SYNC_JSON="$VIBAN_DATA_DIR/sync.json"
MOCK_PROVIDER_DIR=$(mktemp -d)
trap "rm -rf $VIBAN_DATA_DIR $MOCK_PROVIDER_DIR" EXIT

reset_json() {
    cat > "$VIBAN_JSON" << 'EOF'
{
  "version": 2,
  "next_id": 1,
  "issues": []
}
EOF
}

# Create mock provider
create_mock_provider() {
    mkdir -p "$MOCK_PROVIDER_DIR/scripts/providers"
    cat > "$MOCK_PROVIDER_DIR/scripts/providers/mock.sh" << 'MOCKEOF'
#!/bin/bash
provider_name() { echo "mock"; }
provider_check_deps() { return 0; }
provider_check_auth() { return 0; }
provider_detect_config() { echo '{"repo":"test/repo"}'; }
provider_fetch_issues() {
    cat << 'ISSUES'
[
  {
    "remote_id": "42",
    "title": "Open issue",
    "description": "This is open",
    "status": "backlog",
    "priority": "P1",
    "type": "bug",
    "updated_at": "2026-02-11T10:00:00Z"
  },
  {
    "remote_id": "43",
    "title": "Closed issue",
    "description": "This was closed",
    "status": "done",
    "priority": "P2",
    "type": "feat",
    "updated_at": "2026-02-11T09:00:00Z"
  }
]
ISSUES
}
provider_create_issue() { echo "99"; }
provider_update_issue() { cat > /dev/null; return 0; }
provider_close_issue() { return 0; }
provider_ensure_labels() { return 0; }
MOCKEOF
    chmod +x "$MOCK_PROVIDER_DIR/scripts/providers/mock.sh"

    # Create failing provider for error test
    cat > "$MOCK_PROVIDER_DIR/scripts/providers/failing.sh" << 'FAILEOF'
#!/bin/bash
provider_name() { echo "failing"; }
provider_check_deps() { return 0; }
provider_check_auth() { return 0; }
provider_detect_config() { echo '{"repo":"test/repo"}'; }
provider_fetch_issues() { echo "[]"; }
provider_create_issue() { echo "Error: network failure" >&2; return 1; }
provider_update_issue() { cat > /dev/null; return 0; }
provider_close_issue() { return 0; }
provider_ensure_labels() { return 0; }
FAILEOF
    chmod +x "$MOCK_PROVIDER_DIR/scripts/providers/failing.sh"
}

create_mock_provider

echo "Testing auto-sync features..."
echo ""

# ============================================================
# Test 1: sync_create.sh syntax validation
# ============================================================
echo "Test 1: sync_create.sh syntax validation"

run_test
if bash -n "$PROJECT_ROOT/scripts/sync_create.sh" 2>/dev/null; then
    pass "sync_create.sh syntax valid"
else
    fail "sync_create.sh syntax" "valid" "syntax error"
fi

# ============================================================
# Test 2: Auto-create on add when sync configured
# ============================================================
echo ""
echo "Test 2: Auto-create on add with sync configured"

reset_json
# Setup sync.json with mock provider
cat > "$SYNC_JSON" << 'EOF'
{"provider":"mock","provider_config":{"repo":"test/repo"},"last_sync_at":"2026-02-11T00:00:00Z","issues":{}}
EOF

run_test
# Call sync_create.sh directly with mock provider
$VIBAN_BIN add "Test auto-create" "desc" P1 bug >/dev/null 2>&1

# Add a card manually and test sync_create.sh
reset_json
cat > "$SYNC_JSON" << 'EOF'
{"provider":"mock","provider_config":{"repo":"test/repo"},"last_sync_at":"2026-02-11T00:00:00Z","issues":{}}
EOF

# Add card without ext_id
jq '.next_id = 2 | .issues = [{"id":1,"title":"Test card","description":"desc","status":"backlog","priority":"P1","type":"bug","external_id":null,"attachments":[],"assigned_to":null,"created_at":"2026-02-11T10:00:00Z","updated_at":"2026-02-11T10:00:00Z"}]' \
    "$VIBAN_JSON" > "${VIBAN_JSON}.tmp" && mv "${VIBAN_JSON}.tmp" "$VIBAN_JSON"

result=$(VIBAN_JSON="$VIBAN_JSON" VIBAN_DATA_DIR="$VIBAN_DATA_DIR" \
    VIBAN_PROVIDER="mock" VIBAN_SCRIPT_DIR="$MOCK_PROVIDER_DIR" \
    bash "$PROJECT_ROOT/scripts/sync_create.sh" 1 2>/dev/null) || true

if [[ "$result" == "mock:99" ]]; then
    pass "sync_create returns mock:99"
else
    fail "sync_create result" "mock:99" "$result"
fi

run_test
# Verify card was updated with external_id
ext_id=$(jq -r '.issues[0].external_id' "$VIBAN_JSON")
if [[ "$ext_id" == "mock:99" ]]; then
    pass "card external_id updated to mock:99"
else
    fail "card external_id" "mock:99" "$ext_id"
fi

run_test
# Verify sync metadata recorded
sync_rid=$(jq -r '.issues["1"].remote_id' "$SYNC_JSON")
if [[ "$sync_rid" == "99" ]]; then
    pass "sync metadata recorded for card 1"
else
    fail "sync metadata" "99" "$sync_rid"
fi

# ============================================================
# Test 3: No auto-create when sync not configured
# ============================================================
echo ""
echo "Test 3: No auto-create without sync"

reset_json
rm -f "$SYNC_JSON"

run_test
$VIBAN_BIN add "No sync card" "desc" P2 feat >/dev/null 2>&1
ext_id=$(jq -r '.issues[0].external_id' "$VIBAN_JSON")
if [[ "$ext_id" == "null" ]]; then
    pass "no external_id without sync.json"
else
    fail "no auto-create" "null" "$ext_id"
fi

# ============================================================
# Test 4: Graceful failure when provider errors
# ============================================================
echo ""
echo "Test 4: Graceful failure on provider error"

reset_json
cat > "$SYNC_JSON" << 'EOF'
{"provider":"failing","provider_config":{"repo":"test/repo"},"last_sync_at":"2026-02-11T00:00:00Z","issues":{}}
EOF

jq '.next_id = 2 | .issues = [{"id":1,"title":"Fail card","description":"desc","status":"backlog","priority":"P1","type":"bug","external_id":null,"attachments":[],"assigned_to":null,"created_at":"2026-02-11T10:00:00Z","updated_at":"2026-02-11T10:00:00Z"}]' \
    "$VIBAN_JSON" > "${VIBAN_JSON}.tmp" && mv "${VIBAN_JSON}.tmp" "$VIBAN_JSON"

run_test
result=$(VIBAN_JSON="$VIBAN_JSON" VIBAN_DATA_DIR="$VIBAN_DATA_DIR" \
    VIBAN_PROVIDER="failing" VIBAN_SCRIPT_DIR="$MOCK_PROVIDER_DIR" \
    bash "$PROJECT_ROOT/scripts/sync_create.sh" 1 2>/dev/null) || true

# Should return empty (failure) but not crash
if [[ -z "$result" ]]; then
    pass "graceful failure returns empty"
else
    fail "graceful failure" "empty" "$result"
fi

run_test
# Card should still exist and be unchanged
card_title=$(jq -r '.issues[0].title' "$VIBAN_JSON")
if [[ "$card_title" == "Fail card" ]]; then
    pass "card preserved after provider failure"
else
    fail "card preserved" "Fail card" "$card_title"
fi

# ============================================================
# Test 5: --auto flag silent execution
# ============================================================
echo ""
echo "Test 5: --auto flag behavior"

reset_json
cat > "$SYNC_JSON" << 'EOF'
{"provider":"mock","provider_config":{"repo":"test/repo"},"last_sync_at":"2026-02-10T00:00:00Z","issues":{}}
EOF

run_test
# Run sync with --auto flag using mock provider
output=$(VIBAN_JSON="$VIBAN_JSON" VIBAN_DATA_DIR="$VIBAN_DATA_DIR" \
    VIBAN_PROVIDER="mock" VIBAN_SCRIPT_DIR="$MOCK_PROVIDER_DIR" \
    bash "$PROJECT_ROOT/scripts/sync.sh" --auto 2>&1) || true

# Should produce no stdout output
if [[ -z "$output" ]]; then
    pass "--auto produces no output"
else
    fail "--auto silent" "empty" "$output"
fi

run_test
# last_sync_at should be updated
last_sync=$(jq -r '.last_sync_at' "$SYNC_JSON")
if [[ "$last_sync" > "2026-02-10T00:00:00Z" ]]; then
    pass "--auto updates last_sync_at"
else
    fail "--auto last_sync_at" ">2026-02-10" "$last_sync"
fi

# ============================================================
# Test 6: Closed remote issue -> card removed
# ============================================================
echo ""
echo "Test 6: Closed issue removes existing card"

reset_json
# Setup: card linked to mock:43 (which is closed in mock provider)
jq '.next_id = 2 | .issues = [{"id":1,"title":"Will be closed","description":"desc","status":"in_progress","priority":"P2","type":"feat","external_id":"mock:43","attachments":[],"assigned_to":null,"created_at":"2026-02-11T08:00:00Z","updated_at":"2026-02-11T08:00:00Z"}]' \
    "$VIBAN_JSON" > "${VIBAN_JSON}.tmp" && mv "${VIBAN_JSON}.tmp" "$VIBAN_JSON"
cat > "$SYNC_JSON" << 'EOF'
{"provider":"mock","provider_config":{"repo":"test/repo"},"last_sync_at":"2026-02-10T00:00:00Z","issues":{"1":{"remote_id":"43","remote_updated_at":"2026-02-10T09:00:00Z","viban_updated_at":"2026-02-11T08:00:00Z"}}}
EOF

run_test
VIBAN_JSON="$VIBAN_JSON" VIBAN_DATA_DIR="$VIBAN_DATA_DIR" \
    VIBAN_PROVIDER="mock" VIBAN_SCRIPT_DIR="$MOCK_PROVIDER_DIR" \
    bash "$PROJECT_ROOT/scripts/sync.sh" --pull-only >/dev/null 2>&1 || true

# The original card (id=1, mock:43) should be removed; open issue 42 gets imported
closed_card=$(jq -r '.issues[] | select(.external_id == "mock:43")' "$VIBAN_JSON")
if [[ -z "$closed_card" ]]; then
    pass "closed remote issue removes card (mock:43 gone)"
else
    fail "card removed" "mock:43 absent" "mock:43 still present"
fi

# ============================================================
# Test 7: Closed issue skipped on initial import
# ============================================================
echo ""
echo "Test 7: Closed issue skipped on initial import"

reset_json
cat > "$SYNC_JSON" << 'EOF'
{"provider":"mock","provider_config":{"repo":"test/repo"},"last_sync_at":"2026-02-10T00:00:00Z","issues":{}}
EOF

run_test
VIBAN_JSON="$VIBAN_JSON" VIBAN_DATA_DIR="$VIBAN_DATA_DIR" \
    VIBAN_PROVIDER="mock" VIBAN_SCRIPT_DIR="$MOCK_PROVIDER_DIR" \
    bash "$PROJECT_ROOT/scripts/sync.sh" --pull-only >/dev/null 2>&1 || true

# Only the open issue (#42) should be imported, not the closed one (#43)
card_count=$(jq '.issues | length' "$VIBAN_JSON")
if [[ "$card_count" == "1" ]]; then
    pass "only open issue imported (closed skipped)"
else
    fail "import count" "1 card" "$card_count cards"
fi

run_test
imported_ext=$(jq -r '.issues[0].external_id' "$VIBAN_JSON")
if [[ "$imported_ext" == "mock:42" ]]; then
    pass "imported issue is mock:42 (open one)"
else
    fail "imported issue" "mock:42" "$imported_ext"
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
