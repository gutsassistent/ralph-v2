#!/bin/bash
# Ralph v2 — Iterative AI Build Loop
# Each iteration spawns a FRESH agent session (clean context).
# Usage: ./scripts/ralph.sh [options]
#
# Options:
#   --tool claude|codex|amp    Agent CLI to use (default: claude)
#   --model <model>            Model override (e.g. claude-sonnet-4-5)
#   --max <N>                  Max iterations (default: 50)
#   --step <N>                 Start from specific step number
#   --dry-run                  Show what would run, don't execute

set -e

# --- Config ---
TOOL="claude"
MODEL=""
MAX_ITERATIONS=50
START_STEP=""
DRY_RUN=false
RALPH_DIR="ralph"
PROGRESS_FILE="$RALPH_DIR/progress.md"
LESSONS_FILE="$RALPH_DIR/lessons.md"
FAILURES_FILE="$RALPH_DIR/failures.log"

# --- Parse args ---
while [[ $# -gt 0 ]]; do
  case $1 in
    --tool)    TOOL="$2"; shift 2 ;;
    --tool=*)  TOOL="${1#*=}"; shift ;;
    --model)   MODEL="$2"; shift 2 ;;
    --model=*) MODEL="${1#*=}"; shift ;;
    --max)     MAX_ITERATIONS="$2"; shift 2 ;;
    --max=*)   MAX_ITERATIONS="${1#*=}"; shift ;;
    --step)    START_STEP="$2"; shift 2 ;;
    --step=*)  START_STEP="${1#*=}"; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    *)         echo "Unknown option: $1"; exit 1 ;;
  esac
done

# --- Validate ---
if [ ! -f "$PROGRESS_FILE" ]; then
  echo "Error: $PROGRESS_FILE not found. Run scripts/init.sh first."
  exit 1
fi

if [ ! -f "CLAUDE.md" ]; then
  echo "Error: CLAUDE.md not found."
  exit 1
fi

# --- Build prompt ---
build_prompt() {
  local iteration=$1
  cat << 'PROMPT'
You are a worker agent in a Ralph v2 iterative build loop. This is a SINGLE iteration — do ONE step, then stop.

## Your task for this iteration:

1. Read `ralph/lessons.md` — learn what to avoid
2. Read `ralph/failures.log` — check for repeated failures (3x same hash = STOP)
3. Read `ralph/progress.md` — find the first step with status NOT STARTED or IN PROGRESS
4. Execute ONLY that one step
5. Verify: run the project's test/build commands
6. Update `ralph/progress.md` with the result
7. If you failed: append to `ralph/failures.log` (format: `iteration:N|action:description|error:message|hash:short`) and add a lesson to `ralph/lessons.md`
8. If you succeeded: mark the step as DONE in `ralph/progress.md`
9. `git add -A && git commit -m "ralph: step N - [description]"`

## Critical rules:
- Do EXACTLY ONE step. Not two. Not "one and a quick fix".
- If the same failure hash appears 3x in failures.log, write STUCK in progress.md and output: <signal>STUCK</signal>
- If ALL steps are DONE, output: <signal>COMPLETE</signal>
- If a step is BLOCKED, skip to the next NOT STARTED step. If all remaining are BLOCKED, output: <signal>BLOCKED</signal>
- Do NOT touch files unrelated to the current step
- Do NOT refactor or clean up unless that IS the current step
- If the plan needs changing, update the plan FIRST, commit it separately, THEN proceed

PROMPT
  echo ""
  echo "Current iteration: $iteration"
}

# --- Tool command ---
run_agent() {
  local iteration=$1
  local prompt
  prompt=$(build_prompt "$iteration")

  case "$TOOL" in
    claude)
      local model_flag=""
      if [ -n "$MODEL" ]; then
        model_flag="--model $MODEL"
      fi
      echo "$prompt" | claude --dangerously-skip-permissions $model_flag --print 2>&1
      ;;
    codex)
      local model_flag=""
      if [ -n "$MODEL" ]; then
        model_flag="-m $MODEL"
      fi
      codex exec --dangerously-bypass-approvals-and-sandbox $model_flag "$prompt" 2>&1
      ;;
    amp)
      echo "$prompt" | amp --dangerously-allow-all 2>&1
      ;;
    *)
      echo "Error: Unknown tool '$TOOL'"
      exit 1
      ;;
  esac
}

