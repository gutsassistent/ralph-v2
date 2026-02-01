#!/bin/bash
# Ralph v2 — Split plan for parallel execution
# Creates a scoped progress.md per worktree with ONLY the assigned steps.
#
# Usage: bash scripts/split-plan.sh <worktree-path> <start-step> <end-step>
# Example: bash scripts/split-plan.sh ./worktree-a 1 4
#
# This copies ralph/ to the worktree and rewrites progress.md
# to contain ONLY the specified steps. The agent literally cannot
# see other steps, so it cannot do them.

set -e

WORKTREE="$1"
START="$2"
END="$3"

if [ -z "$WORKTREE" ] || [ -z "$START" ] || [ -z "$END" ]; then
  echo "Usage: bash scripts/split-plan.sh <worktree-path> <start> <end>"
  echo "Example: bash scripts/split-plan.sh ./worktree-a 1 4"
  exit 1
fi

if [ ! -f "ralph/progress.md" ]; then
  echo "Error: ralph/progress.md not found in current directory."
  exit 1
fi

# Ensure ralph dir exists in worktree
mkdir -p "$WORKTREE/ralph"

# Copy lessons and failures (shared knowledge)
cp ralph/lessons.md "$WORKTREE/ralph/lessons.md"
cp ralph/failures.log "$WORKTREE/ralph/failures.log"
cp ralph/spec.md "$WORKTREE/ralph/spec.md"

# Extract only the assigned steps from progress.md
{
  echo "# Progress"
  echo ""
  echo "## Scope"
  echo "This agent is responsible for steps $START-$END ONLY."
  echo "Do NOT work on any steps outside this range."
  echo "Do NOT explore or implement anything not listed below."
  echo ""
  echo "## Plan"
  
  # Extract numbered steps within range
  grep -E "^[0-9]+\." ralph/progress.md | while IFS= read -r line; do
    step_num=$(echo "$line" | grep -oE "^[0-9]+")
    if [ "$step_num" -ge "$START" ] && [ "$step_num" -le "$END" ]; then
      echo "$line"
    fi
  done
  
  echo ""
  echo "## Current"
  echo "- Working on: Step $START"
  echo "- Iteration: 0"
  echo "- Last action: Initialized (scoped to steps $START-$END)"
  echo "- Last result: Ready"
  echo ""
  echo "## Architecture Decisions"
  # Copy architecture decisions section
  sed -n '/^## Architecture Decisions/,/^## /p' ralph/progress.md | head -n -1
} > "$WORKTREE/ralph/progress.md"

# Copy CLAUDE.md if present
if [ -f "CLAUDE.md" ]; then
  cp CLAUDE.md "$WORKTREE/CLAUDE.md"
fi

# Copy ralph.sh
if [ -f "scripts/ralph.sh" ]; then
  mkdir -p "$WORKTREE/scripts"
  cp scripts/ralph.sh "$WORKTREE/scripts/ralph.sh"
  chmod +x "$WORKTREE/scripts/ralph.sh"
fi

echo "Worktree '$WORKTREE' scoped to steps $START-$END"
echo ""
echo "Files created:"
echo "  $WORKTREE/ralph/progress.md  (steps $START-$END only)"
echo "  $WORKTREE/ralph/lessons.md   (shared)"
echo "  $WORKTREE/ralph/spec.md      (shared)"
echo "  $WORKTREE/ralph/failures.log (clean)"
echo ""
echo "Run: cd $WORKTREE && bash scripts/ralph.sh"
