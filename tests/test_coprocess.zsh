#!/bin/zsh
# Test: Python coprocess for TUI rendering
# Verifies the tui_coprocess.py protocol, correctness, and lifecycle

# Note: Don't use 'set -e' as arithmetic expansion ((VAR++)) returns non-zero when VAR is 0

SCRIPT_DIR="${0:A:h}"
PROJECT_ROOT="${SCRIPT_DIR:h}"
COPROC_SCRIPT="$PROJECT_ROOT/scripts/tui_coprocess.py"

# Test counter
TESTS_RUN=0
TESTS_PASSED=0

pass() {
    ((TESTS_PASSED++))
    echo "  ✓ $1"
}

fail() {
    ((TESTS_PASSED+=0))  # no-op to avoid issues
    echo "  ✗ $1"
    echo "    Expected: $2"
    echo "    Got: $3"
}

run_test() {
    ((TESTS_RUN++))
}

echo "Testing Python coprocess (tui_coprocess.py)..."
echo ""

# ============================================================
# Test 1: BATCH_TRUNC - ASCII strings
# ============================================================
echo "Test 1: BATCH_TRUNC with ASCII strings"

run_test
result=$(echo -e "BATCH_TRUNC\n5\t\thello world\nEND\nQUIT" | python3 "$COPROC_SCRIPT")
expected=$'hello\t5\nEND'
if [[ "$result" == "$expected" ]]; then
    pass "ASCII truncate 'hello world' to max 5 → 'hello' width=5"
else
    fail "ASCII truncate" "$expected" "$result"
fi

run_test
result=$(echo -e "BATCH_TRUNC\n3\t\tabcde\nEND\nQUIT" | python3 "$COPROC_SCRIPT")
expected=$'abc\t3\nEND'
if [[ "$result" == "$expected" ]]; then
    pass "ASCII truncate 'abcde' to max 3 → 'abc' width=3"
else
    fail "ASCII truncate to 3" "$expected" "$result"
fi

run_test
# String already fits - no truncation needed
result=$(echo -e "BATCH_TRUNC\n10\t\thi\nEND\nQUIT" | python3 "$COPROC_SCRIPT")
expected=$'hi\t2\nEND'
if [[ "$result" == "$expected" ]]; then
    pass "ASCII no truncation needed: 'hi' max=10 → 'hi' width=2"
else
    fail "ASCII no truncation" "$expected" "$result"
fi

# ============================================================
# Test 2: BATCH_TRUNC - CJK (Korean) strings
# ============================================================
echo ""
echo "Test 2: BATCH_TRUNC with CJK strings"

run_test
# '한글테스트' = 5 chars, each width 2, total width 10
# max_w=5 → '한글' (width 4) fits, '한글테' would be 6 > 5
result=$(echo -e "BATCH_TRUNC\n5\t\t한글테스트\nEND\nQUIT" | python3 "$COPROC_SCRIPT")
expected=$'한글\t4\nEND'
if [[ "$result" == "$expected" ]]; then
    pass "Korean truncate '한글테스트' to max 5 → '한글' width=4"
else
    fail "Korean truncate" "$expected" "$result"
fi

run_test
# max_w=3 → '한' (width 2) fits, '한글' would be 4 > 3
result=$(echo -e "BATCH_TRUNC\n3\t\t한글테스트\nEND\nQUIT" | python3 "$COPROC_SCRIPT")
expected=$'한\t2\nEND'
if [[ "$result" == "$expected" ]]; then
    pass "Korean truncate '한글테스트' to max 3 → '한' width=2"
else
    fail "Korean truncate to 3" "$expected" "$result"
fi

run_test
# max_w=1 → CJK char needs 2, so nothing fits
result=$(echo -e "BATCH_TRUNC\n1\t\t한글\nEND\nQUIT" | python3 "$COPROC_SCRIPT")
expected=$'\t0\nEND'
if [[ "$result" == "$expected" ]]; then
    pass "Korean truncate to max 1 → empty (CJK needs width 2)"
else
    fail "Korean truncate to 1" "$expected" "$result"
fi

# ============================================================
# Test 3: BATCH_TRUNC - Mixed ASCII + CJK
# ============================================================
echo ""
echo "Test 3: BATCH_TRUNC with mixed ASCII + CJK"

run_test
# 'A한B' = A(1)+한(2)+B(1) = width 4
# max_w=3 → 'A한' (width 3) fits
result=$(echo -e "BATCH_TRUNC\n3\t\tA한B글C\nEND\nQUIT" | python3 "$COPROC_SCRIPT")
expected=$'A한\t3\nEND'
if [[ "$result" == "$expected" ]]; then
    pass "Mixed 'A한B글C' to max 3 → 'A한' width=3"
else
    fail "Mixed truncate" "$expected" "$result"
fi

