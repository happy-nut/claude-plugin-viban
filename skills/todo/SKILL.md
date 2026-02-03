---
name: viban:todo
description: "Analyze problem situation and register as viban issue (focus on symptoms and problem definition)"
category: development
complexity: medium
mcp-servers: []
personas: []
---

# /viban:todo - Problem Analysis and Issue Registration

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

```bash
viban add "{short_title}" "$'## Symptoms\n...(body)'" {priority} {type}
```

**Parameters**:
- `title`: Plain title (no tags)
- `description`: Issue body (Markdown)
- `priority`: P0, P1, P2, P3 (default: P3)
- `type`: bug, feat, chore, refactor

**Examples**:
```bash
# BUG issue
viban add "API response timeout" "$'## Symptoms\n...'" P1 bug

# FEATURE issue
viban add "Dark mode support" "$'## Symptoms\n...'" P2 feat

# REFACTOR issue
viban add "Separate auth logic" "$'## Symptoms\n...'" P3 refactor
```

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
viban add "Backtest results chart not displayed" "$'## Symptoms\n...'" P1 bug
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
