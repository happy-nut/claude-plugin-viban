#!/bin/zsh
# Run all viban tests

SCRIPT_DIR="${0:A:h}"
cd "$SCRIPT_DIR"

echo "╭─────────────────────────────────────╮"
echo "│       VIBAN Test Suite              │"
echo "╰─────────────────────────────────────╯"
echo ""

TOTAL_FAILED=0

for test_file in test_*.zsh; do
    echo "▶ Running $test_file"
    echo "─────────────────────────────────────"
    if ./"$test_file"; then
        echo ""
    else
        ((TOTAL_FAILED++))
        echo ""
    fi
done

echo "═════════════════════════════════════"
if [[ $TOTAL_FAILED -eq 0 ]]; then
    echo "✓ All test suites passed!"
    exit 0
else
    echo "✗ $TOTAL_FAILED test suite(s) failed"
    exit 1
fi
