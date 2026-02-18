---
name: review
description: "Review a worktree issue — checkout branch locally for IDE review, then approve or reject"
---

# /review

Checkout a review-status issue's branch into the main working directory so the user can review changes in their IDE. Supports iterative feedback: reject sends the card back to in_progress with the worktree intact for the agent to continue.

> **CLI only** (no direct viban.json access)

**Input**: `$ARGUMENTS` (optional: issue ID)

---

## Output Rules

- **Do NOT output any preamble.** No "Your Task:", "I'll now...", "Let me...", or task summaries before starting work.
- Start executing Step 1 immediately and silently.

---

## Step 1: Find Review Card

If `$ARGUMENTS` contains an issue ID, use it. Otherwise find the first review card:

```bash
viban list --status review
```

If no review cards exist, tell the user and exit.

Extract the issue ID. Store as `$ID`.

```bash
viban get $ID
```

Show the user a one-line summary: `#ID [PRIORITY] Title`.

---

## Step 2: Detect Review Mode

Determine how to review based on what exists:

```bash
REPO_ROOT=$(git rev-parse --show-toplevel)
BRANCH="issue-$ID"
WT_DIR="$REPO_ROOT/.viban/worktrees/$ID"
```

Check in this order:

### Mode A: PR exists

```bash
gh pr list --head "$BRANCH" --json number,url --jq '.[0]' 2>/dev/null
```

If a PR is found → **PR review mode** (Step 3A).

### Mode B: Branch exists (no PR)

```bash
git rev-parse --verify "$BRANCH" 2>/dev/null
```

If branch exists → **Branch review mode** (Step 3B).

### Mode C: No branch (main-direct work)

No branch found → **Commit review mode** (Step 3C).

---

## Step 3A: PR Review Mode

The preferred path when `/viban:parallel-assign` created a PR.

### 3A.1 Stash if needed

```bash
git status --porcelain
```

If dirty, ask user: "You have uncommitted changes. Stash them to proceed?"
- Yes → `git stash push -m "viban-review: before reviewing #$ID"`
- No → exit

### 3A.2 Detached HEAD checkout

**Do NOT remove the worktree.** Use detached HEAD to view the branch without conflicting with the worktree:

```bash
PREV_BRANCH=$(git branch --show-current)
git checkout --detach "$BRANCH"
```

This puts the main working directory at the same commit as the branch, without "checking out" the branch itself. The worktree remains intact.

### 3A.3 Show changes and wait

```bash
git log "$PREV_BRANCH".."$BRANCH" --oneline
```

Tell the user:
- "Issue #$ID (PR #N) is checked out for review. Review in your IDE."
- "Say **approve** or **reject** when ready."

**Wait for user response.**

### 3A.4 Approve

```bash
git checkout "$PREV_BRANCH"
gh pr merge <PR_NUMBER> --squash --delete-branch
```

Worktree cleanup happens automatically since the branch is deleted. If the worktree dir still exists:

```bash
git worktree remove "$WT_DIR" --force 2>/dev/null
```

```bash
viban done $ID
```

### 3A.5 Reject

```bash
git checkout "$PREV_BRANCH"
viban move $ID in_progress
```

**Worktree stays intact** — the agent can go back and work on feedback.

Ask user for feedback. If provided:

```bash
gh pr comment <PR_NUMBER> --body "<feedback>"
viban comment $ID "<feedback>"
```

### 3A.6 Restore stash

If stashed: `git stash pop`

---

## Step 3B: Branch Review Mode (no PR)

Branch exists locally but no PR was created.

### 3B.1 Stash if needed

Same as 3A.1.

### 3B.2 Detached HEAD checkout

Same as 3A.2 — use `git checkout --detach "$BRANCH"` to preserve the worktree.

### 3B.3 Show changes and wait

```bash
git log "$PREV_BRANCH".."$BRANCH" --oneline
```

Tell user to review in IDE, wait for verdict.

### 3B.4 Approve

```bash
git checkout "$PREV_BRANCH"
```

Remove worktree to free the branch for merge:

```bash
[ -d "$WT_DIR" ] && git worktree remove "$WT_DIR" --force 2>/dev/null
```

```bash
git merge "$BRANCH" --no-ff -m "Merge issue-$ID: <title>"
git branch -d "$BRANCH"
viban done $ID
```

If merge conflicts: help user resolve, then continue.

### 3B.5 Reject

```bash
git checkout "$PREV_BRANCH"
viban move $ID in_progress
```

**Worktree stays intact.** Ask for feedback, store as comment.

### 3B.6 Restore stash

If stashed: `git stash pop`

---

## Step 3C: Commit Review Mode (no branch)

Work was done directly on main (e.g., via `/viban:assign`).

Show recent commits that may relate to this issue:

```bash
git log --oneline -10
```

Tell the user:
- "This issue was worked on directly on main (no branch). Here are recent commits."
- "Say **approve** to mark done, or **reject** to move back to in_progress."

**Wait for user response.**

### Approve

```bash
viban done $ID
```

### Reject

```bash
viban move $ID in_progress
```

Ask for feedback, store as comment.

---

## Key Design Decisions

- **Detached HEAD** instead of branch checkout: avoids conflicting with worktree's branch lock, keeps worktree intact for iteration.
- **Worktree persists on reject**: agent can return to the worktree and address feedback without re-creating it.
- **Worktree removed only on approve**: cleanup happens when work is finalized (branch merge/delete).
- **`viban done` requires review status**: structural guard prevents agents from skipping review. Only humans approve via this command.
