---
name: assign
description: "Assign and resolve first backlog issue from viban board through to PR completion"
---

# /assign

Workflow: First backlog issue → Resolve → PR completion

> **No direct `viban.json` access** — CLI only
> **No Worktree** — Work directly on branch in main repo
> **Workflow**: Read CLAUDE.md first, follow project workflow if exists

---

## Phase 0: CONTEXT & SETUP

### 0.1 Read Project Workflow (CRITICAL)

**Before any work, read the project's CLAUDE.md:**

```bash
# Check for CLAUDE.md at common locations
for path in "./CLAUDE.md" "./.claude/CLAUDE.md" "../CLAUDE.md"; do
    [ -f "$path" ] && cat "$path"
done
```

**Look for:**
- `Issue Resolution Workflow` section
- `Workflow` or `Development Process` section
- Specific steps like `ultrawork`, `code-simplifier`, `code-review`
- Testing requirements (`pytest`, manual verification, etc.)

**IMPORTANT:**
- If project has a defined workflow → **MUST follow it exactly**
- If no workflow found → Use default workflow (Phase 1 below)

### 0.2 Git Setup

```bash
# 1. Check for uncommitted changes
if [ -n "$(git status --porcelain)" ]; then
    echo "Warning: Uncommitted changes detected"
    # → Ask user whether to commit (use AskUserQuestion)
fi

# 2. Switch to main branch and sync
git checkout main
git fetch origin main
git reset --hard origin/main

# 3. Assign issue (state change only, no worktree)
ISSUE_ID=$(viban assign 2>&1 | tail -1)
if [ -z "$ISSUE_ID" ] || [ "$ISSUE_ID" = "No backlog" ]; then
    echo "No issues in backlog"
    exit 0
fi

# 4. Create new branch
git checkout -b viban-$ISSUE_ID
```

**If backlog is empty**: Notify user and exit

---

## Phase 1: ANALYZE → VERIFY

```bash
viban get $ISSUE_ID
```

### If Project Workflow Exists (from CLAUDE.md):

**Follow the project's exact steps.** Common patterns include:

1. Root cause analysis (5 Whys)
2. Context verification (ask if unclear)
3. Implementation & verification strategy
4. Code implementation (`/ultrawork` for 2+ files)
5. **Manual verification** (browser/API, NOT pytest)
6. Code simplification (`/code-simplifier`)
7. Code review (`/code-review`)

### Default Workflow (if no project workflow):

1. **Understand**: Read the issue, understand the problem
2. **Locate**: Find relevant code files
3. **Analyze**: Determine root cause
4. **Implement**: Make minimal, focused changes
5. **Verify**: Test the fix works (appropriate method for the project)
6. **Review**: Self-review changes for quality

---

## Phase 2: SHIP

### 2.1 Rebase

```bash
git fetch origin main
git rebase origin/main
# On conflict: resolve → git add → git rebase --continue
```

### 2.2 Commit & Push

```bash
git add -A
git commit -m "fix: issue title summary

- Root cause: ...
- Solution: ...

Resolves: viban-$ISSUE_ID"

git push -u origin viban-$ISSUE_ID
```

### 2.3 Create PR

```bash
EXISTING_PR=$(gh pr list --head viban-$ISSUE_ID --json number -q '.[0].number')
[ -z "$EXISTING_PR" ] && gh pr create \
    --title "viban-$ISSUE_ID: title" \
    --body "## Changes
- ...

## Testing
- [ ] Tests passing (if applicable)
- [ ] Manual verification (if applicable)" \
    --base main
```

### 2.4 Issue → review

```bash
viban review $ISSUE_ID
```

---

## Phase 3: HANDOFF

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Human Review Required
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Issue #$ISSUE_ID → review status

PR: gh pr view viban-$ISSUE_ID --web

Verification complete:
   - Project workflow followed
   - Changes tested appropriately
   - Code reviewed

After approval: Delete issue from viban TUI

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## Checklist

```
[ ] Read CLAUDE.md for project workflow
[ ] Working on viban-$ISSUE_ID branch
[ ] Project workflow steps completed (or default if none)
[ ] Rebase complete
[ ] PR pushed
[ ] viban review executed
```

---

## CLI Reference

| Command | Description |
|---------|-------------|
| `viban` | Open TUI |
| `viban list` | Print board |
| `viban assign [session]` | Assign issue |
| `viban get <id>` | View issue |
| `viban review <id>` | Move to review |
