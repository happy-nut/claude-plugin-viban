---
name: setup
description: "Install viban dependencies and configure project workflow via interview"
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

### Step 6: Workflow Setup Introduction

After dependencies are installed, explain to the user:

```
╭──────────────────────────────────────────────────╮
│         Workflow Setup (Optional)                 │
╰──────────────────────────────────────────────────╯

/viban:assign uses your project's CLAUDE.md workflow
as the TOP PRIORITY when resolving issues.

Without a workflow, a default 4-step process is used.
Let's set up a custom workflow for this project now.
```

Ask the user with AskUserQuestion whether they want to configure a workflow now or skip.

- **"Configure workflow"** → Continue to Step 7
- **"Skip"** → End setup

### Step 7: Workflow Interview

Use AskUserQuestion for each question. Collect all answers before generating.

**Q1. Project Type**
- header: "Project"
- options:
  - "Web Frontend" (React, Vue, Svelte, etc.)
  - "Web Backend" (API server, microservice)
  - "CLI / Library"
  - "Fullstack" (frontend + backend)
- multiSelect: false

**Q2. Build & Test Command**
- header: "Build/Test"
- options:
  - "`npm run build && npm test`"
  - "`pnpm build && pnpm test`"
  - "`pytest`"
  - "`cargo build && cargo test`"
- multiSelect: false
- (User can select "Other" to type a custom command)

**Q3. Verification Method**
- header: "Verify"
- options:
  - "Browser test (Playwright / Chrome DevTools)"
  - "API endpoint test (curl / WebFetch)"
  - "CLI output check"
  - "No manual verification (tests are enough)"
- multiSelect: true

**Q4. Commit Convention**
- header: "Commits"
- options:
  - "Conventional Commits (`feat:`, `fix:`, `chore:`, etc.)"
  - "Free-form messages"
- multiSelect: false
- (User can select "Other" to type a custom convention)

**Q5. Additional Rules (Optional)**
- Ask with AskUserQuestion:
  - header: "Rules"
  - question: "Any additional project-specific rules? (e.g. 'always update CHANGELOG', 'use Korean commit messages')"
  - options:
    - "No additional rules"
    - "Let me type rules"
  - multiSelect: false
- If user selects "Let me type rules", collect their free-text input.

### Step 8: Generate CLAUDE.md Workflow

Based on interview answers, generate (or append to) the project root `CLAUDE.md`.

**If CLAUDE.md does not exist**: Create it with the workflow section.
**If CLAUDE.md exists but has no `## Issue Resolution Workflow`**: Append the section.
**If CLAUDE.md already has `## Issue Resolution Workflow`**: Ask user whether to overwrite or skip.

Generated template:

```markdown
## Issue Resolution Workflow

> This workflow is automatically applied when running `/viban:assign`.

### Step 1: Analyze
- Read issue description via `viban get {id}`
- Find relevant code files
- Understand the root cause

### Step 2: Implement
- Make minimal, focused changes
- {ADDITIONAL_RULES from Q5, if any}

### Step 3: Verify
- {VERIFICATION_METHODS from Q3}

### Step 4: Build & Test
- Run: `{BUILD_TEST_COMMAND from Q2}`

### Step 5: Commit & PR
- Commit convention: {CONVENTION from Q4}
- Create PR via `gh pr create`

### Step 6: Complete
- Run `viban review {id}` to move to human review
```

**Template variable mapping:**

| Variable | Source | Example |
|----------|--------|---------|
| `{VERIFICATION_METHODS}` | Q3 answers joined as bullet list | `- Browser test with Playwright` |
| `{BUILD_TEST_COMMAND}` | Q2 answer | `npm run build && npm test` |
| `{CONVENTION}` | Q4 answer | `Conventional Commits (feat:, fix:, etc.)` |
| `{ADDITIONAL_RULES}` | Q5 answer (omit line if empty) | `- Always update CHANGELOG.md` |

After writing CLAUDE.md, confirm:

```
╭──────────────────────────────────────────────────╮
│     Workflow saved to CLAUDE.md! ✨              │
╰──────────────────────────────────────────────────╯

/viban:assign will now follow your custom workflow.
You can edit CLAUDE.md anytime to adjust it.
```

---

## Error Handling

- **Homebrew not found on macOS**: Prompt user to install Homebrew first
- **sudo required on Linux**: Inform user that admin privileges are needed
- **Package manager not found**: Show manual installation instructions
- **npm not found**: Install Node.js first

## Notes

- This command requires terminal access to run shell commands
- On Linux, sudo password may be required
- All commands are idempotent (safe to run multiple times)
