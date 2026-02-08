---
name: release
description: "Bump version, commit, tag, and push to trigger npm publish"
---

# /release - Release a new version

Bump the package version, commit, tag, and push to trigger the automated npm publish workflow.

## Execution Steps

### Step 1: Pre-flight checks

```bash
# Ensure on main branch
git branch --show-current  # must be "main"

# Ensure working tree is clean (no uncommitted changes)
git status --porcelain

# Ensure up to date with remote
git fetch origin main
git diff origin/main --stat
```

If not on main, working tree is dirty, or behind remote: **stop and inform user**.

### Step 2: Determine version bump

Read current version from `package.json`:

```bash
grep '"version"' package.json
```

Ask user with AskUserQuestion:
- header: "Version"
- question: "Current version is {current}. What kind of bump?"
- options:
  - "patch" (x.y.Z) - bug fixes, small changes
  - "minor" (x.Y.0) - new features, backward compatible
  - "major" (X.0.0) - breaking changes
- multiSelect: false

Calculate the new version based on selection.

### Step 3: Show changelog preview

Show commits since last tag:

```bash
git log $(git describe --tags --abbrev=0)..HEAD --oneline
```

Display to user for confirmation before proceeding.

### Step 4: Run tests

```bash
zsh tests/run_all.zsh
```

If tests fail: **stop and inform user**. Do not release with failing tests.

### Step 5: Bump version and release

```bash
# Update package.json version
# (use jq or sed to update the version field)

# Commit
git add package.json
git commit -m "{new_version}"

# Tag
git tag v{new_version}

# Push with tags
git push origin main --tags
```

### Step 6: Confirm

```
╭──────────────────────────────────────╮
│  Released v{new_version}!            │
╰──────────────────────────────────────╯

- npm publish: triggered via GitHub Actions
- GitHub Release: auto-generated with release notes

Check: https://github.com/happy-nut/claude-plugin-viban/actions
```

## Error Handling

- **Not on main**: "Switch to main branch first"
- **Dirty working tree**: "Commit or stash changes first"
- **Tests failing**: "Fix failing tests before release"
- **Push failed**: "Check remote access and try again"
