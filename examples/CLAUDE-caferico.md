# Caférico — Agent Instructions (Ralph v2)

## Core Loop

You are a worker agent in an iterative build system. Every task follows this cycle:

1. **Read state** — Read `ralph/progress.md` and `ralph/lessons.md` before doing anything
2. **Do ONE thing** — Complete exactly one step from the plan. Not two. Not "one and a half."
3. **Verify** — Run `npm run typecheck` and `npm run build`. Confirm nothing is broken.
4. **Save state** — Update `ralph/progress.md` with what you did and the result
5. **Commit** — `git commit -m "ralph: step N - [description]"`

## State Files

### ralph/progress.md
Source of truth for plan and current state. Format:
```markdown
# Progress
## Plan
1. [x] Step description — DONE (iteration N)
2. [ ] Step description — IN PROGRESS
3. [ ] Step description — NOT STARTED

## Current
- Working on: Step 2
- Iteration: 7
- Last action: [what you did]
- Last result: [outcome]

## Architecture Decisions
- [Decision]: [Choice] (reason, decided step N)
```

### ralph/lessons.md
Read FIRST every iteration. After every failure or surprising discovery, add a lesson.
Format: `- DO/DO NOT [action] — [reason] (discovered iteration N)`

### ralph/failures.log
Format: `iteration:N|action:description|error:message|hash:short`
If same hash appears 3 times → STOP. Write `STUCK: [description]` in progress.md.

## Project Context

**Caférico** (caferico.be) — Belgische specialty coffee webshop.

### Essentiële Bestanden
- **CONTEXT.md** — Bedrijfsinfo, design richting, technische stack, content, afbeeldingen. LEES DIT EERST.
- **ralph/spec.md** — Wat we nu bouwen + acceptance criteria
- **ralph/progress.md** — Plan + state (source of truth)

### Technische Stack (NIET afwijken)
- **Framework:** Next.js 15 (App Router, TypeScript)
- **Styling:** Tailwind CSS only (geen CSS modules, geen inline styles)
- **i18n:** next-intl (NL default, EN, FR, ES) — ALLE teksten via next-intl
- **Backend:** WooCommerce REST API (headless, draait op one.com)
- **Checkout:** Mollie (hosted checkout, redirect) — NIET Stripe
- **Auth:** NextAuth.js
- **Deployment:** Vercel
- **Fonts:** Playfair Display (headings) + Inter (body)

### Design Richting
- Elegant, warm, premium, awe-inspiring
- Deep browns, cream, gold accents, dark backgrounds
- Mobile-first responsive (375px → 768px → 1024px → 1440px)
- Generous whitespace, 8px grid spacing system
- Zie CONTEXT.md sectie 2 voor volledige design brief

### Huidige Staat
- Redesign fase compleet (42/42 stories)
- Mollie checkout integratie compleet
- WooCommerce REST API integratie werkt
- Cart is client-side (localStorage) via CartProvider/CartDrawer
- Checkout flow: cart → adresformulier → Mollie redirect → return pagina
- Auth fase: NextAuth.js met magic links + Google OAuth (in progress)
- ~100 bestaande WooCommerce klantaccounts

### Bestaande Structuur
```
app/[locale]/(pages)/    — pagina's
components/              — gedeelde componenten
data/                    — mock data (JSON)
messages/                — i18n vertalingen (nl, en, fr, es)
lib/                     — utilities
types/                   — TypeScript types
tailwind.config.ts       — design tokens
```

## Per-Iteration Rules

### Before you start:
- [ ] Read `ralph/progress.md`
- [ ] Read `ralph/lessons.md`
- [ ] Check `ralph/failures.log`
- [ ] Identify the ONE next step

### While working:
- Touch as few files as possible
- If the plan needs changing → update plan FIRST, commit, THEN proceed
- If unsure about architecture → mark step BLOCKED with reason
- No "cleanup" or "refactor" unless that IS the current step
- No scope creep — new issues become new plan steps

### After completing:
- [ ] `npm run typecheck` passes
- [ ] `npm run build` passes
- [ ] Bestaande functionaliteit niet gebroken (cart, taalswitch, navigatie)
- [ ] Update `ralph/progress.md`
- [ ] If failed: update `ralph/failures.log` and `ralph/lessons.md`
- [ ] `git add -A && git commit -m "ralph: step N - [description]"`

## Replanning

Trigger replan when:
- 3 consecutive steps fail
- Approach is fundamentally wrong
- A dependency assumption proved false

Process:
1. Write `## Replan (iteration N) — Reason: [why]` in progress.md
2. Review completed steps — what's salvageable?
3. Write new plan
4. Commit: `git commit -m "ralph: replan - [reason]"`

## Project Rules
- **Alle teksten via next-intl.** Vertalingen in messages/nl.json, en.json, fr.json, es.json.
- **Tailwind only.** Geen styled-components, CSS modules, inline styles.
- **Geen nieuwe dependencies** tenzij de stap het expliciet vereist.
- **Mobile-first.** Elk component eerst voor 375px, dan opschalen.
- **Breek niets.** Cart, routing, i18n, bestaande pagina's moeten werken.

## Anti-Patterns (DO NOT)
- ❌ Meerdere stappen in één iteratie
- ❌ State files overslaan ("ik weet nog wat ik deed")
- ❌ Plan wijzigen zonder apart te committen
- ❌ "Start fresh" of "laat me alles opnieuw doen"
- ❌ Bestanden aanraken die niet bij de huidige stap horen
- ❌ Test failures negeren en doorgaan
- ❌ lessons.md verwijderen of overschrijven
