---
description: "Register a problem as a viban issue"
---

# /add - Register Issue

Register a problem as a viban issue. No codebase exploration, no solutions — symptoms only.

**Input**: `$ARGUMENTS`

## Step 1: Clarify (only if vague)

If clear enough (who/what/where), skip to Step 2. Otherwise, one AskUserQuestion:
- header: "Problem", question: "Can you describe the symptom more specifically?"
- options: context-appropriate (e.g. "Error/crash", "Feature not working", "Performance issue", "Let me describe")

## Step 2: Priority & Type

Infer from description. Don't ask unless truly ambiguous.

| Priority | Condition | Type | When |
|----------|-----------|------|------|
| P0 | System down, data loss | bug | Something broken |
| P1 | Feature broken, errors | feat | New functionality |
| P2 | Performance, warnings | chore | Maintenance, config |
| P3 | Improvements, refactoring | refactor | Code restructuring |

## Step 3: Issue Numbering

```bash
[ -f ".viban/workflow.md" ] && cat ".viban/workflow.md"
```

- Workflow says **Manual** → ask user for external ID (e.g. `PROJ-42`)
- **Auto** or no workflow → let viban auto-assign
- ID in `$ARGUMENTS` → use it regardless

## Step 4: Register

```bash
cat > /tmp/viban-desc.md <<'VIBAN_EOF'
## Symptoms
{one-sentence symptom}
{additional context, if any}
VIBAN_EOF

# Auto numbering (default)
viban add "{title}" --desc-file /tmp/viban-desc.md --priority {priority} --type {type}

# Manual numbering (when workflow specifies)
viban add "{title}" --desc-file /tmp/viban-desc.md --priority {priority} --type {type} --ext-id "{external_id}"
```

Use `<<'VIBAN_EOF'` (quoted) to prevent shell interpretation.

## Step 5: Report

```
Issue #{id} registered
  Title: {title}
  Priority: {priority} | Type: {type}
  Status: backlog
```

## Step 6: Suggest Plan Mode

**Skip** for trivial issues (typo, one-liner config, simple copy edit).
**Recommend** for everything else. Use AskUserQuestion:

- header: "Next step", question: "Want to start planning the solution now?"
- options:
  - "Plan now (Recommended)" — Enter plan mode to analyze and design a solution
  - "Later" — Just register, work on it later

**"Plan now"**: `EnterPlanMode` → after approval, save to `.viban/plans/{issue-id}.md`:

```bash
mkdir -p .viban/plans
```

```markdown
# Plan: {issue title}
> Issue #{id} | {priority} | {type} | Created: {timestamp}

{full plan content}
```

Report: `Plan saved to .viban/plans/{issue-id}.md — /viban:assign will auto-load it.`

**"Later"**: end skill.

> **Bias towards planning.** When in doubt, suggest plan mode.

## Rules

- No codebase exploration — assignee does that in `/viban:assign`
- No solution proposals — symptoms only
- Check duplicates first: `viban list`
- P0 is system-down only
