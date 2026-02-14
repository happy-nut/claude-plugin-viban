---
name: assign
description: "Assign and resolve first backlog issue from viban board through to PR completion"
---

# /assign

First backlog issue → Resolve → PR completion

> **CLI only** (no direct viban.json access) | **No worktree** (branch in main repo)

---

## Phase 0: SETUP

### 0.1 Read Workflow (CRITICAL)

Check in priority order — first match wins, follow it exactly:

1. `.viban/workflow.md` → `[ -f ".viban/workflow.md" ] && cat ".viban/workflow.md"`
2. CLAUDE.md (legacy, only if no workflow.md):
```bash
for path in "./CLAUDE.md" "./.claude/CLAUDE.md" "../CLAUDE.md"; do
    [ -f "$path" ] && cat "$path"
done
```
Look for `Issue Resolution Workflow` or `Workflow` section.
3. Default workflow (Phase 1 below)

### 0.2 Git Setup & Assign

```bash
# Check uncommitted changes → AskUserQuestion if dirty
[ -n "$(git status --porcelain)" ] && echo "Warning: Uncommitted changes"

git checkout main && git fetch origin main && git reset --hard origin/main

ISSUE_ID=$(viban assign 2>&1 | tail -1)
[[ -z "$ISSUE_ID" || "$ISSUE_ID" == "No backlog" ]] && echo "No issues in backlog" && exit 0
```

### 0.3 Detect Sync & Create Branch

```bash
ISSUE_JSON=$(viban get $ISSUE_ID)
EXT_ID=$(echo "$ISSUE_JSON" | jq -r '.external_id // ""')
SYNC_ACTIVE=false; EXTERNAL_NUM=""

if [ -n "$EXT_ID" ] && [ "$EXT_ID" != "null" ]; then
    SYNC_ACTIVE=true
    EXTERNAL_NUM="${EXT_ID##*:}"  # "github:42" -> "42"
    TITLE=$(echo "$ISSUE_JSON" | jq -r '.title' | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | head -c 40)
    git checkout -b "issue-${EXTERNAL_NUM}-${TITLE}"
else
    git checkout -b viban-$ISSUE_ID
fi
```

### 0.4 Load Plan (if available)

```bash
[ -f ".viban/plans/${ISSUE_ID}.md" ] && cat ".viban/plans/${ISSUE_ID}.md"
```

If plan exists: use as primary guide for Phase 1, skip redundant analysis, but verify plan is still current.

---

## Phase 1: ANALYZE & IMPLEMENT

```bash
viban get $ISSUE_ID
```

**With project workflow**: follow its exact steps.
**Default** (no workflow): Understand → Locate → Analyze root cause → Implement minimal changes.

---

## Phase 2: VERIFY

Manual verification — do NOT run build/test here (Phase 3).

| Type | Tool |
|------|------|
| Web UI | Playwright MCP (`browser_navigate`, `browser_snapshot`, `browser_click`) |
| API | WebFetch |
| CLI | Bash |
| Visual | Read (screenshot files) |
| Browser | Chrome DevTools MCP |

Steps: identify what proves the fix → execute → confirm behavior → document evidence.

Examples:
- Web feature: navigate to page, take snapshot, verify element exists
- API fix: fetch endpoint, check response status and body
- CLI change: run command, verify output format
- UI bug: navigate, interact, confirm no error

If verification fails: return to Phase 1.

---

## Phase 3: SHIP

### 3.1 Build & Test

Run project's build/test commands. If fail: fix → return to Phase 2.

### 3.2 Rebase

```bash
git fetch origin main && git rebase origin/main
# On conflict: resolve -> git add -> git rebase --continue
```

### 3.3 Commit & Push

```bash
BRANCH=$(git branch --show-current)
git add -A

# Sync mode: "Closes #NUM" | Default: "Resolves: viban-ID"
if [ "$SYNC_ACTIVE" = true ]; then
    git commit -m "fix: issue title summary

- Root cause: ...
- Solution: ...

Closes #$EXTERNAL_NUM"
else
    git commit -m "fix: issue title summary

- Root cause: ...
- Solution: ...

Resolves: #$ISSUE_ID"
fi

git push -u origin "$BRANCH"
```

### 3.4 Create PR

```bash
EXISTING_PR=$(gh pr list --head "$BRANCH" --json number -q '.[0].number')

if [ -z "$EXISTING_PR" ]; then
    if [ "$SYNC_ACTIVE" = true ]; then
        gh pr create --title "fix: title" \
            --body "## Changes
- ...

Closes #$EXTERNAL_NUM

## Verification
- [ ] Manual verification completed
- [ ] Build passing
- [ ] Tests passing (if applicable)" --base main
    else
        gh pr create --title "fix: title" \
            --body "## Changes
- ...

## Verification
- [ ] Manual verification completed
- [ ] Build passing
- [ ] Tests passing (if applicable)" --base main
    fi
fi
```

### 3.5 Move to Review

```bash
viban review $ISSUE_ID
```

---

## Phase 4: HANDOFF

```
Issue #$ISSUE_ID → review | PR: gh pr view --web
Verification: manual + build + workflow followed
After approval: delete issue from viban TUI
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

> **NEVER exit with issue still in `in_progress`.** Always run `viban review $ISSUE_ID` before exiting — whether completed or stopped early.

## CLI Reference

| Command | Description |
|---------|-------------|
| `viban` | Open TUI |
| `viban list` | Print board |
| `viban assign [session]` | Assign issue |
| `viban get <id>` | View issue |
| `viban review <id>` | Move to review |
