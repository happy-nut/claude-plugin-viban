---
description: "Assign and resolve first backlog issue from viban board through to PR completion"
---

# /assign

Workflow: First backlog issue -> Resolve -> PR completion

> **No direct `viban.json` access** - CLI only
> **No Worktree** - Work directly on branch in main repo
> **Workflow**: Read `.viban/workflow.md` first, then CLAUDE.md fallback

---

## Phase 0: CONTEXT & SETUP

### 0.1 Read Project Workflow (CRITICAL)

Before any work, read the project's workflow configuration. Check in priority order:

**Priority 1: `.viban/workflow.md`** (dedicated workflow file)

```bash
[ -f ".viban/workflow.md" ] && cat ".viban/workflow.md"
```

**Priority 2: CLAUDE.md** (legacy fallback)

Only if `.viban/workflow.md` does NOT exist:

```bash
for path in "./CLAUDE.md" "./.claude/CLAUDE.md" "../CLAUDE.md"; do
    [ -f "$path" ] && cat "$path"
done
```

Look for: `Issue Resolution Workflow` or `Workflow` section.

**Priority 3: Default workflow** (Phase 1 below)

IMPORTANT:
- If `.viban/workflow.md` exists -> MUST follow it exactly (all phases)
- Else if CLAUDE.md has a workflow section -> MUST follow it exactly
- If no workflow found -> Use default workflow (Phase 1 below)

### 0.2 Git Setup

```bash
# 1. Check for uncommitted changes
if [ -n "$(git status --porcelain)" ]; then
    echo "Warning: Uncommitted changes detected"
    # Ask user whether to commit (use AskUserQuestion)
fi

# 2. Switch to main branch and sync
git checkout main
git fetch origin main
git reset --hard origin/main

# 3. Assign issue
ISSUE_ID=$(viban assign 2>&1 | tail -1)
if [ -z "$ISSUE_ID" ] || [ "$ISSUE_ID" = "No backlog" ]; then
    echo "No issues in backlog"
    exit 0
fi

# 4. Create new branch
git checkout -b viban-$ISSUE_ID
```

If backlog is empty: Notify user and exit

---

## Phase 1: ANALYZE & IMPLEMENT

```bash
viban get $ISSUE_ID
```

### If Project Workflow Exists (from `.viban/workflow.md` or CLAUDE.md):

Follow the project's exact steps.

### Default Workflow (if no project workflow):

1. **Understand**: Read the issue, understand the problem
2. **Locate**: Find relevant code files
3. **Analyze**: Determine root cause
4. **Implement**: Make minimal, focused changes

---

## Phase 2: VERIFY

Manual verification using available tools. Do NOT run build/test here - save that for Phase 3.

### Verification Methods (use what's appropriate):

| Type | Tool | Usage |
|------|------|-------|
| Web UI | Playwright MCP | `browser_navigate`, `browser_snapshot`, `browser_click` |
| API | WebFetch | Fetch endpoints, check responses |
| CLI | Bash | Run the CLI command, check output |
| Visual | Read | Read screenshot files if provided |
| Browser | Chrome DevTools MCP | `take_snapshot`, `navigate_page`, `click` |

### Verification Steps:

1. **Identify verification target**: What proves this fix works?
2. **Execute verification**: Use appropriate tool from above
3. **Confirm result**: Does the actual behavior match expected?
4. **Document evidence**: Note what was verified and how

Example verifications:
- Web feature: Navigate to page, take snapshot, verify element exists
- API fix: Fetch endpoint, check response status and body
- CLI change: Run command, verify output format
- UI bug: Navigate, interact, confirm no error

If verification fails: Return to Phase 1, fix the issue, re-verify.

---

## Phase 3: SHIP

### 3.1 Run Build & Tests

```bash
# Run project's build/test commands
# Example: npm run build && npm test
# Example: pytest
# Example: cargo build && cargo test
```

If build/test fails: Fix errors, return to Phase 2 for re-verification.

### 3.2 Rebase

```bash
git fetch origin main
git rebase origin/main
# On conflict: resolve -> git add -> git rebase --continue
```

### 3.3 Commit & Push

```bash
git add -A
git commit -m "fix: issue title summary

- Root cause: ...
- Solution: ...

Resolves: viban-$ISSUE_ID"

git push -u origin viban-$ISSUE_ID
```

### 3.4 Create PR

```bash
EXISTING_PR=$(gh pr list --head viban-$ISSUE_ID --json number -q '.[0].number')
[ -z "$EXISTING_PR" ] && gh pr create \
    --title "viban-$ISSUE_ID: title" \
    --body "## Changes
- ...

## Verification
- [ ] Manual verification completed
- [ ] Build passing
- [ ] Tests passing (if applicable)" \
    --base main
```

### 3.5 Issue -> review

```bash
viban review $ISSUE_ID
```

---

## Phase 4: HANDOFF

```
Human Review Required

Issue #$ISSUE_ID -> review status

PR: gh pr view viban-$ISSUE_ID --web

Verification complete:
   - Manual verification done with available tools
   - Build passing
   - Project workflow followed

After approval: Delete issue from viban TUI
```

---

## Checklist

```
[ ] Read .viban/workflow.md (or CLAUDE.md fallback) for project workflow
[ ] Working on viban-$ISSUE_ID branch
[ ] Implementation complete
[ ] Manual verification passed (using appropriate tools)
[ ] Build & tests passing
[ ] Rebase complete
[ ] PR created
[ ] viban review executed
```

---

## CRITICAL: Status Transition Rule

> **NEVER end this command with the issue still in `in_progress`.**
>
> Before exiting — whether you completed all phases or stopped early due to errors:
> ```bash
> viban review $ISSUE_ID
> ```
> This is MANDATORY. If you skip this, the board becomes stale and misleading.

## CLI Reference

| Command | Description |
|---------|-------------|
| `viban` | Open TUI |
| `viban list` | Print board |
| `viban assign [session]` | Assign issue |
| `viban get <id>` | View issue |
| `viban review <id>` | Move to review |
