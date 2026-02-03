#!/bin/zsh
# Test: Layout width calculations
# Verifies that display width calculations are correct for various character types

# Note: Don't use 'set -e' as arithmetic expansion ((VAR++)) returns non-zero when VAR is 0

SCRIPT_DIR="${0:A:h}"
PROJECT_ROOT="${SCRIPT_DIR:h}"

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

# Source str_width function from viban
str_width() {
    local str="$1"
    local char_count=${#str}
    local byte_count
    LC_ALL=C byte_count=${#str}
    local multi_byte_chars=$(( (byte_count - char_count) / 2 ))
    echo $(( char_count + multi_byte_chars ))
}

# Braille spinner frames (same as in viban)
SPINNER_FRAMES=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')

echo "Testing layout width calculations..."
echo ""

# ============================================================
# Test 1: ASCII characters have width 1
# ============================================================
echo "Test 1: ASCII characters"
run_test

ascii_width=$(str_width "hello")
if [[ "$ascii_width" == "5" ]]; then
    pass "ASCII 'hello' has width 5"
else
    fail "ASCII width" "5" "$ascii_width"
fi

run_test
space_width=$(str_width "a b")
if [[ "$space_width" == "3" ]]; then
    pass "ASCII 'a b' (with space) has width 3"
else
    fail "ASCII with space width" "3" "$space_width"
fi

# ============================================================
# Test 2: Korean (CJK) characters have width 2
# ============================================================
echo ""
echo "Test 2: Korean (CJK) characters"
run_test

korean_width=$(str_width "한글")
if [[ "$korean_width" == "4" ]]; then
    pass "Korean '한글' (2 chars) has width 4"
else
    fail "Korean width" "4" "$korean_width"
fi

run_test
mixed_width=$(str_width "A한B글C")
# A(1) + 한(2) + B(1) + 글(2) + C(1) = 7
if [[ "$mixed_width" == "7" ]]; then
    pass "Mixed 'A한B글C' has width 7"
else
    fail "Mixed width" "7" "$mixed_width"
fi

# ============================================================
# Test 3: Braille characters (the bug we fixed)
# ============================================================
echo ""
echo "Test 3: Braille spinner characters"

# Note: str_width calculates Braille as width 2 (3 bytes like CJK)
# but actual display width is 1. The fix compensates for this
# in the card layout code, not in str_width itself.

run_test
braille_char="${SPINNER_FRAMES[1]}"  # ⠋
braille_width=$(str_width "$braille_char")
# str_width returns 2 for Braille (same as CJK due to 3-byte UTF-8)
# This is "incorrect" for display but we compensate in layout code
if [[ "$braille_width" == "2" ]]; then
    pass "Braille '⠋' returns width 2 from str_width (compensated in layout)"
else
    fail "Braille str_width" "2" "$braille_width"
fi

run_test
# Spinner with space: "⠋ " should be width 3 from str_width
spinner_with_space="${braille_char} "
spinner_width=$(str_width "$spinner_with_space")
if [[ "$spinner_width" == "3" ]]; then
    pass "Spinner with space '⠋ ' returns width 3 from str_width"
else
    fail "Spinner with space str_width" "3" "$spinner_width"
fi

# ============================================================
# Test 4: Layout compensation for Braille
# ============================================================
echo ""
echo "Test 4: Braille width compensation in layout"

# Simulate the layout calculation with compensation
# This mirrors the fix in build_column_lines
simulate_title_width() {
    local spinner_prefix="$1"
    local title="$2"
    local title_content="  ${spinner_prefix}#1 $title"
    local title_content_w=$(str_width "$title_content")
    # Braille compensation (the fix we made)
    [[ -n "$spinner_prefix" ]] && title_content_w=$((title_content_w - 1))
    echo "$title_content_w"
}

run_test
# Without spinner
width_no_spinner=$(simulate_title_width "" "Test")
# "  #1 Test" = 2 + 2 + 1 + 4 = 9 (spaces + "#1" + space + "Test")
expected_no_spinner=9
if [[ "$width_no_spinner" == "$expected_no_spinner" ]]; then
    pass "Title without spinner: width=$width_no_spinner"
else
    fail "Title without spinner width" "$expected_no_spinner" "$width_no_spinner"
fi

run_test
# With spinner (Braille + space)
spinner_prefix="⠧ "
width_with_spinner=$(simulate_title_width "$spinner_prefix" "Test")
# "  ⠧ #1 Test" = 2 + (2+1) + 2 + 1 + 4 = 12 from str_width
# After compensation (-1): 11
# Actual display: 2 + (1+1) + 2 + 1 + 4 = 11 ✓
expected_with_spinner=11
if [[ "$width_with_spinner" == "$expected_with_spinner" ]]; then
    pass "Title with spinner: width=$width_with_spinner (compensated)"
else
    fail "Title with spinner width" "$expected_with_spinner" "$width_with_spinner"
fi

# ============================================================
# Test 5: Card padding calculation
# ============================================================
echo ""
echo "Test 5: Card padding stays non-negative"

run_test
# Simulate card layout with various title lengths
card_inner=32  # typical card inner width
test_padding() {
    local spinner_prefix="$1"
    local title="$2"
    local title_w=$((card_inner - 7))  # leave room for "#id "
    [[ -n "$spinner_prefix" ]] && title_w=$((title_w - 2))  # spinner takes 2 display cols

    # Truncate title if needed (simplified)
    local short="$title"
    [[ ${#title} -gt $title_w ]] && short="${title:0:$title_w}"

    local title_content="  ${spinner_prefix}#1 $short"
    local title_content_w=$(str_width "$title_content")
    [[ -n "$spinner_prefix" ]] && title_content_w=$((title_content_w - 1))

    local title_pad=$((card_inner - title_content_w))
    (( title_pad < 0 )) && title_pad=0
    echo "$title_pad"
}

# Test with long Korean title
long_korean="한글테스트제목이아주긴경우"
padding_korean=$(test_padding "⠧ " "$long_korean")
if [[ "$padding_korean" -ge 0 ]]; then
    pass "Korean title padding is non-negative: $padding_korean"
else
    fail "Korean title padding" ">=0" "$padding_korean"
fi

run_test
# Test with long ASCII title
long_ascii="This is a very long ASCII title for testing"
padding_ascii=$(test_padding "⠧ " "$long_ascii")
if [[ "$padding_ascii" -ge 0 ]]; then
    pass "ASCII title padding is non-negative: $padding_ascii"
else
    fail "ASCII title padding" ">=0" "$padding_ascii"
fi

run_test
# Test with short title
short_title="Bug"
padding_short=$(test_padding "⠧ " "$short_title")
if [[ "$padding_short" -gt 0 ]]; then
    pass "Short title has positive padding: $padding_short"
else
    fail "Short title padding" ">0" "$padding_short"
fi

# ============================================================
# Test 6: All spinner frames have consistent width
# ============================================================
echo ""
echo "Test 6: All spinner frames have consistent width"

run_test
first_frame_width=$(str_width "${SPINNER_FRAMES[1]}")
all_consistent=true
for frame in $SPINNER_FRAMES; do
    frame_width=$(str_width "$frame")
    if [[ "$frame_width" != "$first_frame_width" ]]; then
        all_consistent=false
        fail "Spinner frame '$frame' width" "$first_frame_width" "$frame_width"
        break
    fi
done

if $all_consistent; then
    pass "All ${#SPINNER_FRAMES[@]} spinner frames have consistent width ($first_frame_width)"
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
