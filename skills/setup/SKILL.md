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
command -v python3 &> /dev/null && echo "✓ python3" || echo "✗ python3"
command -v gum &> /dev/null && echo "✓ gum" || echo "✗ gum"
command -v jq &> /dev/null && echo "✓ jq" || echo "✗ jq"
command -v viban &> /dev/null && echo "✓ viban ($(viban --version 2>/dev/null || echo 'not installed'))" || echo "✗ viban"
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

### Step 4: Install or Update viban CLI

```bash
npm install -g claude-plugin-viban@latest
```

This installs viban if not present, or updates to the latest version if already installed.

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
  ✓ python3
  ✓ gum
  ✓ jq
  ✓ viban

You can now use:
  viban              Open TUI board
  viban add "task"   Add a task
  viban list         List all tasks
  /viban:assign      Auto-resolve next issue
  /viban:add         Create structured issue
```

### Step 6: Workflow Setup Introduction

After dependencies are installed, explain to the user:

```
╭──────────────────────────────────────────────────╮
│         Workflow Setup (Optional)                 │
╰──────────────────────────────────────────────────╯

/viban:assign uses your project's .viban/workflow.md
as the TOP PRIORITY when resolving issues.

Without a workflow, a default 4-step process is used.
Let's set up a custom workflow for this project now.
```

Ask the user with AskUserQuestion whether they want to configure a workflow now or skip.

- **"Configure workflow"** → Continue to Step 7
- **"Skip"** → End setup

### Step 7: Auto-detect Project Configuration

Before interviewing, automatically gather project context. Do NOT ask the user about things you can detect.

**7.1 Detect build/test commands:**

```bash
# Check package.json scripts
[ -f package.json ] && cat package.json | jq '.scripts' 2>/dev/null

# Check for common build systems
[ -f Makefile ] && echo "Makefile found"
[ -f pyproject.toml ] && echo "pyproject.toml found"
[ -f Cargo.toml ] && echo "Cargo.toml found"
[ -f go.mod ] && echo "go.mod found"
```

Determine the appropriate build/test command from the detected files.

**7.2 Detect existing conventions from git history:**

```bash
# Recent commit messages to infer commit style
git log --oneline -20 2>/dev/null

# Branch naming patterns
git branch -r 2>/dev/null | head -20
```

**7.3 Detect project type and verification methods:**

Infer from file structure (e.g. `src/components/` = frontend, `routes/` or `controllers/` = backend API, `bin/` = CLI).

Store all detected values internally. These will be used in Step 9 to populate the workflow template without asking the user.

### Step 8: Workflow Interview

Ask only what the agent **cannot infer on its own**. One AskUserQuestion call, 3 questions. Everything else uses smart defaults or auto-detection.

**Q1. Pipeline**
- header: "Pipeline"
- question: "After `/viban:assign`, how far should the agent go?"
- options:
  - "Full auto — analyze → implement → commit → PR → review"
  - "Stop before PR — I'll review the diff then create PR myself"
  - "Stop before commit — I'll review the code before anything ships"
  - "Plan only — analyze and propose a plan, I'll implement"
- multiSelect: false

**Q2. Issue Numbering**
- header: "Issue ID"
- question: "How should issues be numbered when using `/viban:add`?"
- options:
  - "Auto — viban auto-assigns #1, #2, #3..."
  - "Manual — ask for an external ID each time (e.g. PROJ-42, JIRA-123)"
- multiSelect: false

**Q3. Extra Rules**
- header: "Rules"
- question: "Any additional rules the agent should follow? (e.g. commit conventions, language, CHANGELOG)"
- options:
  - "No, auto-detect everything"
  - "Let me describe"
- multiSelect: false
- If user selects "Let me describe", collect free-text.

**Defaults for everything else (do NOT ask):**

| Setting | Default | How to override |
|---------|---------|-----------------|
| Commit/PR conventions | Auto-detected from `git log` history | Q3 free-text or edit `.viban/workflow.md` |
| Analysis depth | Agent decides per issue priority/complexity | Edit `.viban/workflow.md` |
| Implementation approach | Agent decides per issue type | Edit `.viban/workflow.md` |
| Quality gates | Build/tests pass + manual verification | Edit `.viban/workflow.md` |
| Test evidence | Test output logs in PR body | Q3 free-text or edit file |
| Post-merge | Auto-close issue + delete branch | Edit `.viban/workflow.md` |
| Verification method | Auto-detected from project type | Edit `.viban/workflow.md` |

### Step 9: Generate `.viban/workflow.md`

#### 9.1 Create `.viban/` directory and update `.gitignore`

```bash
mkdir -p .viban
```

Add `.viban` to `.gitignore`:
- If `.gitignore` exists but does not contain `.viban`: append `.viban` to it
- If `.gitignore` does not exist: create it with `.viban`
- If `.gitignore` already contains `.viban`: do nothing

```bash
if [ -f .gitignore ]; then
    grep -qxF '.viban' .gitignore || echo '.viban' >> .gitignore
else
    echo '.viban' > .gitignore
