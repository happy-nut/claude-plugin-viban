---
description: "Assign first backlog issue — clarify if unclear, then finish"
---

> Tip: Run `/clear` before `/viban:assign` for a clean context.

Run `/viban:assign` to pick up and resolve the next backlog issue.

Usage: `/viban:assign`

What it does:
1. Assigns the first backlog issue (by priority) to the current session
2. If the issue description is unclear, interviews you to gather missing information
3. Analyzes, implements, verifies, and ships the fix (branch + PR + review)

**IMPORTANT:** Never read or write `viban.json` directly — always use `viban` CLI commands.
