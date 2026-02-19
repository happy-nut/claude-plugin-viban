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

### Step 4: Install or Update viban CLI + Auto-detect (Parallel)

Run dependency installation in the **background** while auto-detecting project configuration **in parallel**:

**Background task (install):**

```bash
npm install -g claude-plugin-viban@latest
```

**Parallel task (auto-detect) — run simultaneously:**

Jump to Step 7 (Auto-detect Project Configuration) and start gathering project context while installation proceeds.

Wait for both tasks to complete before continuing to Step 5.

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

Tip: Use /viban:sync to integrate with GitHub Issues.
     Run it anytime to set up two-way sync.
```

### Step 6: Workflow Setup Introduction

After dependencies are installed and auto-detection is complete, explain to the user:

```
╭──────────────────────────────────────────────────╮
│         Workflow Setup (Optional)                │
╰──────────────────────────────────────────────────╯

/viban:assign uses your project's .viban/workflow.md
as the TOP PRIORITY when resolving issues.

Without a workflow, a default process is used:
analyze → implement → verify → ship.
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
  - "Full auto — analyze → implement → commit → PR (review in PR)"
  - "Stop before PR — I'll review the diff first (review in terminal/IDE)"
  - "Stop before commit — I'll review the code first (review in terminal/IDE)"
- multiSelect: false

**Q2. Issue Tracker Sync**
- header: "Sync"
- question: "Sync issues with an external tracker (GitHub Issues, Jira, Linear, etc.)?"
- options:
  - "Yes — set up two-way sync (issues imported from provider)"
  - "No — auto-number locally (#1, #2, #3...)"
  - "No — but use manual external IDs (e.g. PROJ-42)"
- multiSelect: false
- If user selects "Yes", run `viban sync` to initialize sync after workflow setup completes.

**Q3. Extra Rules**

Before asking, show the user what was auto-detected from Step 7:

```
Detected conventions:
  Commit style:  {e.g. "feat: ...", "fix: ..." (Conventional Commits)}
  Branch naming: {e.g. "feat/*", "fix/*"}
  Build command: {e.g. "npm run build && npm test"}
  Project type:  {e.g. "CLI tool (zsh)"}
```

Then ask:

- header: "Rules"
- question: "Anything to change or add to the detected conventions above?"
- options:
  - "Looks good, use as-is"
  - "Let me adjust"
- multiSelect: false
- If user selects "Let me adjust", collect free-text.

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
| Issue tracker sync | Q2 | "Yes (sync)" or "No (auto)" or "No (manual IDs)" |
| Extra rules | Q3 | User-typed rules or "None" |

**Workflow generation principles:**
- **Q1 (Pipeline) determines the entire automation structure** — which phases run automatically, where to stop, and whether to create PRs. "Full auto" = no stops + auto PR. "Stop before PR" = auto commit + user creates PR. "Stop before commit" = implement only + user reviews.
- **Q2 (Issue tracker sync) determines how issues are managed.** "Yes" = run `viban sync` after setup to import/sync issues from external tracker (GitHub, Jira, Linear, etc.), IDs come from provider. "No — auto-number" = viban auto-assigns `#1`, `#2`. "No — manual IDs" = agent asks for an external ID each time and passes `--ext-id` to `viban add`. When manual, commits/PRs reference the external ID instead of `#N`.
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
{AUTO_DETECTED from existing patterns, or `issue-{id}` as default}

### Pull Request
{FROM Q1:}
{- "Full auto": create PR with body template, move issue to review via `viban review {id}`}
{- "Stop before PR": commit and push only, notify user that PR is pending. Run `viban review {id}`.}
{- "Stop before commit": N/A — agent already stopped earlier}

### PR Body Template
{AUTO_DETECTED from git history convention. If Q3 overrides, use that instead.}

### Ship Checklist
- [ ] Rebased on latest main
- [ ] All commits follow convention
- [ ] `viban review {id}` executed

---

## Issue Management

- Issue tracking: {FROM Q2: "Yes" = synced with external tracker via `viban sync`, "No — auto-number" = auto-increment (viban default), "No — manual IDs" = ask for external ID via `--ext-id` flag}
- Test evidence: include test output in PR body
- Post-merge: handled by `/viban:approve` (merges PR, runs `viban done {id}`, deletes branch)

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

## CLI Reference

| Command | Description |
|---------|-------------|
| `viban help` | Show help and verify installation |
| `viban add "<title>"` | Add a task |
| `viban list` | List all tasks |
| `viban sync` | Initialize external tracker sync |

## Notes

- This command requires terminal access to run shell commands
- On Linux, sudo password may be required
- All commands are idempotent (safe to run multiple times)
