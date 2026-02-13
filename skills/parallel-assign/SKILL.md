---
name: parallel-assign
description: "Assign and resolve multiple independent backlog issues in parallel using git worktrees and coordinated agents"
---

# /parallel-assign

Parallel resolution of independent backlog issues via git worktrees.

> **CLI only** (no direct viban.json access) | **Opus sub-agents** in isolated worktrees

**Input**: `$ARGUMENTS` (optional: number of issues, default 3)

---

## Phase 0: SETUP

### 0.1 Read Workflow

```bash
[ -f ".viban/workflow.md" ] && cat ".viban/workflow.md"
```

Fallback to CLAUDE.md, then default. Same as `/viban:assign` Phase 0.1.

### 0.2 Parse Arguments

Extract count from `$ARGUMENTS`:
- Number provided (e.g. `/viban:parallel-assign 5`) → use that number
- No number → default to 3
- Maximum: 5

### 0.3 Check Backlog & Git State

```bash
viban list
```

Count available backlog issues. Adjust N down if fewer available.
If backlog is empty: notify user and exit.

```bash
[ -n "$(git status --porcelain)" ] && echo "Warning: Uncommitted changes"
git checkout main && git fetch origin main && git reset --hard origin/main
```

### 0.4 Assign Issues

Assign N issues, each with a unique session ID. Determine branch names per workflow convention:

```bash
ISSUES=()  # Array of "ID|BRANCH" pairs
for i in $(seq 1 $N); do
    SESSION=$(echo "${RANDOM}${i}" | md5 | head -c 8)
    ID=$(viban assign "$SESSION" 2>&1 | tail -1)
    [[ -z "$ID" || "$ID" == "No backlog" ]] && break

    # Determine branch name (same logic as /viban:assign Phase 0.3)
    ISSUE_JSON=$(viban get "$ID")
    EXT_ID=$(echo "$ISSUE_JSON" | jq -r '.external_id // ""')
    if [ -n "$EXT_ID" ] && [ "$EXT_ID" != "null" ]; then
        EXTERNAL_NUM="${EXT_ID##*:}"
        TITLE=$(echo "$ISSUE_JSON" | jq -r '.title' | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | head -c 40)
        BRANCH="issue-${EXTERNAL_NUM}-${TITLE}"
    else
        BRANCH="issue-${ID}"
    fi

    ISSUES+=("${ID}|${BRANCH}")
done
```

If no issues were assigned: notify user and exit.

### 0.5 Create Worktrees

For each assigned issue, create an isolated git worktree:

```bash
REPO_ROOT=$(git rev-parse --show-toplevel)
mkdir -p "$REPO_ROOT/.viban/worktrees"

for entry in "${ISSUES[@]}"; do
    ID="${entry%%|*}"
    BRANCH="${entry##*|}"
    WT_DIR="$REPO_ROOT/.viban/worktrees/$BRANCH"

    git worktree add -b "$BRANCH" "$WT_DIR" origin/main
done
```

### 0.6 Sync Status

```bash
viban sync --push-only
```

---

## Phase 1: DISPATCH PARALLEL AGENTS

Spawn one **opus** agent per issue using `Task` tool. All agents launch in a single message with `run_in_background: true`.

**Agent prompt template** (per issue):

