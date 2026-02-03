# viban

**Vi**sual Kan**ban** - Terminal-based Kanban board TUI for AI-human collaborative issue tracking.

[![CI](https://github.com/happy-nut/claude-plugin-viban/actions/workflows/ci.yml/badge.svg)](https://github.com/happy-nut/claude-plugin-viban/actions/workflows/ci.yml)
[![npm version](https://badge.fury.io/js/%40happy-nut%2Fclaude-plugin-viban.svg)](https://www.npmjs.com/package/@happy-nut/claude-plugin-viban)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## Features

- **3-Column Kanban Board**: `backlog` → `in_progress` → `review` → `done`
- **Priority Levels**: P0 (critical) to P3 (low priority)
- **Type Tags**: bug, feat, chore, refactor, docs, test
- **TUI Navigation**: Interactive terminal UI with gum
- **Parallel Sessions**: Multiple Claude Code sessions can work simultaneously
- **Session Assignment**: Prevents duplicate work across parallel agents
- **Claude Code Integration**: Built-in skills for automated issue resolution

## Requirements

- zsh
- [gum](https://github.com/charmbracelet/gum) - `brew install gum`
- [jq](https://jqlang.github.io/jq/) - `brew install jq`

## Installation

### Via npm (Recommended)

```bash
npm install -g claude-plugin-viban
```

After installation, `viban` command is automatically available in your terminal.

**Verify installation:**
```bash
viban help
```

### Shell Setup (if viban command not found)

If `viban` is not found after npm install, add npm global bin to your PATH:

**For zsh (macOS default):**
```bash
# Add to ~/.zshrc
export PATH="$PATH:$(npm config get prefix)/bin"

# Reload
source ~/.zshrc
```

**For bash:**
```bash
# Add to ~/.bashrc
export PATH="$PATH:$(npm config get prefix)/bin"

# Reload
source ~/.bashrc
```

### Manual Installation

```bash
git clone https://github.com/happy-nut/claude-plugin-viban.git
cd claude-plugin-viban
chmod +x bin/viban scripts/check-deps.sh

# Option 1: Symlink to /usr/local/bin
ln -s "$(pwd)/bin/viban" /usr/local/bin/viban

# Option 2: Add to PATH
echo 'export PATH="$PATH:'$(pwd)'/bin"' >> ~/.zshrc
source ~/.zshrc
```

### Claude Code Plugin

To use viban skills in Claude Code:

```bash
# Add as plugin marketplace
/plugin marketplace add https://github.com/happy-nut/claude-plugin-viban

# Install the plugin
/plugin install viban

# Now you can use:
/viban:assign
/viban:todo
```

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
viban list                              # Display kanban board
viban add "Title" "Description" P2 feat # Create new issue
viban assign [session-id]               # Assign top backlog issue
viban review [id]                       # Move issue to review
viban done <id>                         # Mark issue as done
viban get <id>                          # Get issue details (JSON)
viban help                              # Show help message
```

**Examples:**

```bash
# Add a high-priority bug
viban add "Fix login error" "Users cannot login after password reset" P1 bug

# List all issues
viban list

# Assign first backlog issue to current session
viban assign

# Mark issue #5 as done
viban done 5

# Get issue details as JSON
viban get 3
```

### Claude Code Integration

viban provides two skills for automated issue management in Claude Code:

#### `/viban:assign` - Auto-resolve next issue

Automatically picks the highest priority backlog issue and executes the full resolution workflow:

1. Fetches top backlog issue
2. Assigns to current session
3. Analyzes and implements the fix
4. Marks as review/done upon completion

**Use cases:**
- Autonomous issue resolution
- Parallel agent workflows
- Pre-prioritized backlog processing

#### `/viban:todo` - Create structured issue

Analyzes a problem and creates a properly structured viban issue:

1. Prompts for problem description
2. Analyzes symptoms, root cause, expected behavior
3. Creates issue with proper title, description, priority, type

**Use cases:**
- Bug reporting
- Feature requests
- Converting free-form descriptions to structured issues

## Configuration

### Data Location (viban.json)

viban stores issues in `viban.json` with the following priority:

| Priority | Location | When Used |
|----------|----------|-----------|
| 1 | `$VIBAN_DATA_DIR` | Explicit override via environment variable |
| 2 | `.git/` (git common dir) | In a git repository (shared across worktrees) |
| 3 | `.viban/` | Non-git directories (fallback) |

**Why Git Common Dir?**
- Shared across git worktrees (parallel work sessions)
- Survives branch switches
- Single source of truth for the repository

**For Non-Git Projects:**
```bash
# viban will automatically create .viban/viban.json in current directory
cd /path/to/non-git-project
viban add "First issue" "Description" P2 feat
# Creates: /path/to/non-git-project/.viban/viban.json
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
- No manual setup required

### Issue Status Flow

```
backlog → in_progress → review → done
            ↑              ↑
      (assign)       (complete)
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
| **docs** | Documentation updates |
| **test** | Test additions/fixes |

## Data Structure

Issues are stored in `viban.json`:

```json
{
  "version": 1,
  "issues": [
    {
      "id": 1,
      "title": "Fix authentication bug",
      "description": "Users cannot login after password reset",
      "status": "in_progress",
      "priority": "P1",
      "type": "bug",
      "assigned_to": "session-abc123",
      "created_at": "2025-01-23T10:00:00Z",
      "updated_at": "2025-01-23T14:30:00Z"
    }
  ]
}
```

## Parallel Session Handling

Multiple Claude Code sessions can work simultaneously:

1. Each session calls `/viban:assign`
2. Session ID is recorded in `assigned_to` field
3. Other sessions skip already-assigned issues
4. Completion moves issue to `review` or `done`

This prevents duplicate work and enables parallel agent workflows.

## File Structure

```
claude-plugin-viban/
├── .claude-plugin/
│   └── plugin.json          # Plugin metadata
├── .github/
│   └── workflows/
│       ├── ci.yml           # CI testing
│       └── release.yml      # NPM publishing
├── bin/
│   └── viban                # Main TUI/CLI script
├── commands/                # Claude Code commands (deprecated)
├── docs/
│   └── CLAUDE.md            # Claude Code integration guide
├── scripts/
│   └── check-deps.sh        # Dependency checker
├── skills/
│   ├── assign/              # /viban:assign skill
│   └── todo/                # /viban:todo skill
├── LICENSE                  # MIT License
├── package.json             # NPM package config
└── README.md                # This file
```

## Development

### Running Tests

```bash
# Install dependencies
brew install gum jq

# Make executable
chmod +x bin/viban scripts/check-deps.sh

# Run tests
./bin/viban help

# Test in a git repo
cd /path/to/git/repo
viban add "Test issue" "Test description" P2 feat
viban list
```

### Publishing

```bash
# Update version in package.json
npm version patch  # or minor, major

# Create and push tag
git tag v1.0.1
git push origin v1.0.1

# GitHub Actions will automatically publish to npm
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

- [npm package](https://www.npmjs.com/package/@happy-nut/claude-plugin-viban)
- [Documentation](https://github.com/happy-nut/claude-plugin-viban/tree/main/docs)
- [Issues](https://github.com/happy-nut/claude-plugin-viban/issues)
