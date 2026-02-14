---
name: assign
description: "Assign first backlog issue — clarify if unclear, then finish"
---

# /assign

Assign the first backlog issue. If the description is unclear or lacks context, interview the user and enrich the issue. **Do NOT start implementation.**

> **CLI only** (no direct viban.json access)

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

> - This command **assigns only**. Do NOT create branches, write code, or start implementation.
> - Do NOT run `viban review` — the issue stays in `in_progress` for the next work session.
> - If the issue is clear, just report and finish immediately.

## CLI Reference

| Command | Description |
|---------|-------------|
| `viban assign [session]` | Assign issue |
| `viban get <id>` | View issue |
