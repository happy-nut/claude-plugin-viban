---
name: parallel-assign
description: "Assign and resolve multiple independent backlog issues in parallel using git worktrees and coordinated agents"
---

# /parallel-assign

Parallel resolution of independent backlog issues via git worktrees.

> **CLI only** (no direct viban.json access) | **Opus sub-agents** in isolated worktrees

**Input**: `$ARGUMENTS` (optional: number of issues, default 3)

---

## Output Rules

- **Do NOT output any preamble.** No "Your Task:", "I'll now...", "Let me...", or task summaries before starting work.
- Start executing Phase 0 immediately and silently.

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

    BRANCH="issue-${ID}"

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
    # Use issue ID as worktree dir name (matches cmd_done cleanup at .viban/worktrees/{ID})
    WT_DIR="$REPO_ROOT/.viban/worktrees/$ID"

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
- Worktree path: {REPO_ROOT}/.viban/worktrees/{ID}
- Branch: {BRANCH}
- Main repo: {REPO_ROOT}
- ALL file operations must happen inside the worktree path

## Workflow (Analyze + Implement + Verify only)
{paste workflow.md Phase 1 (Analyze), Phase 2 (Implement), and Phase 3 (Verify) sections ONLY}
{DO NOT include: Pipeline summary, GitHub Sync, Phase 4 (Build and Test), Phase 5 (Ship), Issue Management, Post-merge, or Additional Rules}

## Issue Details
{paste viban get output}

## Plan (if available)
{paste .viban/plans/{ID}.md content, or "No plan available"}

## Instructions

You are one of {N} parallel agents working in isolated git worktrees.

1. Work ONLY inside your worktree: {REPO_ROOT}/.viban/worktrees/{ID}
   - cd to the worktree before any work
   - All reads, edits, and writes must target files under this path

2. Follow the project workflow phases:
   - Analyze: understand the issue, locate code, identify root cause
   - Implement: make focused changes following project conventions
   - Verify: manual verification of the fix

3. After implementation, commit on your branch:
   ```bash
   cd {REPO_ROOT}/.viban/worktrees/{ID}
   git add <specific files>
   git commit -m "type: description

   - Root cause: ...
   - Solution: ...

   Resolves: #{ID}"
   ```

4. That's it. Stop after committing.

ABSOLUTE RULES:
- **Your job ends after committing.** The coordinator handles push, PR creation, and issue status.
- **FORBIDDEN: `git push`** — the coordinator pushes from the main repo after verifying.
- **FORBIDDEN: `gh pr create`** — the coordinator creates PRs after transplanting branches.
- **FORBIDDEN: `viban done`** — this DELETES the card permanently.
- **FORBIDDEN: `viban review`** — the coordinator handles issue status.
- **FORBIDDEN: reading or writing `viban.json`** — use CLI commands only.
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

---

## Phase 3: TRANSPLANT & CLEANUP

After all agents finish, the coordinator handles everything from the main repo root.

```bash
REPO_ROOT=$(git rev-parse --show-toplevel)
cd "$REPO_ROOT"
```

### 3.1 Verify Local Branches

Confirm each branch has commits from the agent:

```bash
for entry in "${ISSUES[@]}"; do
    BRANCH="${entry##*|}"
    git log --oneline -3 "$BRANCH"
done
```

If a branch has no new commits (agent failed), skip it and report.

### 3.2 Push Branches & Create PRs

For each branch with commits, push from the main repo and create a PR:

```bash
for entry in "${ISSUES[@]}"; do
    ID="${entry%%|*}"
    BRANCH="${entry##*|}"

    # Push the local branch to remote
    git push -u origin "$BRANCH"

    # Create PR
    gh pr create --head "$BRANCH" --base main \
        --title "type: title" \
        --body "Resolves: #${ID}"

    # Move issue to review
    viban review "$ID"
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

- **Agent fails mid-work**: coordinator still attempts push + PR for any commits on the branch. If no commits, skip and call `viban review {ID}` to unblock the card.
- **Worktree creation fails**: skip that issue, log error, continue with others
- **Push fails**: report it; local branch still available for manual push
- **PR creation fails**: report it; branch is already pushed, user can create PR manually
- **Test failures**: report which branch likely caused the failure

---

## CRITICAL RULES

> 1. **NEVER read or write `viban.json` directly** — always use `viban` CLI commands. Direct JSON access causes race conditions and data corruption.
> 2. **NEVER exit with any issue still in `in_progress`.** For every assigned issue, ensure `viban review {ID}` has been called.
> 3. **Do NOT remove worktrees** after PRs are created. Worktrees stay at `.viban/worktrees/{ID}` for the review flow (`/viban:approve` cleans up).

## CLI Reference

| Command | Description |
|---------|-------------|
| `viban list` | Print board |
| `viban assign [session]` | Assign issue |
| `viban get <id>` | View issue |
| `viban review <id>` | Move to review |
| `viban sync --push-only` | Sync to GitHub |
