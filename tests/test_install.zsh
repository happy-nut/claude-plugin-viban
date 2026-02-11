#!/bin/zsh
# Test: install.sh structural integrity

SCRIPT_DIR="${0:A:h}"
PROJECT_ROOT="${SCRIPT_DIR:h}"
INSTALL_SCRIPT="$PROJECT_ROOT/install.sh"

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

echo "Testing install.sh structural integrity..."
echo ""

# ─── Test 1: Syntax check ───
echo "Test 1: Bash syntax validation"
run_test
if bash -n "$INSTALL_SCRIPT" 2>/dev/null; then
    pass "install.sh has valid bash syntax"
else
    fail "install.sh syntax check" "valid syntax" "syntax error"
fi

# ─── Test 2: main() wrapper exists (prevents curl|bash stdin issues) ───
echo ""
echo "Test 2: main() wrapper for curl|bash safety"
run_test
if grep -q '^main()' "$INSTALL_SCRIPT"; then
    pass "main() function defined"
else
    fail "main() function" "main() defined" "not found"
fi

run_test
if grep -q '^main "\$@"' "$INSTALL_SCRIPT"; then
    pass "main \"\$@\" called at end"
else
    fail "main invocation" "main \"\$@\" at end" "not found"
fi

# ─── Test 3: No plugins.json references (use claude plugin CLI instead) ───
echo ""
echo "Test 3: No legacy plugins.json registration"
run_test
if grep -q 'plugins\.json' "$INSTALL_SCRIPT"; then
    fail "plugins.json absent" "no plugins.json references" "found plugins.json reference"
else
    pass "no plugins.json references (uses claude plugin CLI)"
fi

# ─── Test 4: Correct plugin registration method ───
echo ""
echo "Test 4: Claude plugin CLI registration"
run_test
if grep -q 'claude plugin marketplace add' "$INSTALL_SCRIPT"; then
    pass "uses 'claude plugin marketplace add'"
else
    fail "marketplace add" "claude plugin marketplace add" "not found"
fi

run_test
if grep -q 'claude plugin install' "$INSTALL_SCRIPT"; then
    pass "uses 'claude plugin install'"
else
    fail "plugin install" "claude plugin install" "not found"
fi

# ─── Test 5: Fallback when claude CLI is missing ───
echo ""
echo "Test 5: Fallback for missing claude CLI"
run_test
if grep -q 'command -v claude' "$INSTALL_SCRIPT"; then
    pass "checks for claude CLI availability"
else
    fail "claude CLI check" "command -v claude" "not found"
fi

# ─── Test 6: Required dependencies are installed ───
echo ""
echo "Test 6: All required dependencies in install script"
DEPS_OK=true
for dep in zsh python3 jq; do
    run_test
    if grep -q "install_pkg \"$dep\"" "$INSTALL_SCRIPT"; then
        pass "installs $dep via install_pkg"
    else
        fail "dependency $dep" "install_pkg \"$dep\"" "not found"
        DEPS_OK=false
    fi
done
run_test
if grep -q 'install_gum' "$INSTALL_SCRIPT"; then
    pass "installs gum via install_gum"
else
    fail "dependency gum" "install_gum call" "not found"
    DEPS_OK=false
fi

# ─── Results ───
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
