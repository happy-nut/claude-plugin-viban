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
```

### Mode A: PR exists

```bash
gh pr list --head "$BRANCH" --json number,url --jq '.[0]' 2>/dev/null
```

If PR found → **PR mode**.

### Mode B: Branch exists (no PR)

```bash
git rev-parse --verify "$BRANCH" 2>/dev/null
```

If branch exists → **Branch mode**.

### Mode C: No branch

No branch → **Commit mode**.

---

## Step 3: Checkout for Review

### Mode A / B (branch exists)

Stash if dirty:

```bash
git status --porcelain
```

If dirty, ask user: "You have uncommitted changes. Stash them to proceed?"
- Yes → `git stash push -m "viban-review: before reviewing #$ID"`
- No → exit

Detached HEAD checkout (preserves worktree):

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

**Mode A**: "PR #N for issue #$ID is checked out. Review in your IDE. Run `/viban:approve $ID` or `/viban:reject $ID` when ready."

**Mode B**: "Branch `issue-$ID` is checked out. Review in your IDE. Run `/viban:approve $ID` or `/viban:reject $ID` when ready."

**Mode C**: "Issue #$ID was worked on main directly. Run `/viban:approve $ID` or `/viban:reject $ID` when ready."

**Done.** Do not wait for user input. The skill exits here.
