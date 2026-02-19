#!/bin/zsh
# Test: SKILL.md files do not contain patterns that confuse agents
#
# Background: agents have hallucinated "python -m viban" instead of "viban"
# because SKILL.md contained ```python pseudo-code blocks. This test ensures
# all skill definitions use correct invocation patterns.

SCRIPT_DIR="${0:A:h}"
PROJECT_ROOT="${SCRIPT_DIR:h}"
SKILLS_DIR="$PROJECT_ROOT/skills"

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

echo "Testing SKILL.md integrity..."
echo ""

# ─── Test 1: No "python -m viban" or "python viban" invocations ───
echo "Test 1: No Python-based viban invocations"
for skill_file in "$SKILLS_DIR"/*/SKILL.md; do
    skill_name="${${skill_file:h}:t}"
    run_test
    if grep -v 'NEVER' "$skill_file" | grep -qE '(python3?|python3?\s+-m)\s+viban'; then
        fail "$skill_name: no python viban" \
            "no 'python viban' or 'python -m viban'" \
            "$(grep -v 'NEVER' "$skill_file" | grep -nE '(python3?|python3?\s+-m)\s+viban' | head -1)"
    else
        pass "$skill_name: no python-based viban invocation"
    fi
done

# ─── Test 2: No "node viban" or "npx viban" invocations ───
echo ""
echo "Test 2: No Node-based viban invocations"
for skill_file in "$SKILLS_DIR"/*/SKILL.md; do
    skill_name="${${skill_file:h}:t}"
    run_test
    if grep -qE '(node|npx|npm run)\s+viban' "$skill_file"; then
        fail "$skill_name: no node viban" \
            "no 'node viban' or 'npx viban'" \
            "$(grep -nE '(node|npx|npm run)\s+viban' "$skill_file" | head -1)"
    else
        pass "$skill_name: no node-based viban invocation"
    fi
done

# ─── Test 3: No ```python code blocks (confuses agents into using python) ───
echo ""
echo "Test 3: No \`\`\`python code blocks in SKILL.md"
for skill_file in "$SKILLS_DIR"/*/SKILL.md; do
    skill_name="${${skill_file:h}:t}"
    run_test
    if grep -q '```python' "$skill_file"; then
        fail "$skill_name: no python blocks" \
            "no \`\`\`python code blocks (use \`\`\`text for pseudo-code)" \
            "$(grep -n '```python' "$skill_file" | head -1)"
    else
        pass "$skill_name: no python code blocks"
    fi
done

# ─── Test 4: Bash code blocks use "viban" directly (not via interpreter) ───
echo ""
echo "Test 4: Bash blocks invoke viban directly"
for skill_file in "$SKILLS_DIR"/*/SKILL.md; do
    skill_name="${${skill_file:h}:t}"
    # Only test skills that reference viban commands
    if grep -q 'viban' "$skill_file"; then
        run_test
        # Check that viban appears as a direct command (line starts with viban or uses $(viban...))
        # and NOT prefixed by an interpreter
        if grep -E '^\s*(python3?|node|npx)\s+.*viban' "$skill_file" | grep -qv '^#'; then
            fail "$skill_name: direct viban invocation" \
                "viban called directly, not via interpreter" \
                "$(grep -nE '^\s*(python3?|node|npx)\s+.*viban' "$skill_file" | head -1)"
        else
            pass "$skill_name: viban invoked directly"
        fi
    fi
done

# ─── Test 5: Skills with viban workflow commands include CLI Reference ───
echo ""
echo "Test 5: CLI Reference section present"
for skill_file in "$SKILLS_DIR"/*/SKILL.md; do
    skill_name="${${skill_file:h}:t}"
    # Only check skills that use viban workflow commands (add/get/list/assign/move/review/done/comment/sync)
    # Skip skills that only reference viban for installation/version checks
    if grep -qE 'viban (add|get|list|assign|move|review|done|comment|sync)' "$skill_file"; then
        run_test
        if grep -q '## CLI Reference' "$skill_file"; then
            pass "$skill_name: has CLI Reference section"
        else
            fail "$skill_name: CLI Reference" \
                "## CLI Reference section present" \
                "not found"
        fi
    fi
done

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
