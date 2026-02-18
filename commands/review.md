---
description: "Checkout a review issue's branch for IDE review"
---

Run `/viban:review` to checkout a review-status issue's branch for IDE review.

Usage: `/viban:review [id]`

- `id`: (optional) specific issue ID. If omitted, picks the first review card.

What it does:
1. Detects review mode (PR / branch / main-direct)
2. Stashes local changes if needed
3. Checks out the branch via detached HEAD (worktree stays intact)
4. Shows diff summary

After reviewing in your IDE, run:
- `/viban:approve <id>` — merge and mark done
- `/viban:reject <id> [feedback]` — back to in_progress with feedback

**IMPORTANT:** Never read or write `viban.json` directly — always use `viban` CLI commands.
