---
name: add
description: "Register a problem as a viban issue"
---

# /add - Register Issue

Register a problem as a viban issue. Keep it lightweight — no codebase exploration, no heavy analysis.

> **Principle**: Clarify symptoms only if vague. Don't explore code or propose solutions.

## Input

**User Input**: `$ARGUMENTS`

## Step 1: Clarify (only if needed)

If the user's description is **clear enough** to register (who/what/where), skip to Step 2.

If **vague or ambiguous**, concretize with one AskUserQuestion:

- header: "Problem"
- question: "Can you describe the symptom more specifically?"
- options based on context, e.g.:
  - "Error/crash on specific action"
  - "Feature not working as expected"
  - "Performance issue"
  - "Let me describe"
- multiSelect: false

Goal: get a **one-sentence symptom** clear enough for an assignee to understand.

## Step 2: Determine Priority & Type

Infer from the description. Do NOT ask unless truly ambiguous.

| Condition | Priority |
|-----------|----------|
| System down, data loss | P0 |
| Feature broken, errors | P1 |
| Performance, warnings | P2 |
| Improvements, refactoring | P3 |

| Type | When |
|------|------|
| bug | Something is broken |
| feat | New functionality |
| chore | Maintenance, config |
| refactor | Code restructuring |

## Step 3: Check Workflow for Issue Numbering

```bash
[ -f ".viban/workflow.md" ] && cat ".viban/workflow.md"
```

- If workflow says **Manual** issue numbering → ask user for an external ID (e.g. `PROJ-42`)
- If workflow says **Auto** or no workflow exists → let viban auto-assign
- If user provided a specific ID in `$ARGUMENTS` → use it regardless of workflow

## Step 4: Register

Write the description to a temp file, then register:

```bash
cat > /tmp/viban-desc.md <<'VIBAN_EOF'
## Symptoms
{concretized one-sentence symptom from Step 1}
{additional context from user input, if any}
VIBAN_EOF

# Auto numbering (default)
viban add "{title}" --desc-file /tmp/viban-desc.md --priority {priority} --type {type}

# Manual numbering (when workflow specifies manual)
viban add "{title}" --desc-file /tmp/viban-desc.md --priority {priority} --type {type} --ext-id "{external_id}"
```

**Why heredoc?** `<<'VIBAN_EOF'` prevents shell interpretation of backticks, `$`, etc.

## Step 5: Report

```
Issue #{id} registered
  Title: {title}
  Priority: {priority} | Type: {type}
  Status: backlog
```

## Notes

- **No codebase exploration** — the assignee does that during `/viban:assign`
- **No solution proposals** — focus on symptoms only
- **Check duplicates** before registering: `viban list`
- **Don't over-prioritize** — P0 is system-down only
