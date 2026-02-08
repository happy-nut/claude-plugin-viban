---
description: "Analyze problem and register as viban issue with evidence"
---

# /add - Problem Analysis and Issue Registration

Analyze problem situation and register as viban issue with file locations and evidence.

> **Core Principle**: Focus on **symptoms and problem definition**, not solutions.
> Solutions are decided by the assignee after understanding full context.

## Input Verification

**User Input**: `$ARGUMENTS`

If input is empty or unclear:
1. Use AskUserQuestion to ask about the problem
2. Proceed after receiving response

## Execution Steps

### Step 1: Problem Identification

Analyze the problem described by user:
1. **Identify symptoms**: Clearly define what the problem is
2. **Extract keywords**: Error messages, feature names, module names, etc.
3. **Determine priority**:
   | Condition | Priority |
   |-----------|----------|
   | System down, data loss | P0 |
   | Feature broken, errors | P1 |
   | Performance degradation, warnings | P2 |
   | Improvements, refactoring | P3 |

### Step 2: Codebase Exploration

**Required**: Must find code location related to the problem

1. **Search by keywords**:
   ```bash
   # Search by error message or function name
   grep -r "keyword" . --include="*.py" --include="*.ts" --include="*.tsx" --include="*.js" --include="*.jsx"
   ```

2. **Check related files**:
   - Find module where error occurred
   - Check stack trace files if available
   - For API endpoints: trace router → use case → domain

3. **Collect location information**:
   - File path: relative to project root
   - Function/class name
   - Line number (if possible)

### Step 3: Issue Body Composition

Write issue body in this format:

```markdown
## Symptoms
One-sentence summary of what happened.
- Frequency: (if known)
- Affected features:

## Reproduction Steps
1. Step-by-step reproduction
2. ...
3. Environment: local/staging/production

## Expected Result
- How it should work normally

## Actual Result
- The problem that actually occurred

## Stack Trace (if available)
```
Error log or stack trace
```

## Location
- File: `path/to/file.ext`
- Function/Class:
- Line: (if known)

## Possible Cause (hypothesis)
- Estimate which code/condition is causing the problem
- List items to verify (not solutions)

## Meta Information
- Registered: (current timestamp)
- Reporter: user
```

### Step 4: Register viban Issue

Write the description body to a temp file using a heredoc, then pass via `--desc-file`:

```bash
cat > /tmp/viban-desc.md <<'VIBAN_EOF'
## Symptoms
One-sentence summary...

## Reproduction Steps
1. ...

## Location
- File: `path/to/file.ext`
VIBAN_EOF

viban add "{short_title}" --desc-file /tmp/viban-desc.md --priority {priority} --type {type}
```

**Why heredoc?** Using `<<'VIBAN_EOF'` (single-quoted delimiter) prevents shell interpretation of backticks, `$`, parentheses, and other special characters in the description.

**Parameters**:
- `title`: Plain title (no tags) — first positional argument
- `--desc-file`: Path to file containing issue body (Markdown)
- `--priority`: P0, P1, P2, P3 (default: P3)
- `--type`: bug, feat, chore, refactor
- `--attach`: (optional) File paths to attach (screenshots, logs, etc.)

**Examples**:
```bash
# BUG issue
cat > /tmp/viban-desc.md <<'VIBAN_EOF'
## Symptoms
API responds with 504 after 30 seconds.
- File: `src/api/handler.ts:42`
VIBAN_EOF
viban add "API response timeout" --desc-file /tmp/viban-desc.md --priority P1 --type bug

# FEATURE issue
cat > /tmp/viban-desc.md <<'VIBAN_EOF'
## Symptoms
Users request dark mode support.
VIBAN_EOF
viban add "Dark mode support" --desc-file /tmp/viban-desc.md --priority P2 --type feat

# With screenshot attachments
cat > /tmp/viban-desc.md <<'VIBAN_EOF'
## Symptoms
Layout broken on mobile viewport.
VIBAN_EOF
viban add "Layout broken on mobile" --desc-file /tmp/viban-desc.md --priority P1 --type bug --attach ./screenshots/mobile-bug.png
```

### Step 4a: Attaching Screenshots (Recommended for Visual Issues)

For visual bugs (layout issues, UI glitches, rendering problems), attaching screenshots significantly helps:

1. **Take a screenshot** of the problem:
   - macOS: `Cmd + Shift + 4` (selection) or `Cmd + Shift + 3` (full screen)
   - Save to project directory: `./screenshots/` or `./.viban/attachments/`

2. **Attach during creation**:
   ```bash
   viban add "Button misaligned on dashboard" --desc-file /tmp/viban-desc.md --priority P1 --type bug --attach ./screenshots/button-issue.png
   ```

3. **Or attach to existing issue**:
   ```bash
   viban attach {issue_id} ./screenshots/screenshot1.png ./screenshots/screenshot2.png
   ```

4. **View attachments**:
   ```bash
   viban get {issue_id}
   ```

> **Why attach screenshots?**
> - Claude Code can read image files and understand visual context
> - The assignee can see exactly what the problem looks like
> - Reduces back-and-forth clarification

### Step 5: Report Results

After registration, report to user:

```
=== viban Issue Registered ===
- Issue ID: #{id}
- Title: {title}
- Type: {type}
- Priority: {priority}
- Location: {file_path}:{line}
- Status: backlog

Next steps:
- `viban list` to view issue list
- `viban start {id}` to start working
```

## When Input is Missing

Use AskUserQuestion with these prompts:

```
What problem should be registered as an issue?

Please include:
1. What is the problem? (error message, unexpected behavior, etc.)
2. Where does it occur? (page, API, feature, etc.)
3. How to reproduce? (step-by-step)
```

## Example

**Input**: "Charts not showing on backtest results page"

**Analysis Process**:
1. Keywords: backtest, results, chart
2. Code exploration:
   ```bash
   grep -r "chart" . --include="*.tsx" --include="*.ts"
   ```
3. Related file found: `src/pages/backtest/results.tsx`
4. Check chart rendering logic

**Registration Command**:
```bash
cat > /tmp/viban-desc.md <<'VIBAN_EOF'
## Symptoms
Backtest results chart not displayed when clicking chart tab.
- File: `src/pages/backtest/results.tsx`
VIBAN_EOF
viban add "Backtest results chart not displayed" --desc-file /tmp/viban-desc.md --priority P1 --type bug
```

**Registered Issue**:
```
Title: Backtest results chart not displayed
Priority: P1
Type: bug
Location: src/pages/backtest/results.tsx
```

## Important Notes

- **Location Required**: Do not register without file path
- **Evidence Required**: Do not register based on guesses without code exploration
- **Avoid Solutions**: Do not write specific solutions (assignee decides)
- **Check Duplicates**: Check existing issues before registration
  ```bash
  viban list
  ```
- **Accurate Priority**: P0 only for system-down level, avoid over-estimation

## Final Step: Auto Update Check

After completing issue registration, run:

```bash
viban update
```

This silently checks for updates and only outputs if an update is applied.
