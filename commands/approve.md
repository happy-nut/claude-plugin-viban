---
description: "Approve a reviewed issue — merge branch, cleanup, mark done"
---

Run `/viban:approve <id>` after reviewing an issue with `/viban:review`.

Usage: `/viban:approve <id>`

What it does:
1. Merges the issue branch (via PR squash-merge or local merge)
2. Cleans up worktree and branch
3. Marks the card as done
4. Restores any stashed changes from `/viban:review`

**IMPORTANT:** Never read or write `viban.json` directly — always use `viban` CLI commands.
