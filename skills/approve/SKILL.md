---
name: approve
description: "Approve a reviewed issue — merge branch, cleanup worktree, mark done"
---

# /approve

Approve a review-status issue after IDE review. Restores commits, merges the branch, removes the worktree, and marks the card done.

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
WT_DIR="$REPO_ROOT/.viban/worktrees/$ID"
```

---

## Step 2: Restore Branch Commits

If worktree exists and was soft-reset (from `/viban:review`):

```bash
[ -d "$WT_DIR" ] && git -C "$WT_DIR" reset --soft ORIG_HEAD
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

Report: "Issue #$ID approved and merged."
