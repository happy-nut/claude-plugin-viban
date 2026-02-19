---
name: reject
description: "Reject a reviewed issue — return to in_progress with feedback"
---

# /reject

Reject a review-status issue and move it back to in_progress. The worktree stays intact so the agent can address feedback.

> **CLI only** (no direct viban.json access)

**Input**: `$ARGUMENTS` (required: issue ID, optional: feedback text)

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

Parse `$ARGUMENTS`: first token is `$ID`, rest is `$FEEDBACK`.

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

## Step 3: Re-attach Worktree

If worktree exists (detached during review), re-attach it to the branch:

```bash
[ -d "$WT_DIR" ] && git -C "$WT_DIR" checkout "$BRANCH"
```

If worktree does not exist, recreate it:

```bash
[ ! -d "$WT_DIR" ] && git worktree add "$WT_DIR" "$BRANCH"
```

---

## Step 4: Move Back to in_progress

```bash
viban move $ID in_progress
```

---

## Step 5: Record Feedback

If `$FEEDBACK` is provided:

```bash
viban comment $ID "$FEEDBACK"
```

Also comment on PR if one exists:

```bash
PR_NUM=$(gh pr list --head "$BRANCH" --json number --jq '.[0].number' 2>/dev/null)
[ -n "$PR_NUM" ] && gh pr comment "$PR_NUM" --body "$FEEDBACK"
```

If no feedback provided, ask the user: "Any feedback for the developer?"
- If provided → store as comment
- If none → skip

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

Report: "Issue #$ID rejected → in_progress. Worktree intact at `$WT_DIR`."

## CLI Reference

| Command | Description |
|---------|-------------|
| `viban get <id>` | View issue details |
| `viban move <id> <status>` | Move issue to status |
| `viban comment <id> "<text>"` | Add comment to issue |
