#!/bin/zsh
# Test: VIBAN_DATA_DIR always resolves to $PWD/.viban (monorepo-safe)

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

echo "Testing VIBAN_DATA_DIR resolution (monorepo-safe)..."
echo ""

# ── Test 1: Monorepo — .viban created in CWD, not git root ──
run_test
echo "Test $TESTS_RUN: monorepo — .viban in CWD, not git root"

MONO_ROOT=$(mktemp -d)
trap "rm -rf $MONO_ROOT" EXIT

# Create a fake monorepo: git repo with a subdirectory
git -C "$MONO_ROOT" init -q
git -C "$MONO_ROOT" commit --allow-empty -m "init" -q
SUBDIR="$MONO_ROOT/packages/my-app"
mkdir -p "$SUBDIR"

# Run viban from the subdirectory (no VIBAN_DATA_DIR override)
(unset VIBAN_DATA_DIR; cd "$SUBDIR" && zsh "$VIBAN_BIN" list) &>/dev/null

if [[ -d "$SUBDIR/.viban" ]]; then
    pass ".viban created in CWD ($SUBDIR)"
else
    fail ".viban created in CWD" "$SUBDIR/.viban" "not found"
fi

# ── Test 2: .viban must NOT be at git root ──
run_test
echo "Test $TESTS_RUN: .viban NOT at git root when CWD differs"

if [[ ! -d "$MONO_ROOT/.viban" ]]; then
    pass ".viban absent from git root ($MONO_ROOT)"
else
    fail ".viban absent from git root" "no $MONO_ROOT/.viban" "found at git root"
fi

# ── Test 3: VIBAN_DATA_DIR env var still overrides ──
run_test
echo "Test $TESTS_RUN: VIBAN_DATA_DIR env override still works"

CUSTOM_DIR=$(mktemp -d)
(export VIBAN_DATA_DIR="$CUSTOM_DIR"; cd "$SUBDIR" && zsh "$VIBAN_BIN" list) &>/dev/null

if [[ -f "$CUSTOM_DIR/viban.json" ]]; then
    pass "env override honored ($CUSTOM_DIR)"
else
    fail "env override honored" "$CUSTOM_DIR/viban.json" "not found"
fi
rm -rf "$CUSTOM_DIR"

# ── Test 4: Non-git directory uses $PWD ──
run_test
echo "Test $TESTS_RUN: non-git directory uses PWD"

NOGIT_DIR=$(mktemp -d)
(unset VIBAN_DATA_DIR; cd "$NOGIT_DIR" && zsh "$VIBAN_BIN" list) &>/dev/null

if [[ -d "$NOGIT_DIR/.viban" ]]; then
    pass ".viban in non-git PWD ($NOGIT_DIR)"
else
    fail ".viban in non-git PWD" "$NOGIT_DIR/.viban" "not found"
fi
rm -rf "$NOGIT_DIR"

# ── Test 5: Lint — no git rev-parse --show-toplevel for .viban paths ──
run_test
echo "Test $TESTS_RUN: lint — no show-toplevel used for .viban path derivation"

# Check bin/viban: the VIBAN_DATA_DIR block must not use show-toplevel
_violations=()

# bin/viban: show-toplevel in VIBAN_DATA_DIR assignment
if grep -q 'VIBAN_DATA_DIR.*git rev-parse --show-toplevel' "$PROJECT_ROOT/bin/viban"; then
    _violations+=("bin/viban")
fi

# Skills: REPO_ROOT pattern for .viban paths
for f in "$PROJECT_ROOT"/skills/*/SKILL.md; do
    if grep -q 'git rev-parse --show-toplevel' "$f" 2>/dev/null; then
        _violations+=("${f#$PROJECT_ROOT/}")
    fi
done

# commands/*.md
for f in "$PROJECT_ROOT"/commands/*.md; do
    if grep -q 'git rev-parse --show-toplevel' "$f" 2>/dev/null; then
        _violations+=("${f#$PROJECT_ROOT/}")
    fi
done

if [[ ${#_violations[@]} -eq 0 ]]; then
    pass "no show-toplevel in .viban path derivation"
else
    fail "no show-toplevel in .viban path derivation" "0 violations" "${_violations[*]}"
fi

# ── Results ──
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Results: $TESTS_PASSED/$TESTS_RUN tests passed"
if [[ $TESTS_PASSED -eq $TESTS_RUN ]]; then
    echo "All tests passed!"
    exit 0
else
    echo "Some tests FAILED!"
    exit 1
fi
