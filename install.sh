#!/bin/bash
# viban - One-liner installer
# Usage: curl -fsSL https://raw.githubusercontent.com/happy-nut/claude-plugin-viban/main/install.sh | bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

echo ""
echo -e "${BOLD}${BLUE}╭─────────────────────────────────────╮${NC}"
echo -e "${BOLD}${BLUE}│         viban installer             │${NC}"
echo -e "${BOLD}${BLUE}╰─────────────────────────────────────╯${NC}"
echo ""

# Detect OS
OS="unknown"
PKG_MANAGER=""

if [[ "$OSTYPE" == "darwin"* ]]; then
    OS="macos"
    if command -v brew &> /dev/null; then
        PKG_MANAGER="brew"
    else
        echo -e "${RED}Error: Homebrew is required on macOS${NC}"
        echo -e "Install it first: ${YELLOW}/bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"${NC}"
        exit 1
    fi
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OS="linux"
    if command -v apt &> /dev/null; then
        PKG_MANAGER="apt"
    elif command -v dnf &> /dev/null; then
        PKG_MANAGER="dnf"
    elif command -v pacman &> /dev/null; then
        PKG_MANAGER="pacman"
    else
        echo -e "${RED}Error: No supported package manager found (apt, dnf, pacman)${NC}"
        exit 1
    fi
else
    echo -e "${RED}Error: Unsupported OS: $OSTYPE${NC}"
    exit 1
fi

echo -e "${GREEN}✓${NC} Detected: $OS ($PKG_MANAGER)"

# Install system dependencies
install_pkg() {
    local name="$1"

    if command -v "$name" &> /dev/null; then
        echo -e "${GREEN}✓${NC} $name already installed"
        return 0
    fi

    echo -e "${YELLOW}→${NC} Installing $name..."

    case "$PKG_MANAGER" in
        brew)
            brew install "$name"
            ;;
        apt)
            sudo apt update -qq
            sudo apt install -y "$name"
            ;;
        dnf)
            sudo dnf install -y "$name"
            ;;
        pacman)
            sudo pacman -S --noconfirm "$name"
            ;;
    esac

    echo -e "${GREEN}✓${NC} $name installed"
}

# Install gum (special case for Linux - needs Charm repo)
install_gum() {
    if command -v gum &> /dev/null; then
        echo -e "${GREEN}✓${NC} gum already installed"
        return 0
    fi

    echo -e "${YELLOW}→${NC} Installing gum..."

    case "$PKG_MANAGER" in
        brew)
            brew install gum
            ;;
        apt)
            # Add Charm repository
            sudo mkdir -p /etc/apt/keyrings
            curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg 2>/dev/null || true
            echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | sudo tee /etc/apt/sources.list.d/charm.list > /dev/null
            sudo apt update -qq
            sudo apt install -y gum
            ;;
        dnf)
            echo '[charm]
name=Charm
baseurl=https://repo.charm.sh/yum/
enabled=1
gpgcheck=1
gpgkey=https://repo.charm.sh/yum/gpg.key' | sudo tee /etc/yum.repos.d/charm.repo > /dev/null
            sudo dnf install -y gum
            ;;
        pacman)
            sudo pacman -S --noconfirm gum
            ;;
    esac

    echo -e "${GREEN}✓${NC} gum installed"
}

echo ""
echo -e "${BOLD}Installing dependencies...${NC}"
echo ""

# Install zsh (required for viban script)
install_pkg "zsh"

# Install jq
install_pkg "jq"

# Install gum
install_gum

# Check for npm
echo ""
if ! command -v npm &> /dev/null; then
    echo -e "${YELLOW}→${NC} Installing Node.js..."
    case "$PKG_MANAGER" in
        brew)
            brew install node
            ;;
        apt)
            curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
            sudo apt install -y nodejs
            ;;
        dnf)
            sudo dnf install -y nodejs
            ;;
        pacman)
            sudo pacman -S --noconfirm nodejs npm
            ;;
    esac
    echo -e "${GREEN}✓${NC} Node.js installed"
else
    echo -e "${GREEN}✓${NC} npm already installed"
fi

# Install viban via npm
echo ""
echo -e "${BOLD}Installing viban...${NC}"
echo ""

npm install -g claude-plugin-viban

echo ""
echo -e "${GREEN}✓${NC} viban installed globally"

# Register Claude Code plugin
echo ""
echo -e "${BOLD}Registering Claude Code plugin...${NC}"
echo ""

CLAUDE_CONFIG_DIR="${HOME}/.claude"
CLAUDE_PLUGINS_FILE="${CLAUDE_CONFIG_DIR}/plugins.json"

mkdir -p "$CLAUDE_CONFIG_DIR"

# Get npm global prefix to find viban
NPM_PREFIX=$(npm prefix -g)
VIBAN_PLUGIN_DIR="${NPM_PREFIX}/lib/node_modules/claude-plugin-viban"

# Check if plugins.json exists
if [[ -f "$CLAUDE_PLUGINS_FILE" ]]; then
    # Check if viban is already registered
    if jq -e '.plugins[] | select(.name == "viban")' "$CLAUDE_PLUGINS_FILE" > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Plugin already registered"
    else
        # Add viban to existing plugins
        jq --arg path "$VIBAN_PLUGIN_DIR" '.plugins += [{"name": "viban", "path": $path}]' "$CLAUDE_PLUGINS_FILE" > "${CLAUDE_PLUGINS_FILE}.tmp"
        mv "${CLAUDE_PLUGINS_FILE}.tmp" "$CLAUDE_PLUGINS_FILE"
        echo -e "${GREEN}✓${NC} Plugin registered"
    fi
else
    # Create new plugins.json
    cat > "$CLAUDE_PLUGINS_FILE" << EOF
{
  "plugins": [
    {
      "name": "viban",
      "path": "$VIBAN_PLUGIN_DIR"
    }
  ]
}
EOF
    echo -e "${GREEN}✓${NC} Plugin registered"
fi

echo ""
echo -e "${BOLD}${GREEN}╭─────────────────────────────────────╮${NC}"
echo -e "${BOLD}${GREEN}│      Installation complete! 🎉      │${NC}"
echo -e "${BOLD}${GREEN}╰─────────────────────────────────────╯${NC}"
echo ""
echo -e "Usage:"
echo -e "  ${YELLOW}viban${NC}              Open TUI board"
echo -e "  ${YELLOW}viban add \"task\"${NC}   Add a task"
echo -e "  ${YELLOW}viban list${NC}         List all tasks"
echo -e "  ${YELLOW}viban help${NC}         Show all commands"
echo ""
echo -e "In Claude Code, the plugin is now available."
echo ""