```
You are resolving viban issue #{ID} in an isolated git worktree.

## Environment
- Worktree path: {REPO_ROOT}/.viban/worktrees/{BRANCH}
- Branch: {BRANCH}
- Main repo: {REPO_ROOT}
- ALL file operations must happen inside the worktree path

## Workflow
{paste workflow.md content}

## Issue Details
{paste viban get output}

## Plan (if available)
{paste .viban/plans/{ID}.md content, or "No plan available"}

## Instructions

You are one of {N} parallel agents working in isolated git worktrees.

1. Work ONLY inside your worktree: {REPO_ROOT}/.viban/worktrees/{BRANCH}
   - cd to the worktree before any work
   - All reads, edits, and writes must target files under this path

2. Follow the project workflow phases:
   - Analyze: understand the issue, locate code, identify root cause
   - Implement: make focused changes following project conventions
   - Verify: manual verification of the fix

3. After implementation, commit on your branch:
   ```bash
   cd {REPO_ROOT}/.viban/worktrees/{BRANCH}
   git add <specific files>
   git commit -m "type: description

   - Root cause: ...
   - Solution: ...

   Resolves: #{ID}"
   ```

4. Push and create PR:
   ```bash
   git push -u origin {BRANCH}
   gh pr create --title "type: title" --body "..." --base main
   ```

5. Move issue to review:
   ```bash
   cd {REPO_ROOT}
   viban review {ID}
   ```

CRITICAL:
- Always run `viban review {ID}` before finishing, even on errors.
- Do NOT run the full test suite — the coordinator handles that.
- Do NOT remove the worktree — the coordinator handles cleanup.
```

### Dispatch Pattern

```python
# Pseudo-code for the dispatch
for each (ID, BRANCH) in ISSUES:
    Task(
        subagent_type="general-purpose",
        model="opus",
        run_in_background=True,
        prompt=filled_template(ID, BRANCH, workflow, issue_json, plan)
    )
```

---

## Phase 2: MONITOR & COLLECT

1. Wait for all background agents to complete (poll via `TaskOutput`)
2. Collect results — note successes and failures
3. For any issue where `viban review` was not called, run it now as safety net:
   ```bash
   viban review $ID
   ```

---

## Phase 3: TRANSPLANT & CLEANUP

After all agents finish, for each issue:

### 3.1 Verify Local Branches

The local branch already exists (created by `git worktree add -b`). After worktree removal, the branch and its commits remain in the local repo.

```bash
REPO_ROOT=$(git rev-parse --show-toplevel)
cd "$REPO_ROOT"

for entry in "${ISSUES[@]}"; do
    BRANCH="${entry##*|}"
    git log --oneline -3 "$BRANCH"
done
```

### 3.2 Remove Worktrees

PRs have been created — worktrees are no longer needed:

```bash
for entry in "${ISSUES[@]}"; do
    BRANCH="${entry##*|}"
    WT_DIR="$REPO_ROOT/.viban/worktrees/$BRANCH"
    git worktree remove "$WT_DIR" --force
done
```

### 3.3 Verify PRs Exist

```bash
for entry in "${ISSUES[@]}"; do
    BRANCH="${entry##*|}"
    gh pr list --head "$BRANCH" --json number,title,url -q '.[0]'
done
```

---

## Phase 4: TEST & REPORT

### 4.1 Run Tests

Run the full test suite once on main (not per-agent):

```bash
zsh tests/run_all.zsh
```

If tests fail: identify which agent's changes caused the failure and report.

### 4.2 Sync

```bash
viban sync --push-only
```

### 4.3 Report

```
Parallel Resolution Complete

| Issue | Title | Branch | PR | Status |
|-------|-------|--------|----|--------|
| #ID   | ...   | ...    | #N | review |

Total: N issues processed
  Succeeded: X
  Failed: Y

Local branches available:
  - {BRANCH_1}
  - {BRANCH_2}
  ...

Worktrees cleaned up. All PRs ready for human review.
```

---

## Error Handling

- **Agent fails mid-work**: coordinator calls `viban review {ID}` as safety net
- **Worktree creation fails**: skip that issue, log error, continue with others
- **PR creation fails in agent**: coordinator reports it; local branch still available for manual PR
- **Test failures**: report which branch likely caused the failure

---

## CRITICAL RULES

> 1. **NEVER exit with any issue still in `in_progress`.** For every assigned issue, ensure `viban review {ID}` has been called.
> 2. **ALWAYS clean up worktrees** after PRs are created. Worktree dirs must not linger in `.viban/worktrees/`.

## CLI Reference

| Command | Description |
|---------|-------------|
| `viban list` | Print board |
| `viban assign [session]` | Assign issue |
| `viban get <id>` | View issue |
| `viban review <id>` | Move to review |
| `viban sync --push-only` | Sync to GitHub |
