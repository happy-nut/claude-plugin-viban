---
name: add
description: "Register a problem as a viban issue"
---

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
mkdir -p .viban/tmp
cat > .viban/tmp/desc.md <<'VIBAN_EOF'
## Symptoms
{one-sentence symptom}
{additional context, if any}
VIBAN_EOF

# Auto numbering (default)
viban add "{title}" --desc-file .viban/tmp/desc.md --priority {priority} --type {type}
rm -f .viban/tmp/desc.md

# Manual numbering (when workflow specifies)
viban add "{title}" --desc-file .viban/tmp/desc.md --priority {priority} --type {type} --ext-id "{external_id}"
rm -f .viban/tmp/desc.md
```

Use `<<'VIBAN_EOF'` (quoted) to prevent shell interpretation.

## Step 5: Report

```
Issue #{id} registered
  Title: {title}
  Priority: {priority} | Type: {type}
  Status: backlog
```

## Step 6: Done

Report the registered issue and **stop immediately**. Do not suggest next steps, do not offer to plan, do not continue.

> **This skill ends here. No exceptions.**

## Rules

### READ-ONLY MODE — This skill must NOT modify any files.

**Allowed tools (whitelist — everything else is FORBIDDEN):**
- `Bash`: ONLY for `mkdir -p .viban/tmp`, `viban add`, `viban list`, `cat .viban/workflow.md`, `rm -f .viban/tmp/desc.md`
- `Write`: ONLY for `.viban/tmp/desc.md` (temp file for `--desc-file`)
- `AskUserQuestion`: for clarification
- `Read`: for reading `.viban/workflow.md`

**FORBIDDEN tools and actions:**
- `Edit`: NEVER use. No file modifications of any kind.
- `Write` to any path outside `/tmp/viban-*.md` and `.viban/plans/`: FORBIDDEN.
- `Bash` for anything other than `viban` CLI and `cat`/`mkdir` above: FORBIDDEN.
- No `git` commands. No source code reads. No codebase exploration.

## CLI Reference

| Command | Description |
|---------|-------------|
| `viban list` | Print board (check for duplicates) |
| `viban add "<title>" --desc-file <f> --priority <p> --type <t>` | Register issue |
| `viban add "<title>" ... --ext-id "<id>"` | Register with external ID |

### Additional rules:
- **NEVER read or write `viban.json` directly** — always use `viban` CLI commands
- No solution proposals in the issue — symptoms only
- Check duplicates first: `viban list`
- P0 is system-down only
- After Step 6 completes (plan saved or skipped), the skill is **done**. Do not continue.
