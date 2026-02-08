#!/bin/zsh
# Test: pad_to_width batch width calculation accuracy
setopt EXTENDED_GLOB

SCRIPT_DIR="${0:A:h}"
PROJECT_ROOT="${SCRIPT_DIR:h}"

TESTS_RUN=0
TESTS_PASSED=0

pass() { ((TESTS_PASSED++)); echo "  ✓ $1"; }
fail() { ((TESTS_PASSED+=0)); echo "  ✗ $1"; echo "    Expected: $2"; echo "    Got: $3"; }
run_test() { ((TESTS_RUN++)); }

_ESC=$'\e'

strip_ansi() {
    local s="$1"
    # Use sed for reliable ANSI stripping
    printf '%s' "$s" | sed $'s/\e\\[[0-9;]*[a-zA-Z]//g'
}

str_width() {
    local str="$1"
    local char_count=${#str}
    local byte_count
    LC_ALL=C byte_count=${#str}
    unset LC_ALL
    [[ $byte_count -eq $char_count ]] && { echo $char_count; return; }
    python3 -c "
import unicodedata, sys
s = sys.stdin.read().rstrip('\n')
print(sum(2 if unicodedata.east_asian_width(c) in 'FW' else 1 for c in s))
" <<< "$str"
}

pad_to_width() {
    local line="$1" width="$2" precomputed_w="${3:-}"
    local plain=$(strip_ansi "$line")
    local display_w
    if [[ -n "$precomputed_w" ]]; then
        display_w=$precomputed_w
    else
        display_w=$(str_width "$plain")
    fi
    local pad=$((width - display_w))
    printf '%s' "$line"
    (( pad > 0 )) && printf "%${pad}s" ""
}

# Batch compute widths - strip ANSI, then measure
batch_compute_widths() {
    local -a input_lines=("$@")
    local -a plains widths
    local needs_python=0

    local i plain cc byte_cnt
    for ((i=1; i<=${#input_lines[@]}; i++)); do
        plain=$(strip_ansi "${input_lines[$i]}")
        plains+=("$plain")
        cc=${#plain}
        LC_ALL=C byte_cnt=${#plain}
        unset LC_ALL
        if [[ $byte_cnt -eq $cc ]]; then
            widths+=($cc)
        else
            widths+=(-1)
            needs_python=1
        fi
    done

    if (( needs_python )); then
        local py_input=""
        for ((i=1; i<=${#plains[@]}; i++)); do
            if [[ ${widths[$i]} -eq -1 ]]; then
                py_input+="${plains[$i]}"$'\n'
            fi
        done
        local -a py_results
        py_results=("${(@f)$(python3 -c "
import unicodedata,sys
for line in sys.stdin.read().rstrip('\n').split('\n'):
    print(sum(2 if unicodedata.east_asian_width(c) in 'FW' else 1 for c in line))
" <<< "$py_input")}")
        local pi=1
        for ((i=1; i<=${#widths[@]}; i++)); do
            if [[ ${widths[$i]} -eq -1 ]]; then
                widths[$i]=${py_results[$pi]}
                ((pi++))
            fi
        done
    fi

    echo "${widths[@]}"
}

echo "Testing pad_to_width batch computation..."
echo ""

# ============================================================
# Test 1: ASCII-only lines
# ============================================================
echo "Test 1: ASCII-only lines"
run_test
result=$(batch_compute_widths "hello" "world" "test")
if [[ "$result" == "5 5 4" ]]; then
    pass "ASCII widths: $result"
else
    fail "ASCII widths" "5 5 4" "$result"
fi

# ============================================================
# Test 2: Box-drawing characters (width 1 each)
# ============================================================
echo ""
echo "Test 2: Box-drawing characters"
run_test
result=$(batch_compute_widths " ╭──────╮ " " │ test │ " " ╰──────╯ ")
if [[ "$result" == "10 10 10" ]]; then
    pass "Box-drawing widths: $result"
else
    fail "Box-drawing widths" "10 10 10" "$result"
fi

# ============================================================
# Test 3: Korean text (width 2 per char)
# ============================================================
echo ""
echo "Test 3: Korean text"
run_test
result=$(batch_compute_widths "한글" "ABC" "테스트")
if [[ "$result" == "4 3 6" ]]; then
    pass "Mixed Korean/ASCII widths: $result"
else
    fail "Mixed Korean/ASCII widths" "4 3 6" "$result"
fi

# ============================================================
# Test 4: Mixed Korean + box-drawing in single line
# ============================================================
echo ""
echo "Test 4: Mixed Korean + box-drawing"
run_test
line=" │  #1 한글 테스트│ "
expected_w=$(str_width "$line")
result=$(batch_compute_widths "$line")
if [[ "$result" == "$expected_w" ]]; then
    pass "Mixed line width: $result (matches str_width)"
else
    fail "Mixed line width" "$expected_w" "$result"
fi

# ============================================================
# Test 5: ANSI codes are stripped before width calculation
# ============================================================
echo ""
echo "Test 5: ANSI codes stripped"
run_test
ansi_line=$'\e[1mhello\e[0m'
result=$(batch_compute_widths "$ansi_line")
if [[ "$result" == "5" ]]; then
    pass "ANSI-wrapped 'hello' width: $result"
else
    fail "ANSI-wrapped width" "5" "$result"
fi

run_test
ansi_korean=$'\e[2m│\e[0m\e[1m  한글\e[0m   \e[2m│\e[0m'
expected_w=$(str_width "│  한글   │")
result=$(batch_compute_widths "$ansi_korean")
if [[ "$result" == "$expected_w" ]]; then
    pass "ANSI Korean card line width: $result"
else
    fail "ANSI Korean card line width" "$expected_w" "$result"
fi

# ============================================================
# Test 6: pad_to_width output has exact target width
# ============================================================
echo ""
echo "Test 6: pad_to_width produces exact width"
run_test
target_w=40
output=$(pad_to_width "hello" $target_w 5)
output_w=$(str_width "$output")
if [[ "$output_w" == "$target_w" ]]; then
    pass "ASCII padded to $target_w: actual=$output_w"
else
    fail "ASCII pad_to_width" "$target_w" "$output_w"
fi

run_test
korean="한글테스트"
korean_w=$(str_width "$korean")
output=$(pad_to_width "$korean" $target_w "$korean_w")
output_w=$(str_width "$output")
if [[ "$output_w" == "$target_w" ]]; then
    pass "Korean padded to $target_w: actual=$output_w"
else
    fail "Korean pad_to_width" "$target_w" "$output_w"
fi

run_test
boxline=" ╭──────────╮ "
box_w=$(str_width "$boxline")
output=$(pad_to_width "$boxline" $target_w "$box_w")
output_w=$(str_width "$output")
if [[ "$output_w" == "$target_w" ]]; then
    pass "Box-drawing padded to $target_w: actual=$output_w"
else
    fail "Box-drawing pad_to_width" "$target_w" "$output_w"
fi

# ============================================================
# Test 7: Batch vs individual str_width consistency
# ============================================================
echo ""
echo "Test 7: Batch matches individual str_width"
run_test
lines=(
    " ╭────────────────────────────────╮ "
    " │  #147 백테스트 차트 on-demand │ "
    " │  주가 차트에서 과거 데이터를  │ "
    " │  [P3] [FEAT]                   │ "
    " ╰────────────────────────────────╯ "
)
batch_result=$(batch_compute_widths "${lines[@]}")
batch_arr=(${=batch_result})

all_match=true
for ((i=1; i<=${#lines[@]}; i++)); do
    plain="${lines[$i]//${_ESC}\[[0-9;]#[a-zA-Z]/}"
    individual=$(str_width "$plain")
    if [[ "${batch_arr[$i]}" != "$individual" ]]; then
        all_match=false
        fail "Line $i batch vs str_width" "$individual" "${batch_arr[$i]}"
        break
    fi
done

if $all_match; then
    pass "All ${#lines[@]} lines: batch matches str_width"
fi

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
