#!/bin/bash
# viban dependency checker

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

echo "Checking viban dependencies..."
echo ""

missing=0

check_dep() {
    local name="$1"
    local install_macos="$2"
    local install_linux="$3"

    if command -v "$name" &> /dev/null; then
        echo -e "  ${GREEN}✓${NC} $name"
        return 0
    else
        echo -e "  ${RED}✗${NC} $name not found"
        if [[ "$OSTYPE" == "darwin"* ]]; then
            echo -e "    Install: ${YELLOW}$install_macos${NC}"
        else
            echo -e "    Install: ${YELLOW}$install_linux${NC}"
        fi
        missing=1
        return 1
    fi
}

check_dep "gum" "brew install gum" "See https://github.com/charmbracelet/gum#installation"
check_dep "jq" "brew install jq" "apt install jq"

echo ""
if [[ $missing -eq 1 ]]; then
    echo -e "${YELLOW}Please install missing dependencies for full functionality.${NC}"
    exit 0  # Don't fail npm install
fi

echo -e "${GREEN}All dependencies installed!${NC}"
