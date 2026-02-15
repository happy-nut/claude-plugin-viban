---
name: assign
description: "Assign first backlog issue — clarify if unclear, then finish"
---

# /assign

Assign the first backlog issue. If the description is unclear or lacks context, interview the user and enrich the issue. **Do NOT start implementation.**

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

If a workflow exists, follow its conventions for issue handling.

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

Assess whether the issue description provides enough context for someone to start working on it:

- **Clear**: the symptom, affected area, and expected behavior are all understandable
- **Unclear**: vague description, missing context, ambiguous scope, or multiple possible interpretations

### If Clear

Report the assignment and finish:

```
Issue #{id} assigned
  Title: {title}
  Priority: {priority} | Type: {type}
  Status: in_progress

Ready for work.
```

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

Then report:

```
Issue #{id} assigned and clarified
  Title: {title}
  Priority: {priority} | Type: {type}
  Status: in_progress

Clarification added to issue description.
```

---

## CRITICAL

> - **NEVER read or write `viban.json` directly** — always use `viban` CLI commands (`viban assign`, `viban get`, `viban list`, `viban done`, etc.)
> - This command **assigns only**. Do NOT create branches, write code, or start implementation.
> - If the issue is clear, just report and finish immediately.

## CLI Reference

| Command | Description |
|---------|-------------|
| `viban assign [session]` | Assign issue |
| `viban get <id>` | View issue |
| `viban done <id>` | Mark as done (non-destructive) |
| `viban done <id> --remove` | Delete card permanently |
| `viban review [id]` | Move to review |
