---
name: approve
description: "Approve a reviewed issue — merge branch, cleanup worktree, mark done"
---

# /approve

Approve a review-status issue after IDE review. Merges the branch, removes the worktree, and marks the card done.

> **CLI only** (no direct viban.json access)

**Input**: `$ARGUMENTS` (required: issue ID)

---

## Output Rules

- **Do NOT output any preamble.**
- Start executing Step 1 immediately.

---

## Step 1: Validate

```bash
viban get $ID
```

Confirm the issue is in `review` status. If not, tell the user and exit.

```bash
BRANCH="issue-$ID"
WT_DIR="$PWD/.viban/worktrees/$ID"
```

---

## Step 2: Return to Main

Detached HEAD from `/viban:review` — branch is intact, just switch back:

```bash
git checkout main
```

---

## Step 3: Merge

### If PR exists

```bash
PR_NUM=$(gh pr list --head "$BRANCH" --json number --jq '.[0].number' 2>/dev/null)
```

If PR found:

```bash
gh pr merge "$PR_NUM" --squash --delete-branch
git pull origin main
```

### If no PR (branch only)

```bash
git merge "$BRANCH" --no-ff -m "Merge issue-$ID: <title>"
git branch -d "$BRANCH"
```

If merge conflicts: help user resolve.

### If no branch (main-direct work)

Nothing to merge. Proceed to Step 4.

---

## Step 4: Cleanup Worktree

```bash
[ -d "$WT_DIR" ] && git worktree remove "$WT_DIR" --force 2>/dev/null
```

---

## Step 5: Complete

```bash
viban done $ID
```

---

## Step 6: Restore User State

Check for stash:

```bash
STASH=$(git stash list | grep "viban-review: before #$ID" | head -1 | cut -d: -f1)
[ -n "$STASH" ] && git stash pop "$STASH"
```

Check for temp commit:

```bash
TEMP=$(git log --oneline -1 | grep "viban-review: temp commit before #$ID")
[ -n "$TEMP" ] && git reset HEAD~1
```

Report: "Issue #$ID approved and merged."

## CLI Reference

| Command | Description |
|---------|-------------|
| `viban get <id>` | View issue details |
| `viban done <id>` | Mark issue as done |
