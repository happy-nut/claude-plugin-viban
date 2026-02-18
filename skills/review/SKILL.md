---
name: review
description: "Prepare a review issue for IDE review via staged diffs"
---

# /review

Prepare a review-status issue for IDE review. Soft-resets the worktree so all changes appear as staged diffs.

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

## Step 2: Locate Worktree

```bash
REPO_ROOT=$(git rev-parse --show-toplevel)
BRANCH="issue-$ID"
WT_DIR="$REPO_ROOT/.viban/worktrees/$ID"
```

If worktree does not exist:

```bash
[ ! -d "$WT_DIR" ]
```

Tell the user "No worktree found for #$ID. Cannot review." and exit.

---

## Step 3: Soft-Reset for IDE Review

```bash
git -C "$WT_DIR" reset --soft main
```

Now all changes from the issue branch appear as **staged diffs** when the worktree directory is opened in the IDE.

---

## Step 4: Report and Exit

```bash
PR_INFO=$(gh pr list --head "$BRANCH" --json number,url --jq '.[0]' 2>/dev/null)
```

Tell the user:

```
Reviewing #$ID — open $WT_DIR in your IDE to see staged diffs.
{PR #N: <url> if PR exists}
Run /viban:approve $ID or /viban:reject $ID when ready.
```

**Done.** Do not wait for user input. The skill exits here.
