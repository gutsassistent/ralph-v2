# CLAUDE.md — Ralph Loop v2 Worker Discipline

## Core Loop

You are a worker agent in an iterative build system. Every task follows this cycle:

1. **Read state** — Read `ralph/progress.md` and `ralph/lessons.md` before doing anything
2. **Do ONE thing** — Complete exactly one step from the plan. Not two. Not "one and a half."
3. **Verify** — Run tests, lint, and confirm your change works in isolation
4. **Save state** — Update `ralph/progress.md` with what you did and the result
5. **Commit** — `git commit` with a descriptive message: `ralph: step N - [description]`

## State Files

### ralph/progress.md
The source of truth. Format:

```markdown
# Progress

## Plan
1. [x] Step description — DONE (iteration 3)
2. [ ] Step description — IN PROGRESS
3. [ ] Step description — BLOCKED (reason)
4. [ ] Step description — NOT STARTED

## Current
- Working on: Step 2
- Iteration: 7
- Last action: Created auth middleware
- Last result: Tests passing (4/4)

## Architecture Decisions
- Database: PostgreSQL (decided step 1, reason: need relations)
- Auth: JWT tokens (decided step 3)
```

### ralph/lessons.md
What you've learned during this build. Read this FIRST every iteration.

```markdown
# Lessons

- DO NOT use library X — conflicts with Y (discovered iteration 5)
- The config file is at src/config.ts, not root (wasted iteration 4)
- Always run `npm run build` before testing — TypeScript errors aren't caught by jest alone
```

**Rules:**
- After every failure, add a lesson
- After every surprising discovery, add a lesson
- Keep entries short and actionable
- Never delete entries during a run

### ralph/failures.log
Track failed attempts to detect loops.

```
iteration:5|action:fix-auth-middleware|error:Cannot find module './utils'|hash:a3f2c1
iteration:7|action:fix-auth-middleware|error:Cannot find module './utils'|hash:a3f2c1
```

If you see the same hash appear 3 times → STOP. Write to progress.md: `STUCK: [description]`. Do not attempt again.

## Planning Phase

Before any coding, create the plan:

1. Read the task/spec thoroughly
2. Explore the existing codebase (if brownfield)
3. Write `ralph/spec.md` — what you're building, acceptance criteria
4. Write the numbered plan in `ralph/progress.md`
5. Each step must be:
   - Independently completable
   - Testable/verifiable
   - Small enough for one iteration (max ~50 lines changed)

**Do NOT start coding until the plan is written and committed.**

## Per-Iteration Rules

### Before you start:
- [ ] Read `ralph/progress.md` — know where you are
- [ ] Read `ralph/lessons.md` — know what to avoid
- [ ] Check `ralph/failures.log` — are you about to repeat a mistake?
- [ ] Identify the ONE next step

### While working:
- Touch as few files as possible
- If you discover the plan needs changing, update the plan FIRST, commit it, THEN proceed
- If you're unsure about an architecture choice, mark the step as BLOCKED and explain why
- Never "clean up" or "refactor" unless that IS the current step
- No scope creep. If you notice something else that needs fixing, add it to the plan as a new step

### After completing:
- [ ] Run tests (`npm test`, `pytest`, whatever applies)
- [ ] Run linter
- [ ] Update `ralph/progress.md` with result
- [ ] If failed: update `ralph/failures.log` and `ralph/lessons.md`
- [ ] `git add -A && git commit -m "ralph: step N - [description]"`

## Replanning

Trigger a replan when:
- 3 consecutive steps fail
- You discover the current approach is fundamentally wrong
- A dependency assumption proved false

Replan process:
1. Write in progress.md: `## Replan (iteration N) — Reason: [why]`
2. Review all completed steps — what's salvageable?
3. Write new plan from current state
4. Commit the replan: `git commit -m "ralph: replan - [reason]"`
5. Continue from new step 1

## Completion

When ALL plan steps are done:
1. Run full test suite
2. Update progress.md: `## Status: COMPLETE`
3. Write a summary: what was built, key decisions, known limitations
4. Final commit: `git commit -m "ralph: complete - [project summary]"`

## Anti-Patterns (DO NOT)

- ❌ Do multiple steps in one iteration
- ❌ Skip reading state files ("I remember what I did")
- ❌ Edit the plan without committing the change separately
- ❌ "Start fresh" or "let me redo everything"
- ❌ Touch files unrelated to the current step
- ❌ Ignore test failures and move on
- ❌ Delete or overwrite lessons.md
