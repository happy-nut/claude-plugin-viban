# viban

**Vi**sual Kan**ban** - A simple, lightweight local Kanban board for AI-human collaborative issue tracking.

[![CI](https://github.com/happy-nut/claude-plugin-viban/actions/workflows/ci.yml/badge.svg)](https://github.com/happy-nut/claude-plugin-viban/actions/workflows/ci.yml)
[![npm version](https://badge.fury.io/js/claude-plugin-viban.svg)](https://www.npmjs.com/package/claude-plugin-viban)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

![viban](assets/viban.png)

## Why viban?

- **Lightweight & Fast** - Pure shell script with minimal dependencies. Starts instantly.
- **Local First** - Your issues stay in your repo. No external services or accounts needed.
- **AI-Native** - Built for Claude Code integration from the ground up.
- **Parallel Worktrees** - Resolve multiple issues simultaneously via isolated git worktrees.

## Recommended Workflow

![recommended workflow](assets/screenshot.png)

**Sequential mode** — multiple terminal sessions, one issue at a time:

```
┌───────────────────┐  ┌───────────────────┐  ┌───────────────────┐
│    Session 1      │  │    Session 2      │  │    Session 3      │
│                   │  │                   │  │                   │
│  Product QA       │  │  Issue Work       │  │  viban TUI        │
│  + /viban:add     │  │  + /viban:assign  │  │                   │
│                   │  │                   │  │  (always open)    │
│  Find bugs,       │  │  Pick & resolve   │  │  Monitor board    │
│  register issues  │  │  issues           │  │  in real-time     │
└───────────────────┘  └───────────────────┘  └───────────────────┘
```

**Parallel mode** — resolve multiple issues at once with `/viban:parallel-assign`:

```
┌───────────────────┐
│   Coordinator     │  /viban:parallel-assign 3
│                   │
│  Assigns issues,  │──┬──────────────────────────────────────┐
│  creates worktrees│  │                                      │
│  collects results │  ▼                  ▼                   ▼
│                   │  ┌──────────┐  ┌──────────┐  ┌──────────┐
│                   │  │ Agent 1  │  │ Agent 2  │  │ Agent 3  │
│                   │  │ wt/#12   │  │ wt/#13   │  │ wt/#14   │
│                   │  │ Analyze  │  │ Analyze  │  │ Analyze  │
│                   │  │ Implement│  │ Implement│  │ Implement│
│                   │  │ Commit   │  │ Commit   │  │ Commit   │
│  Push, create PRs │  └──────────┘  └──────────┘  └──────────┘
│  Run tests, report│
└───────────────────┘
```

- Each agent works in an isolated git worktree (`.viban/worktrees/{ID}`)
- Zero interference between agents — no merge conflicts
- Coordinator pushes branches, creates PRs, and runs tests after all agents finish

## Features

- **3-Column Kanban Board**: `backlog` → `in_progress` → `review` (done moves to history)
- **Priority Levels**: P0 (critical) to P3 (low priority)
- **Type Tags**: bug, feat, chore, refactor
- **TUI Navigation**: Interactive terminal UI with gum
- **Issue Comments**: Timestamped progress notes on issues
- **Issue Dependencies**: Block/unblock relationships between issues
- **Sub-tasks**: Parent-child issue decomposition with progress tracking
- **Filter & Search**: Filter by status, priority, type, or search text
- **Board Export**: Export board as markdown table or standalone HTML
- **Backup & Restore**: Snapshot and recover viban.json
- **Issue Templates**: Default values per issue type via `.viban/templates.json`
- **Dry-run Mode**: Preview destructive operations before executing
- **Auto Changelog**: Generate changelogs from conventional commits
- **Statistics**: Throughput metrics, cycle time, and board summary
- **GitHub Sync**: Two-way sync with GitHub Issues (comments, dependencies, sub-tasks)
- **Parallel Sessions**: Multiple Claude Code sessions can work simultaneously
- **Session Assignment**: Prevents duplicate work across parallel agents

## Requirements

- zsh
- python3 (macOS/Linux built-in)
- [gum](https://github.com/charmbracelet/gum)
- [jq](https://jqlang.github.io/jq/)
- [gh](https://cli.github.com/) (optional, for GitHub Issues sync)

> **Tip:** If using Claude Code, run `/viban:setup` to install all dependencies automatically.

## Installation

### For Claude Code Users

```bash
/plugin marketplace add https://github.com/happy-nut/claude-plugin-viban
/plugin install viban
/viban:setup   # Installs all dependencies automatically
```

### For Terminal Users

```bash
curl -fsSL https://raw.githubusercontent.com/happy-nut/claude-plugin-viban/main/install.sh | bash
```

Or via npm (requires zsh, gum, jq pre-installed):
```bash
npm install -g claude-plugin-viban
```

<details>
<summary>Troubleshooting: viban command not found</summary>

Add npm global bin to your PATH:
```bash
# For zsh
echo 'export PATH="$PATH:$(npm config get prefix)/bin"' >> ~/.zshrc && source ~/.zshrc

# For bash
echo 'export PATH="$PATH:$(npm config get prefix)/bin"' >> ~/.bashrc && source ~/.bashrc
```
</details>

## Usage

### TUI (Interactive Mode)

```bash
viban           # Launch TUI
```

**Navigation:**

| Level | Screen | Controls |
|-------|--------|----------|
| 1 | Column List | ↑↓ select, Enter to enter |
| 2 | Card List | ↑↓ select, Enter for details, `a` to add |
| 3 | Card Details | Change status, delete |

**TUI Features:**
- Navigate between backlog, in_progress, review, done columns
- View issue cards with priority and type badges
- Create new issues with rich descriptions
- Move issues between statuses
- Delete issues

### CLI Commands

```bash
# Board & Listing
viban list                                          # Display kanban board
viban list [--status <s>] [--priority P0,P1] [--type bug] [--search text]
viban history                                       # Show completed issues
viban stats                                         # Throughput metrics and statistics
viban export [md|html]                              # Export board as markdown or HTML

# Issue Management
viban add "Title" ["Desc"] [P0-P3] [type] [--parent <id>]  # Create issue
viban edit <id>                                     # Edit issue in editor
viban get <id>                                      # Get issue details (JSON)
viban priority <id> <P0-P3>                         # Set priority
viban attach <id> <file1> [file2...]                # Attach files to issue
viban comment <id> "msg"                            # Add comment to issue

# Workflow
viban assign                                        # Assign top backlog issue
viban review [id]                                   # Move issue to review
viban move <id> <status>                            # Move to any status
viban done <id> [--purge] [--dry-run]               # Complete (--purge to delete)

# Dependencies & Sub-tasks
viban link <id> blocks <id>                         # Add dependency
viban unlink <id> blocks <id> [--dry-run]           # Remove dependency

# Sync & Maintenance
viban sync                                          # Sync with GitHub Issues
viban backup                                        # Snapshot viban.json
viban restore [filename]                            # List or restore a backup
viban changelog [range]                             # Generate changelog from commits
viban migrate                                       # Migrate: extract type from title
viban update                                        # Update to latest version
```

**Examples:**

```bash
# Add a high-priority bug
viban add "Fix login error" "Users cannot login after password reset" P1 bug

# Add a sub-task under issue #5
viban add "Implement auth middleware" --parent 5

# Add a comment to track progress
viban comment 3 "Investigated root cause: null pointer in auth handler"

# Block issue #4 until issue #3 is done
viban link 3 blocks 4

# Filter issues
viban list --priority P0,P1                  # Show critical and high priority
viban list --type bug --status backlog       # Show backlog bugs
viban list --search "auth"                   # Search by text

# Preview before deleting
viban done 5 --purge --dry-run

# Export board for a PR description
viban export md > board.md

# Generate changelog for a release
viban changelog v1.3.11..v1.3.12
```

### Issue Templates

Create `.viban/templates.json` to define defaults per issue type:

```json
{
  "bug": {
    "priority": "P1",
    "description": "## Bug Report\n\n**Steps to reproduce:**\n\n**Expected:**\n\n**Actual:**"
  },
  "feat": {
    "priority": "P2",
    "description": "## Feature\n\n**User story:**\n\n**Acceptance criteria:**"
  }
}
```

When creating an issue with a matching type, unset fields are filled from the template:
```bash
viban add "Login crash" --type bug
# Priority defaults to P1, description defaults to bug template
```

### Claude Code Integration

viban provides skills and commands for automated issue management in Claude Code:

#### `/viban:add` - Register structured issue

Analyzes a problem and creates a properly structured viban issue:

1. Clarifies the problem if vague
2. Infers priority and type from description
3. Registers with proper title, description, priority, type
4. Optionally enters plan mode to design a solution

**Use cases:**
- Bug reporting
- Feature requests
- Converting free-form descriptions to structured issues

#### `/viban:assign` - Assign next backlog issue

Picks the highest priority backlog issue and assigns it to the current session:

1. Assigns top backlog issue (skips blocked issues)
2. Evaluates description clarity
3. If unclear, interviews user and enriches the issue description

This command is **assignment only** - it does not start implementation. Use your project's workflow (`.viban/workflow.md`) to define what happens next.

#### `/viban:parallel-assign` - Parallel resolution with worktrees

Resolves multiple backlog issues simultaneously using isolated git worktrees:

1. Assigns N issues (default: 3, max: 5) and creates worktrees
2. Spawns one opus agent per issue in its own worktree
3. Each agent analyzes, implements, commits, and creates a PR
4. Coordinator collects results, runs tests, and cleans up

**Use cases:**
- Batch processing a backlog
- Parallel agent workflows with zero interference
- Rapid issue throughput

#### `/viban:setup` - Install & configure

Installs all dependencies and optionally configures a project workflow:

1. Detects OS and installs missing dependencies (zsh, gum, jq)
2. Installs/updates viban CLI via npm
3. Auto-detects project conventions (build/test, commit style, branch naming)
4. Interviews for workflow preferences (pipeline depth, issue numbering)
5. Generates `.viban/workflow.md` for `/viban:assign` to follow

## External Tracker Sync

viban can sync two-way with external issue trackers. Currently supported: **GitHub Issues**.

### Quick Start

```bash
# First time: initialize sync (auto-detects provider from git remote)
viban sync --init

# Preview what will change
viban sync --dry-run

# Run sync
viban sync

# Push local-only issues to GitHub
viban sync --push-new
```

> **Tip:** Use `viban sync --dry-run` first to preview changes before syncing.

### How It Works

- **First sync** imports all open remote issues as backlog cards with external IDs (e.g. `github:42`)
- **Subsequent syncs** pull remote changes and push local status updates
- **New local cards** are NOT pushed unless `--push-new` is specified (local-first default)
- **Conflicts** (both sides changed) resolve to remote-wins by default
- **Comments** are pushed from viban to GitHub (tracked to avoid duplicates)
- **Dependencies** (`blocked_by`) and **sub-tasks** are rendered in the GitHub issue body

### Status-to-Label Mapping

| viban status | GitHub label |
|-------------|-------------|
| `backlog` | *(no label)* |
| `in_progress` | `in-progress` |
| `review` | `review` |
| `done` | *(issue closed)* |

### Requirements

- [gh CLI](https://cli.github.com/) installed and authenticated (`gh auth login`)
- Repository must have a GitHub remote

## Configuration

### Data Location (viban.json)

viban stores issues in `viban.json` with the following priority:

| Priority | Location | When Used |
|----------|----------|-----------|
| 1 | `$VIBAN_DATA_DIR` | Explicit override via environment variable |
| 2 | `.viban/` | Default (all projects) |

**Auto-Migration:** If viban detects `viban.json` or `sync.json` in `.git/` (legacy location), it automatically moves them to `.viban/`.

**For Any Project:**
```bash
# viban will automatically create .viban/viban.json in current directory
cd /path/to/project
viban add "First issue" "Description" P2 feat
# Creates: /path/to/project/.viban/viban.json
```

**Custom Data Directory:**
```bash
export VIBAN_DATA_DIR="/path/to/shared/data"
viban list  # Uses /path/to/shared/data/viban.json
```

### Auto-Initialization

viban automatically initializes when first used:
- Creates data directory if not exists
- Creates `viban.json` with empty issue list
- Validates JSON structure on load (version, issues array, required fields)
- No manual setup required

### Issue Status Flow

```
backlog → in_progress → review → done
   ↑           ↑           │
   └───────────┴───────────┘
        (viban move)
```

### Priority Levels

| Priority | Description |
|----------|-------------|
| **P0** | Critical - blocks all work |
| **P1** | High - must do soon |
| **P2** | Medium - normal priority |
| **P3** | Low - nice to have |

### Type Tags

| Type | Use Case |
|------|----------|
| **bug** | Fixing broken functionality |
| **feat** | New feature or enhancement |
| **refactor** | Code restructuring |
| **chore** | Maintenance tasks |

## Data Structure

Issues are stored in `.viban/viban.json`:

```json
{
  "version": 2,
  "next_id": 4,
  "issues": [
    {
      "id": 1,
      "title": "Fix authentication bug",
      "description": "Users cannot login after password reset",
      "status": "in_progress",
      "priority": "P1",
      "type": "bug",
      "assigned_to": "session-abc123",
      "parent_id": null,
      "blocked_by": [3],
      "comments": [
        {"text": "Root cause found", "created_at": "2026-01-23T14:00:00Z"}
      ],
      "attachments": [],
      "created_at": "2026-01-23T10:00:00Z",
      "updated_at": "2026-01-23T14:30:00Z"
    }
  ]
}
```

## Parallel Session Handling

Multiple Claude Code sessions can work simultaneously:

1. Each session calls `/viban:assign`
2. Session ID is recorded in `assigned_to` field
3. Other sessions skip already-assigned and blocked issues
4. Completion moves issue to `review` or `done`

This prevents duplicate work and enables parallel agent workflows.

## File Structure

```
claude-plugin-viban/
├── .claude-plugin/
│   └── plugin.json              # Plugin metadata
├── .github/
│   └── workflows/
│       ├── ci.yml               # CI testing + shellcheck linting
│       └── release.yml          # NPM publishing
├── bin/
│   └── viban                    # Main entry point (dispatch + init)
├── lib/
│   ├── config.zsh               # Colors, labels, borders, ANSI codes
│   ├── helpers.zsh              # Data ops, sorting, JSON validation
│   ├── tui.zsh                  # TUI rendering, coprocess, editor
│   └── commands.zsh             # All cmd_* CLI command implementations
├── commands/
│   ├── add.md                   # /viban:add command
│   ├── assign.md                # /viban:assign command
│   ├── parallel-assign.md       # /viban:parallel-assign command
│   └── setup.md                 # /viban:setup command
├── skills/
│   ├── add/SKILL.md             # /viban:add skill
│   ├── assign/SKILL.md          # /viban:assign skill
│   ├── parallel-assign/SKILL.md # /viban:parallel-assign skill
│   └── setup/SKILL.md           # /viban:setup skill
├── scripts/
│   ├── check-deps.sh            # Dependency checker
│   ├── generate-release-notes.sh # Release notes generator
│   ├── sync.sh                  # Core sync engine (provider-agnostic)
│   ├── sync_create.sh           # Auto-create remote issue on add
│   ├── providers/
│   │   └── github.sh            # GitHub Issues provider
│   └── tui_coprocess.py         # Python coprocess for Unicode width
├── tests/                       # 19 test suites, 212 tests
│   ├── run_all.zsh              # Test runner
│   ├── test_cmd_add.zsh         # Add command tests
│   ├── test_cmd_add_dup.zsh     # Duplicate detection tests
│   ├── test_cmd_backup.zsh      # Backup/restore tests
│   ├── test_cmd_comment.zsh     # Comment tests
│   ├── test_cmd_done.zsh        # Done/archive tests
│   ├── test_cmd_history.zsh     # History/archive tests
│   ├── test_cmd_link.zsh        # Dependency link/unlink tests
│   ├── test_cmd_move.zsh        # Status move tests
│   ├── test_cmd_stats.zsh       # Statistics tests
│   ├── test_cmd_subtask.zsh     # Sub-task tests
│   ├── test_coprocess.zsh       # Python coprocess tests
│   ├── test_install.zsh         # Installation tests
│   ├── test_integration.zsh     # Cross-feature integration tests
│   ├── test_layout.zsh          # TUI layout tests
│   ├── test_pad_width.zsh       # Unicode width tests
│   ├── test_sort_order.zsh      # Sort order tests
│   ├── test_sync.zsh            # Sync engine tests
│   ├── test_sync_auto.zsh       # Auto-sync tests
│   └── test_sync_fields.zsh     # Sync new fields tests
├── docs/
│   ├── CLAUDE.md                # Claude Code integration guide
│   └── release.md               # Release workflow
├── LICENSE                      # MIT License
├── package.json                 # NPM package config
└── README.md                    # This file
```

## Development

### Running Tests

```bash
# Install dependencies
brew install gum jq

# Run the full test suite (19 suites, 212 tests)
zsh tests/run_all.zsh
```

### Publishing

See [docs/release.md](docs/release.md) for the full release workflow.

```bash
# GitHub Actions will automatically publish to npm on tag push
```

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Author

**happy-nut**

- GitHub: [@happy-nut](https://github.com/happy-nut)
- Repository: [claude-plugin-viban](https://github.com/happy-nut/claude-plugin-viban)

## Links

- [npm package](https://www.npmjs.com/package/claude-plugin-viban)
- [Documentation](https://github.com/happy-nut/claude-plugin-viban/tree/main/docs)
- [Issues](https://github.com/happy-nut/claude-plugin-viban/issues)
