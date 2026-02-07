---
name: task
description: "Analyze problem and register as viban issue with evidence"
enter_plan_mode: true
---

# /task - Problem Analysis and Issue Registration

Analyze problem situation and register as viban issue with file locations and evidence.

> **Core Principle**: Focus on **symptoms and problem definition**, not solutions.
> Solutions are decided by the assignee after understanding full context.

## Interview Phase (Required)

**Always start with an interview** to gather complete context before exploring code.

### Interview Questions

Use AskUserQuestion to ask these questions (can combine related ones):

**1. Problem Identification**
```
What problem are you experiencing?

- Error message or unexpected behavior
- What feature/page is affected
- When did it start happening
```

**2. Reproduction Context**
```
How can this be reproduced?

- Step-by-step actions
- Environment (local/staging/production)
- Frequency (always/sometimes/once)
```

**3. Expected vs Actual**
```
What should happen vs what actually happens?

- Expected behavior
- Actual result
- Any error messages or logs
```

**4. Additional Context** (optional, ask if needed)
```
Any additional context?

- Recent changes that might be related
- Workarounds tried
- Related issues or features
```

### Interview Strategy

- Ask 1-2 questions at a time using AskUserQuestion
- Provide options when possible for faster responses
- Stop interviewing when you have enough to:
  1. Search for relevant code
  2. Determine priority and type
  3. Write clear symptoms

## Execution Steps

### Step 1: Problem Identification (from interview)

From the interview responses, extract:
1. **Symptoms**: Clearly define what the problem is
2. **Keywords**: Error messages, feature names, module names
3. **Priority**:
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

## Example Interview Flow

**User runs**: `/viban:task`

**Agent**: (AskUserQuestion)
```
What problem are you experiencing?

Options:
- Something is broken/erroring
- Feature not working as expected
- Performance issue
- Need new feature/improvement
- Other
```

**User selects**: "Something is broken/erroring"

**Agent**: (AskUserQuestion)
```
Please describe the error:

1. What action triggers it?
2. What error message do you see?
3. Which page/feature is affected?
```

**User responds**: "When I click the chart on backtest results, nothing happens. Console shows 'Cannot read property of undefined'"

**Agent**: Now has enough context to:
1. Search for chart-related code in backtest
2. Look for the specific error pattern
3. Register issue with proper details

## Important Notes

- **Interview First**: Always gather context before code exploration
- **Location Required**: Do not register without file path
- **Evidence Required**: Do not register based on guesses without code exploration
- **Avoid Solutions**: Do not write specific solutions (assignee decides)
- **Check Duplicates**: Check existing issues before registration
  ```bash
  viban list
  ```
- **Accurate Priority**: P0 only for system-down level, avoid over-estimation
