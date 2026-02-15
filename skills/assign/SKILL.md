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

## Step 3: Evaluate Clarity

Assess whether the issue description provides enough context to start working:

- **Clear**: the symptom, affected area, and expected behavior are all understandable
- **Unclear**: vague description, missing context, ambiguous scope, or multiple possible interpretations

### If Unclear

Interview the user with AskUserQuestion to gather missing context. Ask about:
- What specifically is the problem? (symptom)
- Where does it happen? (location/trigger)
- What is the expected behavior?
- Any additional constraints or context?

After gathering answers, update the issue description:

```bash
cat > /tmp/viban-desc-update.md <<'VIBAN_EOF'
{original description}

## Clarification
{gathered context from interview}
VIBAN_EOF

# Re-add the issue with enriched description (edit via TUI or recreate)
```

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

### 4.4 Ship (MANDATORY)

Every step below is **required** unless the workflow explicitly says to stop earlier.

```bash
# 1. Commit
git add -A
git commit -m "fix: {description} (#$ISSUE_ID)"

# 2. Push
git push -u origin issue-$ISSUE_ID

# 3. Create PR (REQUIRED — do NOT skip this)
gh pr create --title "fix: {description}" --body "Resolves #$ISSUE_ID

## Summary
{what was changed and why}

## Test plan
{how it was verified}"
```

**If `gh pr create` fails**: fix the error and retry. Do NOT skip PR creation.

## Step 5: Move to Review

After PR is created:

```bash
viban review $ISSUE_ID
```

Report completion with the PR URL:

```
Issue #{id} resolved → review
  Title: {title}
  PR: {pr_url}
```

**Do NOT report completion without a PR URL.**

---

## CRITICAL

> - **NEVER read or write `viban.json` directly** — always use `viban` CLI commands (`viban assign`, `viban get`, `viban list`, `viban done`, etc.)
> - **MUST create a PR** via `gh pr create` unless the workflow explicitly says "stop before PR".
> - **MUST call `viban review`** after PR creation. Do NOT finish without moving the issue to review.
> - **MUST include PR URL** in the completion report. No URL = not done.

## CLI Reference

| Command | Description |
|---------|-------------|
| `viban assign [session]` | Assign issue |
| `viban get <id>` | View issue |
| `viban done <id>` | Mark as done (non-destructive) |
| `viban done <id> --remove` | Delete card permanently |
| `viban review [id]` | Move to review |