# ============================================================
# Test 4: BATCH_TRUNC - Prefix included in width calculation
# ============================================================
echo ""
echo "Test 4: BATCH_TRUNC with prefix"

run_test
# prefix "  " (2 spaces) + truncated text "hi" → content width = 4
result=$(echo -e "BATCH_TRUNC\n10\t  \thi there\nEND\nQUIT" | python3 "$COPROC_SCRIPT")
# "hi there" fits in max 10, width of "  hi there" = 10
expected=$'hi there\t10\nEND'
if [[ "$result" == "$expected" ]]; then
    pass "Prefix '  ' + 'hi there' (fits) → width=10"
else
    fail "Prefix width" "$expected" "$result"
fi

run_test
# prefix "  #1 " (5 chars) + truncated Korean text
# max_w=4 → '한글' (width 4) fits
# content width = prefix "  #1 " (5) + "한글" (4) = 9
result=$(echo -e "BATCH_TRUNC\n4\t  #1 \t한글테스트\nEND\nQUIT" | python3 "$COPROC_SCRIPT")
expected=$'한글\t9\nEND'
if [[ "$result" == "$expected" ]]; then
    pass "Prefix '  #1 ' + Korean truncate → '한글' content_width=9"
else
    fail "Prefix + Korean" "$expected" "$result"
fi

# ============================================================
# Test 5: BATCH_TRUNC - Multiple lines (batch)
# ============================================================
echo ""
echo "Test 5: BATCH_TRUNC batch processing"

run_test
result=$(echo -e "BATCH_TRUNC\n5\t\thello world\n4\t\t한글테스트\n3\t\tabc\nEND\nQUIT" | python3 "$COPROC_SCRIPT")
expected=$'hello\t5\n한글\t4\nabc\t3\nEND'
if [[ "$result" == "$expected" ]]; then
    pass "Batch of 3 lines processed correctly"
else
    fail "Batch processing" "$expected" "$result"
fi

# ============================================================
# Test 6: BATCH_WIDTH - ASCII strings
# ============================================================
echo ""
echo "Test 6: BATCH_WIDTH with ASCII strings"

run_test
result=$(echo -e "BATCH_WIDTH\nhello\nworld\nEND\nQUIT" | python3 "$COPROC_SCRIPT")
expected=$'5\n5\nEND'
if [[ "$result" == "$expected" ]]; then
    pass "ASCII widths: 'hello'=5, 'world'=5"
else
    fail "ASCII widths" "$expected" "$result"
fi

# ============================================================
# Test 7: BATCH_WIDTH - CJK strings
# ============================================================
echo ""
echo "Test 7: BATCH_WIDTH with CJK strings"

run_test
result=$(echo -e "BATCH_WIDTH\n한글\n테스트\nEND\nQUIT" | python3 "$COPROC_SCRIPT")
expected=$'4\n6\nEND'
if [[ "$result" == "$expected" ]]; then
    pass "Korean widths: '한글'=4, '테스트'=6"
else
    fail "Korean widths" "$expected" "$result"
fi

run_test
# Mixed: 'A한B' = 1+2+1 = 4
result=$(echo -e "BATCH_WIDTH\nA한B\nEND\nQUIT" | python3 "$COPROC_SCRIPT")
expected=$'4\nEND'
if [[ "$result" == "$expected" ]]; then
    pass "Mixed 'A한B' width=4"
else
    fail "Mixed width" "$expected" "$result"
fi

# ============================================================
# Test 8: BATCH_WIDTH - Special characters
# ============================================================
echo ""
echo "Test 8: BATCH_WIDTH with special characters"

run_test
# Box drawing: each char is width 1
result=$(echo -e "BATCH_WIDTH\n─────\nEND\nQUIT" | python3 "$COPROC_SCRIPT")
expected=$'5\nEND'
if [[ "$result" == "$expected" ]]; then
    pass "Box drawing '─────' width=5"
else
    fail "Box drawing width" "$expected" "$result"
fi

run_test
# Braille: width 1
result=$(echo -e "BATCH_WIDTH\n⠋\nEND\nQUIT" | python3 "$COPROC_SCRIPT")
expected=$'1\nEND'
if [[ "$result" == "$expected" ]]; then
    pass "Braille '⠋' width=1"
else
    fail "Braille width" "$expected" "$result"
fi

run_test
# Empty string
result=$(echo -e "BATCH_WIDTH\n\nEND\nQUIT" | python3 "$COPROC_SCRIPT")
expected=$'0\nEND'
if [[ "$result" == "$expected" ]]; then
    pass "Empty string width=0"
else
    fail "Empty string width" "$expected" "$result"
fi

# ============================================================
# Test 9: Multiple sequential commands (coprocess stays alive)
# ============================================================
echo ""
echo "Test 9: Multiple sequential commands"

