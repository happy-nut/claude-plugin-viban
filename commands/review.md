---
description: "Review a worktree issue — checkout branch locally for IDE review, then approve or reject"
---

Run `/viban:review` to review the next issue in the review column.

Usage: `/viban:review [id]`

- `id`: (optional) specific issue ID to review. If omitted, picks the first review card.

What it does:
1. Finds the issue's worktree branch (`issue-{id}`)
2. Stashes your local changes if needed (asks first)
3. Checks out the branch in your main working directory for IDE review
4. Waits for your verdict: approve or reject
5. On approve: merges to main, marks done, cleans up branch
6. On reject: returns to main, moves card back to in_progress

**IMPORTANT:** Never read or write `viban.json` directly — always use `viban` CLI commands.
