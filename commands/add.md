---
description: "Register a problem as a viban issue"
---

> Tip: Run `/clear` before `/viban:add` for a clean context.

# /add - Register Issue

Register a problem as a viban issue. No codebase exploration, no solutions — symptoms only.

> **CLI only** (no direct viban.json access)

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

**Skip** unless the issue clearly needs upfront design. Most issues don't.

Only suggest plan mode when:
- The issue spans multiple subsystems or requires architectural decisions
- The description is too vague to act on without investigation
- P0 issues where a wrong fix could make things worse

**Do NOT suggest** for: single-file fixes, straightforward bugs, feature additions with clear scope, chores, refactors with obvious targets.

When suggesting, use AskUserQuestion:

- header: "Next step", question: "This looks complex — want to plan before working on it?"
- options:
  - "Plan now" — Enter plan mode to analyze and design a solution
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

> **Bias towards skipping.** When in doubt, just register and finish.

## Rules

### READ-ONLY MODE — This skill must NOT modify any files.

**Allowed tools (whitelist — everything else is FORBIDDEN):**
- `Bash`: ONLY for `viban add`, `viban list`, `cat .viban/workflow.md`, `mkdir -p .viban/plans`
- `Write`: ONLY for `/tmp/viban-desc.md` (temp file for `--desc-file`) and `.viban/plans/*.md` (plan output)
- `AskUserQuestion`: for clarification and plan mode suggestion
- `EnterPlanMode`: when user chooses to plan
- `Read`: for reading `.viban/workflow.md` and `.viban/plans/`

**FORBIDDEN tools and actions:**
- `Edit`: NEVER use. No file modifications of any kind.
- `Write` to any path outside `/tmp/viban-*.md` and `.viban/plans/`: FORBIDDEN.
- `Bash` for anything other than `viban` CLI and `cat`/`mkdir` above: FORBIDDEN.
- No `git` commands. No source code reads. No codebase exploration.

### Additional rules:
- **NEVER read or write `viban.json` directly** — always use `viban` CLI commands
- No solution proposals in the issue — symptoms only
- Check duplicates first: `viban list`
- P0 is system-down only
- After Step 6 completes (plan saved or skipped), the skill is **done**. Do not continue.
