---
name: reject
description: "Reject a reviewed issue — return to in_progress with feedback"
---

# /reject

Reject a review-status issue and move it back to in_progress. Restores the worktree so the agent can address feedback.

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
REPO_ROOT=$(git rev-parse --show-toplevel)
BRANCH="issue-$ID"
WT_DIR="$REPO_ROOT/.viban/worktrees/$ID"
```

---

## Step 2: Restore Branch Commits

If worktree was soft-reset (from `/viban:review`):

```bash
[ -d "$WT_DIR" ] && git -C "$WT_DIR" reset --soft ORIG_HEAD
```

Worktree stays intact for the agent to continue working.

---

## Step 3: Move Back to in_progress

```bash
viban move $ID in_progress
```

---

## Step 4: Record Feedback

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

## Step 5: Report

Report: "Issue #$ID rejected → in_progress. Worktree intact at `$WT_DIR`."