run_test
result=$(echo -e "BATCH_WIDTH\nhello\nEND\nBATCH_WIDTH\n한글\nEND\nBATCH_TRUNC\n3\t\tabcde\nEND\nQUIT" | python3 "$COPROC_SCRIPT")
expected=$'5\nEND\n4\nEND\nabc\t3\nEND'
if [[ "$result" == "$expected" ]]; then
    pass "3 sequential commands processed correctly"
else
    fail "Sequential commands" "$expected" "$result"
fi

# ============================================================
# Test 10: Coprocess lifecycle via explicit FIFOs (matches bin/viban)
# ============================================================
echo ""
echo "Test 10: Coprocess lifecycle (start/stop/no zombie)"

run_test
# Start coprocess with explicit file descriptors
local _test_in_fifo=$(mktemp -u /tmp/viban_test_in.XXXXXX)
local _test_out_fifo=$(mktemp -u /tmp/viban_test_out.XXXXXX)
mkfifo "$_test_in_fifo" "$_test_out_fifo"
python3 "$COPROC_SCRIPT" < "$_test_in_fifo" > "$_test_out_fifo" &
local COPROC_TEST_PID=$!
exec 7>"$_test_in_fifo" 8<"$_test_out_fifo"
rm -f "$_test_in_fifo" "$_test_out_fifo"

# Verify it's running
if kill -0 "$COPROC_TEST_PID" 2>/dev/null; then
    pass "Coprocess started (PID=$COPROC_TEST_PID)"
else
    fail "Coprocess start" "running" "not running"
fi

run_test
# Send a command and verify response via fd 7/8
echo "BATCH_WIDTH" >&7
echo "test" >&7
echo "END" >&7
local resp=""
while read -r line <&8; do
    [[ "$line" == "END" ]] && break
    resp+="$line"
done
if [[ "$resp" == "4" ]]; then
    pass "Coprocess responds via pipe: width('test')=4"
else
    fail "Coprocess pipe response" "4" "$resp"
fi

run_test
# Send QUIT and verify process terminates
echo "QUIT" >&7
exec 7>&- 2>/dev/null
sleep 0.1
if ! kill -0 "$COPROC_TEST_PID" 2>/dev/null; then
    pass "Coprocess terminated after QUIT (no zombie)"
else
    # Clean up if still running
    kill "$COPROC_TEST_PID" 2>/dev/null
    wait "$COPROC_TEST_PID" 2>/dev/null
    fail "Coprocess termination" "terminated" "still running"
fi
exec 8<&- 2>/dev/null

# ============================================================
# Test 11: BATCH_TRUNC edge cases
# ============================================================
echo ""
echo "Test 11: BATCH_TRUNC edge cases"

run_test
# max_w=0 → nothing fits
result=$(echo -e "BATCH_TRUNC\n0\t\thello\nEND\nQUIT" | python3 "$COPROC_SCRIPT")
expected=$'\t0\nEND'
if [[ "$result" == "$expected" ]]; then
    pass "max_w=0 → empty string, width=0"
else
    fail "max_w=0" "$expected" "$result"
fi

run_test
# Empty text
result=$(echo -e "BATCH_TRUNC\n5\t\t\nEND\nQUIT" | python3 "$COPROC_SCRIPT")
expected=$'\t0\nEND'
if [[ "$result" == "$expected" ]]; then
    pass "Empty text → empty, width=0"
else
    fail "Empty text" "$expected" "$result"
fi

run_test
# Large max_w - no truncation
result=$(echo -e "BATCH_TRUNC\n100\t\thello\nEND\nQUIT" | python3 "$COPROC_SCRIPT")
expected=$'hello\t5\nEND'
if [[ "$result" == "$expected" ]]; then
    pass "Large max_w (100) → no truncation, 'hello' width=5"
else
    fail "Large max_w" "$expected" "$result"
fi

# ============================================================
# Test 12: Consistency with direct Python width calculation
# ============================================================
echo ""
echo "Test 12: Coprocess matches direct Python width"

# Direct Python width function for comparison
direct_width() {
    python3 -c "
import unicodedata, sys
s = sys.stdin.read().rstrip('\n')
print(sum(2 if unicodedata.east_asian_width(c) in 'FW' else 1 for c in s))
" <<< "$1"
}

test_strings=("hello" "한글테스트" "A한B글C" "⠋ Loading..." "─── Title ───")
all_match=true

for s in "${test_strings[@]}"; do
    run_test
    coproc_w=$(echo -e "BATCH_WIDTH\n${s}\nEND\nQUIT" | python3 "$COPROC_SCRIPT")
    coproc_w=${coproc_w%%$'\n'END}  # strip trailing END
    direct_w=$(direct_width "$s")

    if [[ "$coproc_w" == "$direct_w" ]]; then
        pass "Width match for '${s}': ${coproc_w}"
    else
        all_match=false
        fail "Width mismatch for '${s}'" "$direct_w" "$coproc_w"
    fi
done

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
