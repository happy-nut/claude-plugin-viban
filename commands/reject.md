---
description: "Reject a reviewed issue — return to in_progress with feedback"
---

Run `/viban:reject <id> [feedback]` after reviewing an issue with `/viban:review`.

Usage: `/viban:reject <id> [feedback text]`

What it does:
1. Moves the card back to in_progress (worktree stays intact)
2. Records feedback as a comment on the issue (and PR if exists)
3. Restores any stashed changes from `/viban:review`

The agent can then pick the issue back up and address the feedback.

**IMPORTANT:** Never read or write `viban.json` directly — always use `viban` CLI commands.