fi
```

#### 9.2 Check for existing workflow

If `.viban/workflow.md` already exists, ask user with AskUserQuestion:
- "A workflow already exists at `.viban/workflow.md`. What would you like to do?"
- Options: "Overwrite with new interview results" / "Keep existing workflow"
- If user chooses to keep: skip generation and end setup.

#### 9.3 Generate workflow file

Combine **auto-detected values** (Step 7) with **interview answers** (Step 8) to write `.viban/workflow.md`.

**Auto-detected values (from Step 7) — do NOT ask user:**

| Value | Detection Source | Example |
|-------|-----------------|---------|
| Build/test command | `package.json`, `Makefile`, `Cargo.toml`, etc. | `npm run build && npm test` |
| Project type | File structure analysis | "Web Frontend (React)" |
| Verification methods | Inferred from project type | "Browser test (Playwright)" for frontend, "CLI output check" for CLI |
| Existing commit style | `git log --oneline -20` | Infer convention from history |
| Branch naming pattern | `git branch -r` | `feat/*`, `fix/*` |

**Interview values (from Step 8) — only 3 questions:**

| Value | Source | Example |
|-------|--------|---------|
| Pipeline | Q1 | "Full auto" or "Stop before PR" |
| Issue numbering | Q2 | "Auto" or "Manual" |
| Extra rules | Q3 | User-typed rules or "None" |

**Workflow generation principles:**
- **Q1 (Pipeline) determines the entire automation structure** — which phases run automatically, where to stop, and whether to create PRs. "Full auto" = no stops + auto PR. "Stop before PR" = auto commit + user creates PR. "Stop before commit" = implement only + user reviews. "Plan only" = analyze only.
- **Q2 (Issue numbering) determines how `/viban:add` handles IDs.** "Auto" = viban auto-assigns `#1`, `#2`. "Manual" = agent asks for an external ID each time and passes `--ext-id` to `viban add`. When manual, commits/PRs reference the external ID instead of `#N`.
- **Q3 (Extra rules) is appended verbatim to the Additional Rules section.** If user mentions conventions, evidence, CHANGELOG, language, etc., incorporate into the relevant phase.
- **Commit/PR conventions are auto-detected from git history** (Step 7.2). If the user overrides via Q3, use the user's preference instead.
- **Everything else uses smart defaults.** Analysis depth, implementation approach, quality gates, verification methods, issue numbering, post-merge — all auto-determined by the agent or set to sensible defaults.
- Use auto-detected values for operational details (commands, tools, paths).
- Write the workflow in concrete, actionable language — not vague principles.

**Generated template:**

```markdown
# Issue Resolution Workflow

> Auto-applied by `/viban:assign`. Generated by `/viban:setup` - edit freely.

## Pipeline

{FROM Q1:}
{- "Full auto": "Analyze → Implement → Verify → Build → Commit → PR → Review (fully autonomous)"}
{- "Stop before PR": "Analyze → Implement → Verify → Build → Commit → STOP (user creates PR)"}
{- "Stop before commit": "Analyze → Implement → STOP (user reviews code, then commits)"}
{- "Plan only": "Analyze → STOP (user decides next steps)"}

---

## Phase 1: Analyze

The agent determines analysis depth based on issue priority and complexity.

1. Read the issue description via `viban get {id}`
2. Explore codebase — approach chosen by agent based on issue context
3. Identify root cause and estimate scope

### Analysis Checklist
- [ ] Issue description fully understood
- [ ] Affected code located and read
- [ ] Root cause identified (or hypothesis formed)
- [ ] Scope of change estimated

{IF Q1 is "Plan only":}
### >>> STOP: Present analysis and proposed plan to user. Wait for approval.

---

## Phase 2: Implement

The agent determines implementation approach based on issue type and priority.

### Testing Requirements
{AUTO_DETECTED from project's test framework}

### Implementation Checklist
- [ ] Changes are focused on the issue scope
- [ ] No unrelated changes mixed in
- [ ] {TESTING_CHECKLIST — based on detected test framework}

{IF Q1 is "Stop before commit":}
### >>> STOP: Present changes to user. Wait for approval before committing.

---

## Phase 3: Verify

Verify the fix works. Build/tests must pass + manual verification.

### Verification Methods
{AUTO_DETECTED based on project type}

### Verification Checklist
- [ ] Fix verified
- [ ] No regressions in adjacent functionality
- [ ] Build and tests passing

---

## Phase 4: Build and Test

```bash
{AUTO_DETECTED build/test command}
```

If build/test fails: fix errors, return to Phase 3.

---

## Phase 5: Ship

### Commit Convention
{AUTO_DETECTED from git history — infer format from existing commits. If Q3 overrides, use that instead.}

### Branch Convention
{AUTO_DETECTED from existing patterns, or `viban-{id}` as default}

### Pull Request
{FROM Q1:}
{- "Full auto": create PR with body template, move issue to review via `viban review {id}`}
{- "Stop before PR": commit and push only, notify user that PR is pending. Run `viban review {id}`.}
{- "Stop before commit" / "Plan only": N/A — agent already stopped earlier}

### PR Body Template
{AUTO_DETECTED from git history convention. If Q3 overrides, use that instead.}

### Ship Checklist
- [ ] Rebased on latest main
- [ ] All commits follow convention
- [ ] `viban review {id}` executed

---

## Issue Management

- Issue numbering: {FROM Q2: "Auto" = auto-increment (viban default), "Manual" = ask for external ID via `--ext-id` flag}
- Test evidence: include test output in PR body
- Post-merge: auto-close issue (`viban done {id}`), delete branch

---

## Additional Rules

{FROM Q3, or "None"}
```

After writing `.viban/workflow.md`, confirm:

```
╭──────────────────────────────────────────────────╮
│  Workflow saved to .viban/workflow.md! ✨         │
╰──────────────────────────────────────────────────╯

.viban/ added to .gitignore
/viban:assign will now follow your custom workflow.
You can edit .viban/workflow.md anytime to adjust it.
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
