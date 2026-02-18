---
name: review
description: "Checkout a review issue's branch for IDE review"
---

# /review

Checkout a review-status issue's branch into the main working directory so the user can review changes in their IDE.

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

```bash
REPO_ROOT=$(git rev-parse --show-toplevel)
BRANCH="issue-$ID"
WT_DIR="$REPO_ROOT/.viban/worktrees/$ID"
```

Check in priority order — first match wins:

### Mode W: Worktree exists

```bash
[ -d "$WT_DIR" ]
```

If worktree exists → **Worktree mode**.

### Mode A: PR exists (no worktree)

```bash
gh pr list --head "$BRANCH" --json number,url --jq '.[0]' 2>/dev/null
```

If PR found → **PR mode**.

### Mode B: Branch exists (no PR, no worktree)

```bash
git rev-parse --verify "$BRANCH" 2>/dev/null
```

If branch exists → **Branch mode**.

### Mode C: No branch

No branch → **Commit mode**.

---

## Step 3: Present for Review

### Mode W (worktree exists)

Show changes against main:

```bash
git -C "$WT_DIR" log main.."$BRANCH" --oneline
git -C "$WT_DIR" diff main..."$BRANCH" --stat
```

Check if PR exists:

```bash
PR_INFO=$(gh pr list --head "$BRANCH" --json number,url --jq '.[0]' 2>/dev/null)
```

### Mode A / B (no worktree, branch exists)

Stash if dirty:

```bash
git status --porcelain
```

If dirty, ask user: "You have uncommitted changes. Stash them to proceed?"
- Yes → `git stash push -m "viban-review: before reviewing #$ID"`
- No → exit

Detached HEAD checkout:

```bash
PREV_BRANCH=$(git branch --show-current)
git checkout --detach "$BRANCH"
```

Show changes:

```bash
git log "$PREV_BRANCH".."$BRANCH" --oneline
git diff "$PREV_BRANCH"..."$BRANCH" --stat
```

### Mode C (no branch)

Show recent commits:

```bash
git log --oneline -10
```

---

## Step 4: Report and Exit

Tell the user:

**Mode W**: "Issue #$ID worktree is at `$WT_DIR`. Open it in your IDE to review. {PR #N link if PR exists.} Run `/viban:approve $ID` or `/viban:reject $ID` when ready."

**Mode A**: "PR #N for issue #$ID is checked out. Review in your IDE. Run `/viban:approve $ID` or `/viban:reject $ID` when ready."

**Mode B**: "Branch `issue-$ID` is checked out. Review in your IDE. Run `/viban:approve $ID` or `/viban:reject $ID` when ready."

**Mode C**: "Issue #$ID was worked on main directly. Run `/viban:approve $ID` or `/viban:reject $ID` when ready."

**Done.** Do not wait for user input. The skill exits here.
