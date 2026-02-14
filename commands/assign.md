---
description: "Assign first backlog issue — clarify if unclear, then finish"
---

Run `/viban:assign` to pick up the next backlog issue.

Usage: `/viban:assign`

What it does:
1. Assigns the first backlog issue (by priority) to the current session
2. If the issue description is unclear or lacks context, interviews you to gather missing information and updates the issue
3. That's it — no implementation, no branch creation

This command is for **assignment and clarification only**. Use other tools to start working on the assigned issue.

**IMPORTANT:** Never read or write `viban.json` directly — always use `viban` CLI commands.
