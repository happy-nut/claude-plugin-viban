---
description: "Assign and resolve multiple independent backlog issues in parallel using git worktrees and coordinated agents"
---

Run `/viban:parallel-assign` to process multiple backlog issues simultaneously.

Usage: `/viban:parallel-assign [count]`

- `count`: Number of issues to process in parallel (default: 3, max: 5)

Examples:
- `/viban:parallel-assign` — resolve up to 3 backlog issues in parallel
- `/viban:parallel-assign 5` — resolve up to 5 backlog issues in parallel

Each issue gets its own opus agent working in an isolated git worktree. After all agents finish, PRs are created, local branches are preserved, and worktrees are cleaned up.
