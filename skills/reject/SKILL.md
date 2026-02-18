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

---

## Step 2: Return to main branch

```bash
PREV_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
[ -z "$PREV_BRANCH" ] && PREV_BRANCH="main"
git checkout "$PREV_BRANCH"
```

---

## Step 3: Move back to in_progress

```bash
viban move $ID in_progress
```

---

## Step 4: Record feedback

If `$FEEDBACK` is provided:

```bash
viban comment $ID "$FEEDBACK"
```

Also comment on PR if one exists:

```bash
BRANCH="issue-$ID"
PR_NUM=$(gh pr list --head "$BRANCH" --json number --jq '.[0].number' 2>/dev/null)
[ -n "$PR_NUM" ] && gh pr comment "$PR_NUM" --body "$FEEDBACK"
```

If no feedback provided, ask the user: "Any feedback for the developer?"
- If provided → store as comment
- If none → skip

---

## Step 5: Restore stash

```bash
STASH=$(git stash list | grep "viban-review: before reviewing #$ID" | head -1 | cut -d: -f1)
[ -n "$STASH" ] && git stash pop "$STASH"
```

Report: "Issue #$ID rejected and moved to in_progress. Worktree is intact for the agent to continue."
