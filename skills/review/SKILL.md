---
name: review
description: "Checkout a review issue's branch for IDE diff review"
---

# /review

Checkout a review-status issue's branch into the main worktree so the user can review all changes as staged diffs in their IDE.

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

## Step 2: Prepare Branch

```bash
REPO_ROOT=$(git rev-parse --show-toplevel)
BRANCH="issue-$ID"
WT_DIR="$REPO_ROOT/.viban/worktrees/$ID"
```

If worktree exists, detach it to free the branch:

```bash
[ -d "$WT_DIR" ] && git -C "$WT_DIR" checkout --detach 2>/dev/null
```

---

## Step 3: Handle Dirty Working Tree

```bash
git status --porcelain
```

If dirty, ask user with AskUserQuestion:
- "You have uncommitted changes. How should we save them?"
- Options:
  - "Stash" → `git stash push -m "viban-review: before #$ID"`
  - "Temp commit" → `git add -A && git commit -m "viban-review: temp commit before #$ID"`

If clean, proceed directly.

---

## Step 4: Detached Checkout and Reset

```bash
git checkout --detach "$BRANCH"
git reset --soft main
```

This checks out the branch's commit without moving the branch pointer. Now all changes appear as **staged diffs** in the IDE, and the `$BRANCH` ref stays intact.

---

## Step 5: Report and Exit

```bash
PR_INFO=$(gh pr list --head "$BRANCH" --json number,url --jq '.[0]' 2>/dev/null)
```

Tell the user:

```
Reviewing #$ID — all changes are staged in your IDE.
{PR #N: <url> if PR exists}
Run /viban:approve $ID or /viban:reject $ID when ready.
```

**Done.** Do not wait for user input. The skill exits here.
