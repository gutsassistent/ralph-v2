# Ralph v2 — Iterative AI Build System

A disciplined, iterative approach to AI-assisted development. Designed to work with [Emdash](https://emdash.sh) or any coding agent orchestrator.

## What is this?

Ralph v2 turns AI coding agents into reliable builders by enforcing:
- **One task per iteration** — no scope creep, no cascading failures
- **File-based state** — progress, lessons, and failures tracked in files, not context windows
- **Git commit per step** — full rollback capability at any point
- **Loop detection** — stuck agents stop automatically after 3 identical failures
- **Adaptive replanning** — plans update when reality changes

## Quick Start

### Option A: Copy into existing project
```bash
# From your project root:
cp -r /path/to/ralph-v2-template/ralph ./ralph
cp /path/to/ralph-v2-template/CLAUDE.md ./CLAUDE.md  # merge with existing if needed
```

### Option B: Use init script
```bash
bash /path/to/ralph-v2-template/scripts/init.sh "Description of what you're building"
```

### Then:
1. Edit `ralph/spec.md` — define what you're building
2. Open project in Emdash (or your orchestrator)
3. First agent (normal Emdash session): `"Read ralph/spec.md, explore the codebase, create implementation plan in ralph/progress.md"`
4. Review the plan
5. Run `bash scripts/ralph.sh` in each worktree — the script spawns a fresh agent session per iteration (clean context)

## Directory Structure

```
ralph/
├── progress.md      # Plan + current state (source of truth)
├── spec.md          # What we're building + acceptance criteria
├── lessons.md       # Learnings across iterations (agents read this first)
├── failures.log     # Failed attempts for loop detection
└── archive/         # Previous run states (automatic)

CLAUDE.md            # Agent rules (Ralph v2 discipline)
```

## How It Works

```
┌─────────────┐
│  You write   │
│  ralph/spec  │
└──────┬──────┘
       ▼
┌─────────────┐
│ Planning     │  Agent creates numbered plan
│ Agent        │  You review and approve
└──────┬──────┘
       ▼
┌─────────────────────────────────────────┐
│ Emdash (worktrees) + ralph.sh (loop)    │
│                                         │
│ Worktree A: ralph.sh → steps 1-4       │
│ Worktree B: ralph.sh → steps 5-7       │
│ Each iteration = fresh agent session    │
└──────┬──────────────────────────────────┘
       ▼
┌─────────────┐
│ You review   │  Diffs, progress, merge
│ and merge    │
└─────────────┘
```

## Key Concepts

### State over Memory
Agents don't remember between iterations. Everything lives in files:
- `progress.md` — what's done, what's next
- `lessons.md` — what to avoid
- `failures.log` — what's been tried and failed

### One Thing at a Time
Each iteration: read state → do ONE step → verify → save state → commit. No exceptions.

### Replanning is Normal
After 3 consecutive failures or when the approach is wrong, agents rewrite the plan from current state. This isn't failure — it's adaptation.

### Lessons Compound
Every failure adds to `lessons.md`. Every future iteration reads it. Mistakes happen once, not repeatedly.

## Recommended: Emdash

[Emdash](https://emdash.sh) provides the orchestration layer:
- Visual dashboard showing all agents
- Git worktree isolation per agent
- Side-by-side diff review
- Supports 20+ CLI agents (Claude Code, Codex, etc.)

Ralph v2 provides the per-agent discipline. Emdash provides the multi-agent orchestration. Together they form a complete system.

## License

MIT
