---
description: "Assign and resolve multiple independent backlog issues in parallel using coordinated agents"
---

Run `/viban:parallel` to process multiple backlog issues simultaneously.

Usage: `/viban:parallel [count]`

- `count`: Number of issues to process in parallel (default: 3, max: 5)

Examples:
- `/viban:parallel` — resolve up to 3 backlog issues in parallel
- `/viban:parallel 5` — resolve up to 5 backlog issues in parallel

Each issue gets its own agent, branch, and PR. The coordinator runs tests after all agents finish.
