---
name: sync
description: "Sync viban board with external issue tracker (GitHub, Jira, etc.)"
---

# /sync - External Issue Tracker Sync

Sync the viban board with an external issue tracker. Currently supports GitHub Issues via `gh` CLI.

> **Principle**: Show what will happen before doing it. Never sync without user confirmation.

## Input

**User Input**: `$ARGUMENTS`

## Step 1: Check Sync Configuration

```bash
# Check if sync is already configured
if [ -f ".viban/sync.json" ]; then
    echo "Sync configured"
    viban sync --status
else
    echo "Sync not configured"
fi
```

- If **not configured**, proceed to Step 2
- If **configured**, skip to Step 3

## Step 2: Initialize Sync

```bash
viban sync --init
```

This will:
- Auto-detect the provider from git remote (defaults to GitHub)
- Check that `gh` CLI is installed and authenticated
- Create required labels on the remote repo
- Initialize `sync.json` metadata

If initialization fails, report the error and suggest fixes (install `gh`, run `gh auth login`, etc.).

## Step 3: Preview Changes (Dry Run)

```bash
viban sync --dry-run
```

Show the user what will happen:
- `<-` Issues to pull from remote
- `->` Cards to push to remote
- `==` Unchanged items
- `!!` Conflicts (and resolution strategy)

## Step 4: Confirm and Sync

Ask the user for confirmation using AskUserQuestion:

- header: "Sync"
- question: "Apply these sync changes?"
- options:
  - "Yes, sync now"
  - "Sync and push new local cards too (--push-new)"
  - "Pull only (remote -> local)"
  - "Cancel"
- multiSelect: false

Based on the answer:

```bash
# Yes, sync now
viban sync

# With push-new
viban sync --push-new

# Pull only
viban sync --pull-only
```

## Step 5: Report Results

Show the sync summary:
```
Sync complete:
  Pulled: N new/updated cards from remote
  Pushed: N cards to remote
  Conflicts: N (resolved by: remote wins)
  Unchanged: N
```

## Notes

- **First sync imports all open issues** as backlog cards with `github:N` external IDs
- **Conflicts**: when both sides changed, remote wins by default (with warning)
- **Closed issues**: remote closed issues move viban card to `review` status
- **Done cards**: `viban done` then sync closes the remote issue
- **New local cards** are NOT pushed unless `--push-new` is specified (local-first default)
