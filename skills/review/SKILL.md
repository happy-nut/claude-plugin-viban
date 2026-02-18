---
name: review
description: "Review a worktree issue — checkout branch locally for IDE review, then approve or reject"
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

Confirm the issue is in `review` status. Show the user a one-line summary: `#ID [PRIORITY] Title`.

---

## Step 2: Locate Worktree and Branch

```bash
REPO_ROOT=$(git rev-parse --show-toplevel)
WT_DIR="$REPO_ROOT/.viban/worktrees/$ID"
BRANCH="issue-$ID"
```

Check if the branch exists:

```bash
git rev-parse --verify "$BRANCH" 2>/dev/null
```

If the branch doesn't exist:
- Tell the user: "No branch found for #ID. This issue may not have been worked on in a worktree."
- Exit.

---

## Step 3: Check for Local Changes

```bash
git status --porcelain
```

If there are uncommitted changes:
- **Ask the user**: "You have uncommitted changes. Stash them to proceed with review?"
- If user says **yes**: run `git stash push -m "viban-review: before reviewing #$ID"`
- If user says **no**: exit without changes
- Store `$STASHED=true` or `$STASHED=false`

---

## Step 4: Free the Branch and Checkout

If the worktree directory exists, remove it to free the branch:

```bash
git worktree remove "$WT_DIR" --force 2>/dev/null
```

Record the current branch for later:

```bash
PREV_BRANCH=$(git branch --show-current)
```

Checkout the issue branch:

```bash
git checkout "$BRANCH"
```

---

## Step 5: Show Diff and Wait for Verdict

Show the user what changed:

```bash
git log "$PREV_BRANCH".."$BRANCH" --oneline
```

Tell the user:
- "Branch `issue-$ID` is now checked out. Review the changes in your IDE."
- "When ready, tell me: **approve** or **reject**."

**Wait for user response.** Do not proceed until the user explicitly says approve or reject.

---

## Step 6a: Approve

If user approves:

```bash
git checkout "$PREV_BRANCH"
git merge "$BRANCH" --no-ff -m "Merge issue-$ID: <issue title>"
git branch -d "$BRANCH"
viban done $ID
```

If merge conflicts occur:
- Tell the user about the conflicts
- Help resolve them or let the user handle it
- After resolution: `git add . && git merge --continue`

---

## Step 6b: Reject

If user rejects:

```bash
git checkout "$PREV_BRANCH"
viban move $ID in_progress
```

Tell the user the card is back in progress. Optionally ask for feedback to add as a comment:

```bash
viban comment $ID "Review feedback: <user's feedback>"
```

---

## Step 7: Restore Stash

If `$STASHED` was true:

```bash
git stash pop
```

Report final status to the user.
