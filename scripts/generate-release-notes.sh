#!/bin/bash
# Generate release notes from conventional commits
# Usage: ./generate-release-notes.sh [previous_tag] [current_tag]

set -e

PREVIOUS_TAG="${1:-$(git describe --tags --abbrev=0 HEAD^ 2>/dev/null || echo "")}"
CURRENT_TAG="${2:-$(git describe --tags --abbrev=0 HEAD 2>/dev/null || echo "HEAD")}"

# If no previous tag, get all commits
if [[ -z "$PREVIOUS_TAG" ]]; then
  COMMIT_RANGE="$CURRENT_TAG"
else
  COMMIT_RANGE="${PREVIOUS_TAG}..${CURRENT_TAG}"
fi

# Arrays for categorized commits
declare -a FEATURES=()
declare -a FIXES=()
declare -a DOCS=()
declare -a CHORES=()
declare -a OTHERS=()

# Parse commits
while IFS= read -r line; do
  [[ -z "$line" ]] && continue

  # Extract commit message (remove hash prefix if present)
  msg="$line"

  # Categorize by conventional commit prefix
  if [[ "$msg" =~ ^feat(\(.+\))?:\ (.+)$ ]]; then
    FEATURES+=("${BASH_REMATCH[2]}")
  elif [[ "$msg" =~ ^fix(\(.+\))?:\ (.+)$ ]]; then
    FIXES+=("${BASH_REMATCH[2]}")
  elif [[ "$msg" =~ ^docs(\(.+\))?:\ (.+)$ ]]; then
    DOCS+=("${BASH_REMATCH[2]}")
  elif [[ "$msg" =~ ^chore(\(.+\))?:\ (.+)$ ]]; then
    CHORES+=("${BASH_REMATCH[2]}")
  elif [[ "$msg" =~ ^(ci|test|refactor|perf|style|build)(\(.+\))?:\ (.+)$ ]]; then
    CHORES+=("${BASH_REMATCH[3]}")
  else
    # Skip release commits and merge commits
    if [[ ! "$msg" =~ ^(Merge|release|chore:\ release) ]]; then
      OTHERS+=("$msg")
    fi
  fi
done < <(git log --pretty=format:"%s" "$COMMIT_RANGE" 2>/dev/null)

# Generate release notes
generate_section() {
  local title="$1"
  shift
  local items=("$@")

  if [[ ${#items[@]} -gt 0 ]]; then
    echo "## $title"
    echo ""
    for item in "${items[@]}"; do
      # Capitalize first letter
      item="$(echo "${item:0:1}" | tr '[:lower:]' '[:upper:]')${item:1}"
      echo "- $item"
    done
    echo ""
  fi
}

# Output release notes
if [[ -n "$PREVIOUS_TAG" ]]; then
  echo "# What's Changed"
  echo ""
fi

generate_section "Features" "${FEATURES[@]}"
generate_section "Bug Fixes" "${FIXES[@]}"
generate_section "Documentation" "${DOCS[@]}"
generate_section "Maintenance" "${CHORES[@]}"
generate_section "Other Changes" "${OTHERS[@]}"

# Add full changelog link
if [[ -n "$PREVIOUS_TAG" ]]; then
  REPO_URL=$(git remote get-url origin 2>/dev/null | sed 's/\.git$//' | sed 's/git@github.com:/https:\/\/github.com\//')
  if [[ -n "$REPO_URL" ]]; then
    echo "**Full Changelog**: ${REPO_URL}/compare/${PREVIOUS_TAG}...${CURRENT_TAG}"
  fi
fi
