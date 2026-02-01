# Ralph Loop v2 — De Complete Gids

## Inhoudsopgave

1. [Waarom Ralph v2 bestaat](#1-waarom-ralph-v2-bestaat)
2. [Wat er mis was met v1](#2-wat-er-mis-was-met-v1)
3. [De bronnen: wat we hebben gecombineerd](#3-de-bronnen-wat-we-hebben-gecombineerd)
4. [Ralph v2: de architectuur](#4-ralph-v2-de-architectuur)
5. [De concepten in detail](#5-de-concepten-in-detail)
6. [Het twee-lagen systeem: Emdash + ralph.sh](#6-het-twee-lagen-systeem-emdash--ralphsh)
7. [Praktische workflow: stap voor stap](#7-praktische-workflow-stap-voor-stap)
8. [Waarom v2 beter is](#8-waarom-v2-beter-is)
9. [Tips en valkuilen](#9-tips-en-valkuilen)

---

## 1. Waarom Ralph v2 bestaat

### Het probleem

AI coding agents zijn slim genoeg om complexe software te bouwen. Maar ze falen constant bij projecten die meer dan 15-20 iteraties vergen. Niet door gebrek aan intelligentie, maar door een fundamenteel architectuurprobleem: **context window pollution**.

Wat er gebeurt:
- Iteratie 1-10: agent werkt prima, schrijft goede code
- Iteratie 15: context window raakt vol, agent begint te vergeten wat het eerder gebouwd heeft
- Iteratie 25: agent edit bestanden die niet bestaan, of overschrijft eerder werk
- Iteratie 30: "Laat me opnieuw beginnen" — alles weg

Dit is geen bug. Het is hoe LLM's werken. Ze hebben een beperkt geheugen (context window), en alles wat ze "weten" over het project zit in dat venster. Na genoeg iteraties is het venster zo vervuild met oude conversatie, foute pogingen, en verouderde code dat het model niet meer kan onderscheiden wat waar is.

### De oplossing

Verplaats het geheugen van de context window naar **bestanden op disk**. Elke iteratie start een **nieuwe, schone sessie**: de agent leest de huidige staat uit bestanden, doet één ding, schrijft de nieuwe staat terug, en de sessie eindigt. Volgende iteratie = nieuwe sessie = schone context. Geen accumulatie, geen vervuiling, geen vergeten.

Dat is de kern van Ralph Loops. Vernoemd naar Geoffrey Huntley's techniek (ghuntley.com/ralph), geïmplementeerd als plugin in Claude Code, en door ons uitgebreid tot v2.

---

## 2. Wat er mis was met v1

De originele Ralph Loop (zoals in de tweet van @spacepixel en zoals we het gebruikten bij Caferico) had deze setup:

- `ralph.sh` — bash script dat Claude Code in een loop aanroept, **elke iteratie een nieuwe sessie**
- `progress.txt` — één groot tekstbestand met alle voortgang
- `CLAUDE.md` — instructies voor de agent

**Dit werkte.** De 42-story Caferico redesign is ermee gebouwd. Maar het had serieuze gaten:

### Gat 1: Geen loop detection
Als de agent vastliep op een probleem, probeerde hij dezelfde fix eindeloos opnieuw. Geen mechanisme om te detecteren "ik heb dit al 3x geprobeerd en het werkt niet". Resultaat: verbrande tokens en tijd.

### Gat 2: Geen rollback
Geen git commit per iteratie. Als iteratie 30 iets brak dat iteratie 15 had gebouwd, was er geen makkelijke weg terug.

### Gat 3: Statisch plan
Het plan (de PRD) werd aan het begin geschreven en nooit bijgesteld. Als halverwege bleek dat de gekozen aanpak niet werkte, ging de agent braaf door met een kapot plan.

### Gat 4: Alles sequentieel
Eén agent, één taak tegelijk. Geen mogelijkheid om onafhankelijke taken parallel te draaien.

### Gat 5: Geen learning across iterations
Clean context per iteratie is een feature (geen vervuiling) én een bug (geen leren). Als de agent bij iteratie 12 ontdekte dat library X niet werkt, wist hij dat bij iteratie 25 niet meer.

### Gat 6: Geen gestructureerde state
`progress.txt` was één lang bestand dat steeds groeide. Na 42 stories was het 800+ regels.

### Gat 7: Geen stall detection
Als de agent 5 iteraties lang geen voortgang boekte, merkte niemand het tenzij je actief keek.

---

## 3. De bronnen: wat we hebben gecombineerd

Ralph v2 is een synthese van drie bronnen:

### Bron 1: De originele Ralph Loop (@spacepixel)
**Wat we behielden:**
- Het kernprincipe: file-based state in plaats van context memory
- **Het bash script dat elke iteratie een nieuwe sessie start** — dit is cruciaal en was het hele punt van Ralph
- Iteratief werken: één taak per cyclus

**Wat we verwierpen:**
- Het "build while you sleep" narrative — onrealistisch voor complexe projecten
- Het gebrek aan feedback loops en quality gates

### Bron 2: Boris Cherny's tips (maker van Claude Code)
Boris' thread met 10 tips van het Claude Code team leverde deze concepten:

**Tip 1 — Parallel worktrees:** Draai 3-5 agents tegelijk, elk in een eigen git worktree. → **Geïmplementeerd via Emdash als orchestratielaag.** Emdash beheert de worktrees, het bash script runt de loop per worktree.

**Tip 2 — Plan mode eerst:** Begin elke complexe taak in plan mode. Als iets misgaat, terug naar plan mode. → **Geïmplementeerd als verplichte planning fase.** Aparte agent voor planning, pas daarna executie.

**Tip 3 — CLAUDE.md als levend document:** Na elke correctie: "Update je regels zodat je deze fout niet meer maakt." → **Geïmplementeerd als `ralph/lessons.md`.** Gescheiden van CLAUDE.md: lessons zijn per-run, CLAUDE.md is permanent.

**Tip 6 — Challenge Claude:** "Bewijs dat dit werkt." → **Geïmplementeerd als verplichte verificatiestap per iteratie.** Typecheck + build, elke keer.

**Tip 8 — Subagents:** Offload taken voor schone context. → **De hele architectuur is subagent-based.** Elke iteratie is een verse subagent-sessie.

### Bron 3: Onze eigen gap-analyse

**Loop detection:** `failures.log` met hashes. Drie identieke hashes = automatische stop.

**Git commit per iteratie:** Elke stap is een commit. Rollback naar elk punt mogelijk.

**Adaptive replanning:** Na 3 failures → verplichte herplanningsfase.

**Stall detection:** 5 iteraties zonder voortgang → waarschuwing.

**Gestructureerde state:** Vier gespecialiseerde bestanden in plaats van één progress.txt.

---

## 4. Ralph v2: de architectuur

### De bestanden

```
ralph/
├── spec.md          — WAT we bouwen (jij schrijft dit)
├── progress.md      — Plan + huidige staat (agents onderhouden dit)
├── lessons.md       — Geleerde lessen (agents schrijven, agents lezen)
└── failures.log     — Gefaalde pogingen voor loop detection

scripts/
└── ralph.sh         — De loop runner (start elke iteratie een nieuwe agent sessie)

CLAUDE.md            — Agent regels (Ralph v2 discipline + project context)
```

**`ralph/spec.md`** — Het startpunt. Jij definieert wat gebouwd moet worden, acceptance criteria, constraints, en wat buiten scope is. Het enige bestand dat jij handmatig schrijft.

**`ralph/progress.md`** — Source of truth. Bevat het genummerde plan (met status per stap), huidige iteratie, en architectuurbeslissingen. Gestructureerd: checkboxes, expliciete status, aparte secties.

**`ralph/lessons.md`** — Collectief geheugen van de run. Elke fout of ontdekking wordt vastgelegd. Elke toekomstige iteratie leest dit *als eerste*. Format: `- DO/DO NOT [actie] — [reden] (ontdekt iteratie N)`.

**`ralph/failures.log`** — Loop detection. Format: `iteration:N|action:beschrijving|error:foutmelding|hash:kort`. 3x dezelfde hash = automatische stop.

**`scripts/ralph.sh`** — De loop runner. Dit is het hart van het systeem. Het start elke iteratie een **nieuwe, schone agent sessie**. De agent leest de state files, doet één stap, schrijft state terug, en de sessie eindigt. Het script checkt dan op signalen (COMPLETE, STUCK, BLOCKED), stall detection, en start de volgende iteratie.

**`CLAUDE.md`** — De regels die elke agent sessie volgt. Twee delen: Ralph v2 discipline (generieke workflow) + project-specifieke context (stack, design, code structuur).

### Waarom het bash script cruciaal is

Dit is het fundamentele verschil dat Ralph Loops werkt:

**Zonder bash script (gewoon een agent op een taak zetten):**
```
Sessie start → stap 1 → stap 2 → stap 3 → ... → stap 15 → context vol → hallucineert → "start fresh"
[────────────── één doorlopende sessie, groeiende context ──────────────]
```

**Met bash script (elke iteratie een nieuwe sessie):**
```
Sessie 1: leest state → stap 1 → schrijft state → sessie eindigt
Sessie 2: leest state → stap 2 → schrijft state → sessie eindigt
Sessie 3: leest state → stap 3 → schrijft state → sessie eindigt
...
Sessie N: leest state → stap N → schrijft state → COMPLETE
[elke sessie is schoon — geen accumulatie]
```

Het script is de metronoom die het ritme afdwingt. Zonder script is er geen clean context guarantee.

### De iteratiecyclus (per sessie)

```
┌──────────────────────────────────────────────┐
│  NIEUWE SCHONE SESSIE                        │
│                                              │
│  1. READ STATE                               │
│     ├── ralph/lessons.md (wat te vermijden)  │
│     ├── ralph/failures.log (loop check)      │
│     └── ralph/progress.md (waar ben ik?)     │
│                                              │
│  2. DO ONE THING                             │
│     └── Exact één stap uit het plan          │
│                                              │
│  3. VERIFY                                   │
│     ├── typecheck / build / tests            │
│     └── Bestaande functionaliteit intact?    │
│                                              │
│  4. SAVE STATE                               │
│     ├── Update ralph/progress.md             │
│     ├── Bij fout: update failures.log        │
│     └── Bij les: update lessons.md           │
│                                              │
│  5. COMMIT                                   │
│     └── git commit -m "ralph: step N - ..."  │
│                                              │
│  SESSIE EINDIGT                              │
└──────────────────────────────────────────────┘
        ↓
   ralph.sh start volgende sessie
```

---

## 5. De concepten in detail

### Concept 1: Clean Context Per Iteratie

Het belangrijkste concept. Elke iteratie is een verse agent sessie. De agent weet NIETS behalve wat er in de bestanden staat. Dit is waarom file-based state werkt: de bestanden ZIJN het geheugen, niet de context window.

**Waarom dit werkt:**
- Iteratie 50 heeft evenveel "geheugen" als iteratie 1 — ze lezen dezelfde files
- Geen accumulatie van foute informatie
- Elk model kan elke iteratie draaien (je kunt zelfs mid-run van model wisselen)

### Concept 2: One Task Per Iteration

De agent doet exact één stap per iteratie. Niet twee. De sessie is kort genoeg dat de agent niet kan afdwalen.

**Waarom agents dit moeilijk vinden:**
LLM's willen behulpzaam zijn. "Terwijl ik hier toch ben..." is hun natuur. Maar omdat elke sessie eindigt na één stap, is afdwalen fysiek onmogelijk — het script start gewoon een nieuwe sessie.

### Concept 3: Loop Detection

```
failures.log:
iteration:12|action:fix-auth|error:Cannot find module './utils'|hash:a3f2c1
iteration:14|action:fix-auth|error:Cannot find module './utils'|hash:a3f2c1
iteration:16|action:fix-auth|error:Cannot find module './utils'|hash:a3f2c1
→ ralph.sh detecteert 3x dezelfde hash → STOP
```

Twee lagen:
1. **Agent-side:** de agent checkt failures.log en stopt zelf als hij 3x dezelfde hash ziet
2. **Script-side:** ralph.sh checkt ook en stopt de loop als de agent het mist

### Concept 4: Stall Detection

ralph.sh telt het aantal DONE stappen na elke iteratie. Als er 5 iteraties voorbijgaan zonder dat er een stap bijkomt, geeft het script een waarschuwing. De agent werkt misschien, maar boekt geen meetbare voortgang.

### Concept 5: Adaptive Replanning

Triggers:
- 3 opeenvolgende failures
- Fundamenteel verkeerde aanname ontdekt
- Dependency failure

De agent schrijft een replan in progress.md, commit het apart, en gaat door met het nieuwe plan. Het script merkt dit niet eens — het ziet gewoon dat de DONE count weer begint op te lopen.

### Concept 6: Lessons Compound

```markdown
# Lessons
- DO NOT use next-auth/prisma-adapter — incompatible with WooCommerce (iteration 8)
- DO run build after typecheck — some errors only surface during build (iteration 3)
```

Elke sessie leest dit. Fouten worden één keer gemaakt. In v1 werden dezelfde fouten herhaald omdat er geen persistent geheugen was buiten de context.

### Concept 7: Git Commit Per Iteratie

Format: `ralph: step N - [beschrijving]`

Geeft je: volledige history, rollback naar elk punt, blame tracking, diff review per stap.

---

## 6. Het twee-lagen systeem: Emdash + ralph.sh

### De kernvraag: wie doet wat?

Er zijn twee problemen die opgelost moeten worden:
1. **Hoe voorkom je context pollution?** → ralph.sh (nieuwe sessie per iteratie)
2. **Hoe run je meerdere taken parallel?** → Emdash (worktrees + visueel dashboard)

Geen van beide tools lost beide problemen op. Samen wel.

### De architectuur

```
┌─────────────────────────────────────────────────────┐
│  JIJ (de orchestrator)                              │
│  ├── Schrijft ralph/spec.md                         │
│  ├── Reviewt plannen                                │
│  ├── Monitort via Emdash dashboard                  │
│  ├── Grijpt in wanneer nodig                        │
│  └── Merged en deployed                             │
└──────────────────┬──────────────────────────────────┘
                   │
┌──────────────────▼──────────────────────────────────┐
│  EMDASH (parallelle orchestratie)                   │
│  ├── Beheert git worktrees                          │
│  ├── Toont live status per worktree                 │
│  ├── Toont diffs per worktree                       │
│  └── PR's openen en mergen                          │
│                                                     │
│  Worktree A        Worktree B        Worktree C     │
│  ┌──────────┐     ┌──────────┐     ┌──────────┐    │
│  │ralph.sh  │     │ralph.sh  │     │ralph.sh  │    │
│  │running   │     │running   │     │running   │    │
│  │steps 1-4 │     │steps 5-7 │     │steps 8-10│    │
│  └──────────┘     └──────────┘     └──────────┘    │
└─────────────────────────────────────────────────────┘
                   │
┌──────────────────▼──────────────────────────────────┐
│  ralph.sh (per-worktree loop)                       │
│  ├── Start elke iteratie een NIEUWE agent sessie    │
│  ├── Clean context elke keer                        │
│  ├── Loop detection (failures.log)                  │
│  ├── Stall detection (5 iteraties geen voortgang)   │
│  └── Signaal detectie (COMPLETE/STUCK/BLOCKED)      │
└─────────────────────────────────────────────────────┘
```

### Emdash's rol

Emdash is de **visuele laag**:
- Je ziet welke worktrees actief zijn
- Je ziet de terminal output van elk ralph.sh script
- Je ziet diffs die agents produceren
- Je kunt agents stoppen via de UI
- Je kunt PRs openen wanneer een worktree klaar is

### ralph.sh's rol

ralph.sh is de **discipline laag**:
- Dwingt clean context af (nieuwe sessie per iteratie)
- Dwingt one-task-per-iteration af (sessie eindigt na één stap)
- Detecteert loops (failures.log hash check)
- Detecteert stalls (5 iteraties zonder voortgang)
- Stopt automatisch bij COMPLETE, STUCK, of BLOCKED

### Zonder Emdash

Ralph v2 werkt ook zonder Emdash. Je opent gewoon een terminal, navigeert naar je project, en runt `bash scripts/ralph.sh`. Alles sequentieel, maar het werkt.

Emdash voegt toe: parallel worktrees, visueel dashboard, diff review. Niet noodzakelijk, wel een significante verbetering.

### Zonder ralph.sh

Emdash zonder ralph.sh is een agent die je op een taak zet in één doorlopende sessie. Geen clean context per stap. Na 15+ stappen dezelfde context pollution als zonder Ralph. **Dit is waarom je beide nodig hebt.**

---

## 7. Praktische workflow: stap voor stap

### Fase 0: Setup (eenmalig)

1. Installeer Emdash op je laptop
2. Clone de ralph-v2 template: `git clone https://github.com/gutsassistent/ralph-v2 ~/devvv/ralph-v2`
3. Zorg dat Claude Code (of Codex) geïnstalleerd en ingelogd is

### Fase 1: Project voorbereiden

```bash
cd ~/projects/mijn-project

# Initialiseer Ralph v2
bash ~/devvv/ralph-v2/scripts/init.sh "Beschrijving van wat ik bouw"

# Kopieer het loop script
cp ~/devvv/ralph-v2/scripts/ralph.sh ./scripts/ralph.sh
chmod +x ./scripts/ralph.sh
```

**Vul `ralph/spec.md` in.** Definieer:
- Wat je bouwt (concreet, niet vaag)
- Wanneer het af is (meetbare criteria)
- Wat NIET in scope is
- Technische constraints

Hoe scherper de spec, hoe beter de agents werken.

### Fase 2: Planning

Open je project in Emdash. Spawn een agent (gewone Emdash sessie, niet via ralph.sh) met:

> "Read ralph/spec.md. Explore the existing codebase thoroughly. Create a detailed numbered implementation plan in ralph/progress.md. Each step must be independently completable, testable, and small enough for one iteration (max ~50 lines changed). Mark dependencies between steps. Do NOT start coding."

**Review het plan.** Check:
- Zijn de stappen klein genoeg?
- Zijn dependencies correct?
- Welke stappen kunnen parallel?
- Mist er iets?

Optioneel: spawn een tweede agent die het plan reviewt als senior engineer.

Pas het plan aan. Commit het goedgekeurde plan.

### Fase 3: Executie

**Sequentieel (één worktree):**

In Emdash, open een terminal in je worktree en run:

```bash
bash scripts/ralph.sh --tool claude --max 30
```

Het script runt. Elke iteratie zie je output in de terminal. Het script stopt automatisch bij COMPLETE, STUCK, of BLOCKED.

**Parallel (meerdere worktrees):**

1. Maak in Emdash meerdere worktrees aan
2. Kopieer de ralph/ directory en scripts naar elke worktree
3. Pas ralph/progress.md per worktree aan zodat elke worktree een subset van stappen bevat
4. Run `bash scripts/ralph.sh` in elke worktree

```
Worktree A: steps 1-4 (backend API)
Worktree B: steps 5-7 (frontend components)  ← parallel, geen overlap
Worktree C: steps 8-10 (tests + docs)        ← parallel, geen overlap
```

### Fase 4: Monitoren

**Via Emdash:**
- Terminal output per worktree (ralph.sh output is live zichtbaar)
- Diffs per worktree (wat heeft de agent veranderd)
- Stop een worktree als iets fout gaat

**Signalen in de terminal:**
- `✅ All steps complete!` → worktree is klaar
- `🛑 STUCK detected` → loop gedetecteerd, jij moet kijken
- `⚠️ All remaining steps are BLOCKED` → agent wacht op input
- `⚠️ No progress in 5 iterations` → mogelijke stall

**In de bestanden:**
- `ralph/progress.md` → welke stappen af zijn, welke open
- `ralph/failures.log` → wat er fout ging
- `ralph/lessons.md` → wat de agent geleerd heeft

### Fase 5: Mergen en afronden

1. Review diffs per worktree in Emdash
2. Merge branches via Emdash PRs
3. Run volledige test suite op gemergte code
4. Deploy

---

## 8. Waarom v2 beter is

### vs. Ralph v1 (wat we hadden)

| Aspect | v1 | v2 |
|---|---|---|
| Loop runner | Bash script (basic) | Bash script (loop detection, stall detection, signalen) |
| State | Eén progress.txt (800+ regels) | 4 gespecialiseerde bestanden |
| Loop detection | Geen | failures.log met hash-based stop |
| Stall detection | Geen | 5 iteraties zonder voortgang = waarschuwing |
| Rollback | Geen | Git commit per iteratie |
| Planning | Statisch PRD | Adaptive replanning bij failures |
| Learning | Geen | lessons.md accumuleert kennis |
| Parallelisme | Niet mogelijk | Via Emdash worktrees |
| Visuele controle | Terminal alleen | Emdash dashboard + terminal |
| Verificatie | Soms vergeten | Verplicht per iteratie |
| Multi-tool | Alleen Claude Code | Claude Code, Codex, Amp (via --tool flag) |

### vs. Ralph Loop uit de tweet (@spacepixel)

| Aspect | Tweet versie | v2 |
|---|---|---|
| Aanpak | "Build while you sleep" | "Build while you watch" |
| Controle | Fire-and-forget | Jij bent de orchestrator |
| Foutafhandeling | Loop tot max iteraties | Stop bij STUCK/BLOCKED/stall |
| Plan | Eenmalig | Adaptief |
| Learning | Geen | lessons.md |
| Kosten | Ongecontroleerd | Stall/loop detection spaart tokens |

### vs. Emdash alleen (zonder ralph.sh)

| Aspect | Emdash solo | Emdash + ralph.sh |
|---|---|---|
| Context per agent | Één doorlopende sessie | Verse sessie per iteratie |
| Na 15+ stappen | Context pollution | Schone context |
| Discipline | Agent bepaalt | Script dwingt af |
| Loop detection | Geen | failures.log |
| Automatische stop | Geen | COMPLETE/STUCK/BLOCKED |

---

## 9. Tips en valkuilen

### De spec is alles
80% van het succes zit in `ralph/spec.md`. Een vage spec levert vage output. Een scherpe spec met meetbare criteria levert scherpe resultaten.

### Begin sequentieel
Eerste project: één worktree, `bash scripts/ralph.sh`. Leer hoe de cyclus voelt. Pas daarna parallel.

### Review het plan grondig
Een fout in het plan vermenigvuldigt door elke iteratie. Besteed meer tijd aan plannen dan je denkt.

### Kleine stappen > grote stappen
Max ~50 regels per stap. Hoe kleiner, hoe beter loop detection werkt, hoe makkelijker rollback is.

### Herplanning is geen falen
Als het plan niet werkt, is herplannen de juiste actie. Doorbouwen op een kapot fundament is altijd erger.

### Parallelle agents: alleen bij echte onafhankelijkheid
Twee agents die `package.json` moeten wijzigen zijn niet onafhankelijk. Wees conservatief.

### Model routing spaart geld
```bash
# Routine implementatie
bash scripts/ralph.sh --tool claude --model claude-sonnet-4-5

# Complexe architectuur
bash scripts/ralph.sh --tool claude --model claude-opus-4-5
```

### Kijk naar de signalen, niet naar de output
Je hoeft niet elke regel agent output te lezen. Kijk naar:
- Progress count in ralph.sh output
- STUCK/BLOCKED/stall signalen
- Diffs in Emdash

---

## Bijlage: Quick Reference

### ralph.sh opties:
```bash
bash scripts/ralph.sh                          # defaults (claude, 50 iteraties)
bash scripts/ralph.sh --tool codex             # gebruik Codex
bash scripts/ralph.sh --model claude-sonnet-4-5  # specifiek model
bash scripts/ralph.sh --max 20                 # max 20 iteraties
bash scripts/ralph.sh --dry-run                # toon prompt, voer niet uit
```

### Exit codes:
- `0` — COMPLETE (alle stappen af)
- `1` — Max iteraties bereikt
- `2` — STUCK (loop gedetecteerd)
- `3` — BLOCKED (alle resterende stappen geblokkeerd)

### Bestanden die JIJ beheert:
- `ralph/spec.md` — wat we bouwen

### Bestanden die AGENTS beheren:
- `ralph/progress.md` — plan + state
- `ralph/lessons.md` — geleerde lessen
- `ralph/failures.log` — faaldetectie

### Signalen:
- ✅ `COMPLETE` — alle stappen af, loop stopt
- 🛑 `STUCK` — 3x dezelfde fout, loop stopt
- ⚠️ `BLOCKED` — alle stappen geblokkeerd, loop stopt
- ⚠️ Stall — 5 iteraties zonder voortgang, waarschuwing
