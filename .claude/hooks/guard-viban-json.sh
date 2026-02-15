#!/bin/bash
# Guard: block direct Edit/Write to viban.json — use viban CLI instead
input=$(cat)
file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)

if [[ "$file_path" == *"viban.json"* ]]; then
  echo "BLOCKED: Do not edit viban.json directly. Use viban CLI commands:"
  echo "  viban done <id>          # Mark as done"
  echo "  viban review [id]        # Move to review"
  echo "  viban assign [session]   # Assign issue"
  echo "  viban add ...            # Create issue"
  echo "  viban priority <id> <P>  # Set priority"
  exit 1
fi
