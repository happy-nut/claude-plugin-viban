---
description: "Assign and resolve multiple independent backlog issues in parallel — each agent works in its own isolated git worktree"
---

Run `/viban:parallel-assign` to process multiple backlog issues simultaneously.

Each issue is resolved in a **separate git worktree**, so agents never interfere with each other's work. Worktrees are automatically cleaned up after PRs are created.

Usage: `/viban:parallel-assign [count]`

- `count`: Number of issues to process in parallel (default: 3, max: 5)

Examples:
- `/viban:parallel-assign` — resolve up to 3 backlog issues in parallel (each in its own worktree)
- `/viban:parallel-assign 5` — resolve up to 5 backlog issues in parallel

How it works:
1. Assigns N backlog issues and creates isolated git worktrees (`.viban/worktrees/{id}`)
2. Spawns one opus agent per issue — each agent works exclusively in its own worktree
3. Agents analyze, implement, commit, push, and create PRs independently
4. Coordinator collects results, runs tests, and cleans up worktrees
