#!/bin/bash
# Ralph v2 — Initialize in an existing project
# Usage: bash init.sh "Project description"
# Run this from your project root

set -e

DESC="${1:-New project}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE_DIR="$(dirname "$SCRIPT_DIR")"

if [ -d "ralph" ]; then
  echo "ralph/ directory already exists."
  read -p "Overwrite? (y/N) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
  fi
  rm -rf ralph
fi

# Copy ralph directory
cp -r "$TEMPLATE_DIR/ralph" ./ralph

# Update spec with description
sed -i "s|<!-- Describe the project/feature clearly -->|$DESC|" ralph/spec.md

# Handle CLAUDE.md
if [ -f "CLAUDE.md" ]; then
  echo ""
  echo "CLAUDE.md already exists in this project."
  echo "You should merge Ralph v2 rules into it."
  echo ""
  echo "Ralph v2 CLAUDE.md available at:"
  echo "  $TEMPLATE_DIR/CLAUDE.md"
  echo ""
  echo "Key sections to add:"
  echo "  - Core Loop (read state → do one thing → verify → save → commit)"
  echo "  - State Files (ralph/progress.md, ralph/lessons.md, ralph/failures.log)"
  echo "  - Per-Iteration Rules (checklist)"
  echo "  - Replanning triggers"
  echo "  - Anti-Patterns"
else
  cp "$TEMPLATE_DIR/CLAUDE.md" ./CLAUDE.md
  echo "Created CLAUDE.md with Ralph v2 rules."
fi

echo ""
echo "Ralph v2 initialized."
echo ""
echo "Files created:"
echo "  ralph/spec.md       ← EDIT THIS: define what you're building"
echo "  ralph/progress.md   ← agents maintain this"
echo "  ralph/lessons.md    ← agents learn here"  
echo "  ralph/failures.log  ← loop detection"
echo ""
echo "Next steps:"
echo "  1. Edit ralph/spec.md"
echo "  2. Open in Emdash"
echo "  3. First agent: 'Read ralph/spec.md, create plan in ralph/progress.md'"