# --- Loop detection ---
check_stuck() {
  if [ ! -f "$FAILURES_FILE" ] || [ ! -s "$FAILURES_FILE" ]; then
    return 1
  fi
  
  # Extract hashes, find any that appear 3+ times
  local stuck_hash
  stuck_hash=$(grep -oP 'hash:\K\S+' "$FAILURES_FILE" 2>/dev/null | sort | uniq -c | sort -rn | head -1)
  
  if [ -n "$stuck_hash" ]; then
    local count
    count=$(echo "$stuck_hash" | awk '{print $1}')
    if [ "$count" -ge 3 ]; then
      return 0  # stuck
    fi
  fi
  return 1  # not stuck
}

# --- Progress check ---
count_done() {
  grep -c '\[x\]' "$PROGRESS_FILE" 2>/dev/null || echo 0
}

count_total() {
  grep -cE '\[[ x]\]' "$PROGRESS_FILE" 2>/dev/null || echo 0
}

# --- Main loop ---
echo "╔══════════════════════════════════════════════════╗"
echo "║  Ralph v2 — Iterative Build Loop                ║"
echo "║  Tool: $TOOL $([ -n "$MODEL" ] && echo "($MODEL)" || echo "")                        "
echo "║  Max iterations: $MAX_ITERATIONS                         "
echo "╚══════════════════════════════════════════════════╝"
echo ""

if $DRY_RUN; then
  echo "[DRY RUN] Would run $MAX_ITERATIONS iterations with $TOOL"
  echo "[DRY RUN] Prompt preview:"
  build_prompt 1
  exit 0
fi

STALL_COUNT=0
LAST_DONE_COUNT=$(count_done)

for i in $(seq 1 $MAX_ITERATIONS); do
  echo ""
  echo "┌──────────────────────────────────────────────────┐"
  echo "│  Iteration $i/$MAX_ITERATIONS — $(count_done)/$(count_total) steps done"
  echo "└──────────────────────────────────────────────────┘"
  
  # Pre-flight: check if stuck
  if check_stuck; then
    echo "🛑 STUCK detected in failures.log — stopping loop."
    echo "   Check ralph/failures.log and ralph/progress.md for details."
    exit 2
  fi
  
  # Run agent
  OUTPUT=$(run_agent "$i" | tee /dev/stderr) || true
  
  # Check signals
  if echo "$OUTPUT" | grep -q "<signal>COMPLETE</signal>"; then
    echo ""
    echo "✅ All steps complete! Finished at iteration $i."
    exit 0
  fi
  
  if echo "$OUTPUT" | grep -q "<signal>STUCK</signal>"; then
    echo ""
    echo "🛑 Agent reported STUCK at iteration $i."
    echo "   Check ralph/failures.log for repeated failures."
    exit 2
  fi
  
  if echo "$OUTPUT" | grep -q "<signal>BLOCKED</signal>"; then
    echo ""
    echo "⚠️  All remaining steps are BLOCKED at iteration $i."
    echo "   Check ralph/progress.md for blocked reasons."
    exit 3
  fi
  
  # Progress stall detection
  CURRENT_DONE=$(count_done)
  if [ "$CURRENT_DONE" -eq "$LAST_DONE_COUNT" ]; then
    STALL_COUNT=$((STALL_COUNT + 1))
    if [ "$STALL_COUNT" -ge 5 ]; then
      echo ""
      echo "⚠️  No progress in 5 iterations — possible stall."
      echo "   Consider reviewing ralph/progress.md and ralph/failures.log."
      # Don't exit — maybe the agent is working on a multi-iteration step
      STALL_COUNT=0  # Reset to give another 5
    fi
  else
    STALL_COUNT=0
    LAST_DONE_COUNT=$CURRENT_DONE
  fi
  
  echo ""
  echo "   Progress: $(count_done)/$(count_total) steps done"
  
  # Brief pause between iterations
  sleep 2
done

echo ""
echo "⏰ Reached max iterations ($MAX_ITERATIONS) without completing all steps."
echo "   Progress: $(count_done)/$(count_total) steps done"
echo "   Check ralph/progress.md for current state."
exit 1
