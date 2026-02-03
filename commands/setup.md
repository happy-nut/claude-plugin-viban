---
description: "Install viban dependencies (zsh, gum, jq) automatically"
---

# /setup - Install Dependencies

Automatically install all viban dependencies based on the operating system.

## Execution Steps

### Step 1: Detect OS and Package Manager

```bash
# Detect OS
if [[ "$OSTYPE" == "darwin"* ]]; then
    OS="macos"
    PKG_MANAGER="brew"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OS="linux"
    if command -v apt &> /dev/null; then
        PKG_MANAGER="apt"
    elif command -v dnf &> /dev/null; then
        PKG_MANAGER="dnf"
    elif command -v pacman &> /dev/null; then
        PKG_MANAGER="pacman"
    fi
fi
```

Report detected OS and package manager to user.

### Step 2: Check Existing Dependencies

Check which dependencies are already installed:

```bash
command -v zsh &> /dev/null && echo "✓ zsh" || echo "✗ zsh"
command -v gum &> /dev/null && echo "✓ gum" || echo "✗ gum"
command -v jq &> /dev/null && echo "✓ jq" || echo "✗ jq"
command -v viban &> /dev/null && echo "✓ viban" || echo "✗ viban"
```

### Step 3: Install Missing Dependencies

For each missing dependency, run the appropriate install command:

#### macOS (Homebrew)

```bash
# Install Homebrew if not present
if ! command -v brew &> /dev/null; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# Install dependencies
brew install zsh gum jq
```

#### Linux (apt - Debian/Ubuntu)

```bash
# Install zsh and jq
sudo apt update
sudo apt install -y zsh jq

# Install gum (requires Charm repo)
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg
echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | sudo tee /etc/apt/sources.list.d/charm.list
sudo apt update
sudo apt install -y gum
```

#### Linux (dnf - Fedora/RHEL)

```bash
sudo dnf install -y zsh jq

# Install gum
echo '[charm]
name=Charm
baseurl=https://repo.charm.sh/yum/
enabled=1
gpgcheck=1
gpgkey=https://repo.charm.sh/yum/gpg.key' | sudo tee /etc/yum.repos.d/charm.repo
sudo dnf install -y gum
```

#### Linux (pacman - Arch)

```bash
sudo pacman -S --noconfirm zsh jq gum
```

### Step 4: Install viban CLI

```bash
npm install -g claude-plugin-viban
```

### Step 5: Verify Installation

```bash
viban help
```

If successful, show:

```
╭─────────────────────────────────────╮
│      viban setup complete! 🎉       │
╰─────────────────────────────────────╯

All dependencies installed:
  ✓ zsh
  ✓ gum
  ✓ jq
  ✓ viban

You can now use:
  viban              Open TUI board
  viban add "task"   Add a task
  viban list         List all tasks
  /assign            Auto-resolve next issue
  /task              Create structured issue
```

## Error Handling

- **Homebrew not found on macOS**: Prompt user to install Homebrew first
- **sudo required on Linux**: Inform user that admin privileges are needed
- **Package manager not found**: Show manual installation instructions
- **npm not found**: Install Node.js first

## Notes

- This command requires terminal access to run shell commands
- On Linux, sudo password may be required
- All commands are idempotent (safe to run multiple times)
