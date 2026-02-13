---
name: parallel
description: "Assign and resolve multiple independent backlog issues in parallel using coordinated agents"
---

# /parallel

Parallel resolution of independent backlog issues.

> **CLI only** (no direct viban.json access) | **Spawns N agents** via Claude Code teams

**Input**: `$ARGUMENTS` (optional: number of issues, default 3)

---

## Phase 0: SETUP

### 0.1 Read Workflow

```bash
[ -f ".viban/workflow.md" ] && cat ".viban/workflow.md"
```

Fallback to CLAUDE.md, then default. Same as `/viban:assign` Phase 0.1.

### 0.2 Parse Arguments

Extract the count of issues to process in parallel from `$ARGUMENTS`.
- Number provided (e.g. `/viban:parallel 5`) → use that number
- No number → default to 3
- Maximum: 5 (to avoid excessive resource usage)

### 0.3 Check Backlog

```bash
viban list
```

Count available backlog issues. If fewer than requested, adjust N down to match.
If backlog is empty: notify user and exit.

### 0.4 Git Setup

```bash
[ -n "$(git status --porcelain)" ] && echo "Warning: Uncommitted changes"
git checkout main && git fetch origin main && git reset --hard origin/main
```

### 0.5 Assign Issues

Assign N issues from backlog, each with a unique session ID:

```bash
ISSUE_IDS=()
for i in $(seq 1 $N); do
    SESSION=$(echo "${RANDOM}${i}" | md5 | head -c 8)
    ID=$(viban assign "$SESSION" 2>&1 | tail -1)
    [[ -z "$ID" || "$ID" == "No backlog" ]] && break
    ISSUE_IDS+=("$ID")
done
```

If no issues were assigned: notify user and exit.

### 0.6 Sync Status

```bash
viban sync --push-only
```

### 0.7 Collect Issue Details

For each assigned issue, gather its details:

```bash
for ID in "${ISSUE_IDS[@]}"; do
    viban get "$ID"
done
```

---

## Phase 1: DISPATCH PARALLEL AGENTS

Use Claude Code's **Task tool** to spawn one agent per issue. All agents run in parallel.

For each issue, spawn a `general-purpose` agent with `run_in_background: true`:

**Agent prompt template** (per issue):

```
You are resolving viban issue #{ID} in the repository at {repo_path}.

## Workflow
{paste workflow.md content}

## Issue Details
{paste viban get output}

## Plan (if available)
{paste .viban/plans/{ID}.md content, or "No plan available"}

## Instructions

You are one of {N} parallel agents, each resolving an independent issue.

1. Create a branch for your issue:
   - If external_id exists: `git checkout main && git checkout -b issue-{EXT_NUM}-{slug}`
   - Otherwise: `git checkout main && git checkout -b issue-{ID}`

2. Follow the project workflow phases:
   - Analyze: understand the issue, locate code, identify root cause
   - Implement: make focused changes following project conventions
   - Verify: manual verification of the fix

3. After implementation, commit your changes on your branch:
   ```bash
   git add <specific files>
   git commit -m "type: description

   - Root cause: ...
   - Solution: ...

   Resolves: #{ID}"
   ```

4. Push and create PR:
   ```bash
   git push -u origin {branch}
   gh pr create --title "type: title" --body "..." --base main
   ```

5. Move issue to review:
   ```bash
   viban review {ID}
   viban sync --push-only
   ```

CRITICAL: Always run `viban review {ID}` before finishing, even if you encounter errors.
Do NOT run the full test suite — the coordinator will run tests after all agents finish.
```

### Dispatch Pattern

Use the Task tool with `run_in_background: true` for each issue. Launch all agents in a single message to maximize parallelism.

---

## Phase 2: MONITOR & COLLECT

After dispatching all agents:

1. Wait for all background agents to complete (check via TaskOutput)
2. Collect results from each agent
3. Note which issues succeeded and which failed

---

## Phase 3: VERIFY & TEST

After all agents finish:

### 3.1 Check Branch Status

For each issue, verify the branch exists and has a PR:

```bash
for ID in "${ISSUE_IDS[@]}"; do
    BRANCH=$(git branch -a | grep -E "issue-${ID}|viban-${ID}" | head -1 | xargs)
    echo "Issue #${ID}: ${BRANCH:-NO BRANCH}"
    gh pr list --head "${BRANCH}" --json number,title -q '.[0]'
done
```

### 3.2 Run Tests

Run the full test suite once (not per-agent):

```bash
zsh tests/run_all.zsh
```

If tests fail: identify which agent's changes caused the failure and fix.

### 3.3 Sync

```bash
viban sync --push-only
```

---

## Phase 4: REPORT

Provide a summary table:

```
Parallel Resolution Complete

| Issue | Title | Branch | PR | Status |
|-------|-------|--------|----|--------|
| #ID   | ...   | ...    | #N | review |

Total: N issues processed
  Succeeded: X
  Failed: Y

All PRs ready for human review.
```

---

## Error Handling

- **Agent fails mid-work**: Ensure `viban review {ID}` is called for that issue regardless
- **Merge conflicts**: Each agent works on its own branch from main, so conflicts are unlikely. If they occur during rebase, the agent resolves them
- **Test failures**: Report which issue's changes likely caused the failure

---

## CRITICAL: Status Transition Rule

> **NEVER exit with any issue still in `in_progress`.** For every assigned issue, ensure `viban review {ID}` has been called before exiting.

## CLI Reference

| Command | Description |
|---------|-------------|
| `viban list` | Print board |
| `viban assign [session]` | Assign issue |
| `viban get <id>` | View issue |
| `viban review <id>` | Move to review |
| `viban sync --push-only` | Sync to GitHub |
