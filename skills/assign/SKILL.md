---
name: assign
description: "Assign first backlog issue and resolve it through to review"
---

# /assign

Assign the first backlog issue and execute the full resolution workflow. If the description is unclear, interview the user first.

> **CLI only** (no direct viban.json access)

---

## Step 0: Read Workflow (CRITICAL)

Check in priority order — first match wins:

1. `.viban/workflow.md` → `[ -f ".viban/workflow.md" ] && cat ".viban/workflow.md"`
2. CLAUDE.md (legacy, only if no workflow.md):
```bash
for path in "./CLAUDE.md" "./.claude/CLAUDE.md" "../CLAUDE.md"; do
    [ -f "$path" ] && cat "$path"
done
```
Look for `Issue Resolution Workflow` or `Workflow` section.

If a workflow exists, **follow it exactly** — its pipeline, conventions, and stop points override the defaults below.

---

## Step 1: Assign

```bash
ISSUE_ID=$(viban assign 2>&1 | tail -1)
[[ -z "$ISSUE_ID" || "$ISSUE_ID" == "No backlog" ]] && echo "No issues in backlog" && exit 0
```

If backlog is empty: notify user and exit.

## Step 2: Read Issue

```bash
viban get $ISSUE_ID
```

Display the issue title, description, priority, and type to the user.

## Step 3: Evaluate Clarity → Proceed Immediately

Assess whether the issue description provides enough context to start working.

- **Clear** → **proceed directly to Step 4. Do NOT ask the user for confirmation. Do NOT ask "should I start?". Just start.**
- **Unclear** → interview the user with AskUserQuestion to gather missing context, then proceed to Step 4 immediately.

## Step 4: Execute Workflow

Follow the workflow from Step 0. If no workflow was found, use this default pipeline:

### 4.1 Analyze
- Explore the codebase to understand the issue
- Identify root cause and scope of change

### 4.2 Implement
- Create a branch: `git checkout -b issue-{ISSUE_ID}`
- Make the fix/feature changes
- Write or update tests as appropriate

### 4.3 Verify
- Run build and tests to confirm the fix works
- Verify no regressions

### 4.4 Ship (MANDATORY — execute ALL 4 commands in sequence)

```bash
# 1. Commit
git add -A
git commit -m "fix: {description} (#$ISSUE_ID)"

# 2. Push
git push -u origin issue-$ISSUE_ID

# 3. Create PR (REQUIRED — do NOT skip)
gh pr create --title "fix: {description}" --body "Resolves #$ISSUE_ID

## Summary
{what was changed and why}

## Test plan
{how it was verified}"

# 4. Move to review (REQUIRED — do NOT skip)
viban review $ISSUE_ID
```

**If any command fails**: fix the error and retry. Do NOT skip any step.

### Completion Checklist (ALL must be true before you stop)

- [ ] PR created (you have a PR URL)
- [ ] `viban review` called (issue status is "review")
- [ ] Completion message includes PR URL

```
Issue #{id} resolved → review
  Title: {title}
  PR: {pr_url}
```

**If you don't have a PR URL or haven't called `viban review`, you are NOT done. Go back and do it.**

---

## CRITICAL

> - **NEVER read or write `viban.json` directly** — always use `viban` CLI commands (`viban assign`, `viban get`, `viban list`, etc.)
> - **FORBIDDEN: `viban done`** — do NOT use `viban done` or `viban done --remove`. Cards must go to review, not done.
> - **MUST create a PR** via `gh pr create` unless the workflow explicitly says "stop before PR".
> - **MUST call `viban review`** after PR creation. This is the ONLY way to finish. Do NOT use any other status change.
> - **MUST include PR URL** in the completion report. No URL = not done.

## CLI Reference

| Command | Description |
|---------|-------------|
| `viban assign [session]` | Assign issue |
| `viban get <id>` | View issue |
| `viban review [id]` | Move to review (use this to finish) |
