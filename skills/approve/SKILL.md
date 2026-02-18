---
name: approve
description: "Approve a reviewed issue — merge branch, cleanup worktree, mark done"
---

# /approve

Approve a review-status issue after IDE review. Merges the branch, cleans up the worktree, and marks the card done.

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
REPO_ROOT=$(git rev-parse --show-toplevel)
BRANCH="issue-$ID"
PREV_BRANCH=$(git branch --show-current)
```

If `$PREV_BRANCH` is empty (detached HEAD from `/viban:review`), determine the main branch:

```bash
PREV_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
[ -z "$PREV_BRANCH" ] && PREV_BRANCH="main"
```

---

## Step 2: Return to main branch

```bash
git checkout "$PREV_BRANCH"
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
```

Clean up worktree if it still exists:

```bash
WT_DIR="$REPO_ROOT/.viban/worktrees/$ID"
[ -d "$WT_DIR" ] && git worktree remove "$WT_DIR" --force 2>/dev/null
```

### If no PR (branch only)

Remove worktree to free the branch:

```bash
WT_DIR="$REPO_ROOT/.viban/worktrees/$ID"
[ -d "$WT_DIR" ] && git worktree remove "$WT_DIR" --force 2>/dev/null
```

Merge locally:

```bash
git merge "$BRANCH" --no-ff -m "Merge issue-$ID: <title>"
git branch -d "$BRANCH"
```

If merge conflicts: help user resolve.

### If no branch (main-direct work)

Nothing to merge. Proceed to Step 4.

---

## Step 4: Complete

```bash
viban done $ID
```

Restore stash if one was created during `/viban:review`:

```bash
STASH=$(git stash list | grep "viban-review: before reviewing #$ID" | head -1 | cut -d: -f1)
[ -n "$STASH" ] && git stash pop "$STASH"
```

Report: "Issue #$ID approved and merged."
