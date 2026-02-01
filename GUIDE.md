# Ralph Loop v2 — De Complete Gids

## Inhoudsopgave

1. [Waarom Ralph v2 bestaat](#1-waarom-ralph-v2-bestaat)
2. [Wat er mis was met v1](#2-wat-er-mis-was-met-v1)
3. [De bronnen: wat we hebben gecombineerd](#3-de-bronnen-wat-we-hebben-gecombineerd)
4. [Ralph v2: de architectuur](#4-ralph-v2-de-architectuur)
5. [De concepten in detail](#5-de-concepten-in-detail)
6. [Emdash: de orchestratielaag](#6-emdash-de-orchestratielaag)
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

Verplaats het geheugen van de context window naar **bestanden op disk**. Elke iteratie start schoon: de agent leest de huidige staat uit bestanden, doet één ding, schrijft de nieuwe staat terug, en stopt. Geen accumulatie, geen vervuiling, geen vergeten.

Dat is de kern van Ralph Loops. Vernoemd naar Geoffrey Huntley's techniek (ghuntley.com/ralph), geïmplementeerd als plugin in Claude Code, en door ons uitgebreid tot v2.

---

## 2. Wat er mis was met v1

De originele Ralph Loop (zoals in de tweet van @spacepixel en zoals we het gebruikten bij Caferico) had deze setup:

- `ralph.sh` — bash script dat Claude Code in een loop aanroept
- `progress.txt` — één groot tekstbestand met alle voortgang
- `CLAUDE.md` — instructies voor de agent
- De agent pakte steeds de volgende "story" uit een PRD en implementeerde die

**Dit werkte.** De 42-story Caferico redesign is ermee gebouwd. Maar het had serieuze gaten:

### Gat 1: Geen loop detection
Als de agent vastliep op een probleem, probeerde hij dezelfde fix eindeloos opnieuw. Geen mechanisme om te detecteren "ik heb dit al 3x geprobeerd en het werkt niet". Resultaat: verbrande tokens en tijd.

### Gat 2: Geen rollback
Geen git commit per iteratie. Als iteratie 30 iets brak dat iteratie 15 had gebouwd, was er geen makkelijke weg terug. Je moest handmatig door de code graven om te vinden wat er mis ging.

### Gat 3: Statisch plan
Het plan (de PRD) werd aan het begin geschreven en nooit bijgesteld. Als halverwege bleek dat de gekozen aanpak niet werkte, ging de agent braaf door met een kapot plan. Geen adaptive replanning.

### Gat 4: Alles sequentieel
Eén agent, één taak tegelijk. Geen mogelijkheid om onafhankelijke taken parallel te draaien. Een 42-story project duurde daardoor veel langer dan nodig.

### Gat 5: Geen learning across iterations
Clean context per iteratie is een feature (geen vervuiling) én een bug (geen leren). Als de agent bij iteratie 12 ontdekte dat library X niet werkt, wist hij dat bij iteratie 25 niet meer. Dezelfde fout kon meerdere keren gemaakt worden.

### Gat 6: Geen gestructureerde state
`progress.txt` was één lang bestand dat steeds groeide. Na 42 stories was het 800+ regels. De agent moest elke iteratie door dat hele bestand scrollen om te weten waar hij was. Inefficiënt en error-prone.

---

## 3. De bronnen: wat we hebben gecombineerd

Ralph v2 is een synthese van drie bronnen:

### Bron 1: De originele Ralph Loop (@spacepixel)
**Wat we behielden:**
- Het kernprincipe: file-based state in plaats van context memory
- Iteratief werken: één taak per cyclus
- Clean context per iteratie: elke run start schoon

**Wat we verwierpen:**
- Het "build while you sleep" narrative — onrealistisch voor complexe projecten
- Het gebrek aan feedback loops en quality gates

### Bron 2: Boris Cherny's tips (maker van Claude Code)
Boris' thread met 10 tips van het Claude Code team leverde deze concepten:

**Tip 1 — Parallel worktrees:** Draai 3-5 agents tegelijk, elk in een eigen git worktree. De grootste productiviteitswinst volgens het hele Claude Code team. → **Geïmplementeerd via Emdash.**

**Tip 2 — Plan mode eerst:** Begin elke complexe taak in plan mode. Giet je energie in het plan zodat de agent de implementatie in één keer kan doen. Als iets misgaat, terug naar plan mode. → **Geïmplementeerd als verplichte planning fase in Ralph v2.** De agent mag niet beginnen met coderen voordat het plan geschreven en gecommit is.

**Tip 3 — CLAUDE.md als levend document:** Na elke correctie: "Update je CLAUDE.md zodat je deze fout niet meer maakt." Claude is verrassend goed in regels voor zichzelf schrijven. → **Geïmplementeerd als `ralph/lessons.md`.** Elke fout wordt vastgelegd, elke toekomstige iteratie leest het. Maar we scheiden het van CLAUDE.md — lessons zijn per-run, CLAUDE.md is permanent.

**Tip 6 — Challenge Claude:** Zeg "bewijs me dat dit werkt" en laat Claude gedrag vergelijken tussen main en feature branch. → **Geïmplementeerd als verificatiestap.** Elke iteratie moet typecheck + build draaien. Niet alleen "het compileert" maar "het breekt niets".

**Tip 8 — Subagents:** Offload taken naar subagents om de context van de hoofdagent schoon te houden. → **Geïmplementeerd via Emdash.** Elke agent in Emdash is effectief een subagent met eigen worktree en eigen context.

### Bron 3: Onze eigen gap-analyse
De verbeteringen die geen van beide bronnen hadden:

**Loop detection:** Een `failures.log` die gefaalde pogingen hasht. Drie identieke hashes = automatische stop. Voorkomt eindeloos branden van tokens op hetzelfde probleem.

**Git commit per iteratie:** Elke stap is een commit. Rollback naar elk punt mogelijk. De commit message vertelt precies wat er in die iteratie gebeurde.

**Adaptive replanning:** Na 3 opeenvolgende failures of wanneer de aanpak fundamenteel fout blijkt → verplichte herplanningsfase. Het plan is een levend document, geen onveranderlijk contract.

**Gestructureerde state:** In plaats van één groot progress.txt zijn er nu vier gespecialiseerde bestanden die elk een eigen functie hebben (zie sectie 4).

---

## 4. Ralph v2: de architectuur

### De bestanden

```
ralph/
├── spec.md          — WAT we bouwen (jij schrijft dit)
├── progress.md      — Plan + huidige staat (agents onderhouden dit)
├── lessons.md       — Geleerde lessen (agents schrijven, agents lezen)
└── failures.log     — Gefaalde pogingen voor loop detection

CLAUDE.md            — Agent regels (Ralph v2 discipline + project context)
```

**`ralph/spec.md`** — Het startpunt. Jij definieert hier wat gebouwd moet worden, de acceptance criteria, technische constraints, en wat expliciet buiten scope is. Dit is het enige bestand dat jij handmatig schrijft. De rest onderhouden de agents.

**`ralph/progress.md`** — De source of truth voor het plan en de huidige staat. Bevat:
- Het genummerde implementatieplan (met status per stap)
- De huidige iteratie en wat er net gedaan is
- Architectuurbeslissingen die genomen zijn

Dit vervangt het oude `progress.txt` maar is gestructureerd: stappen zijn checkboxes, status is expliciet (DONE/IN PROGRESS/BLOCKED/NOT STARTED), en architectuurbeslissingen hebben een eigen sectie.

**`ralph/lessons.md`** — Het collectieve geheugen van de run. Elke keer dat een agent een fout maakt of iets onverwachts ontdekt, schrijft hij het hier. Elke toekomstige iteratie leest dit bestand *als eerste*. Format: "DO/DO NOT [actie] — [reden] (ontdekt iteratie N)".

Dit lost het "geen learning across iterations" probleem op. De agent vergeet niet meer dat library X niet werkt, want het staat zwart op wit in lessons.md.

**`ralph/failures.log`** — Technisch logbestand voor loop detection. Format: `iteration:N|action:beschrijving|error:foutmelding|hash:kort`. Als dezelfde hash 3x verschijnt, stopt de agent automatisch en markeert de stap als STUCK. Geen eindeloze loops meer.

**`CLAUDE.md`** — De regels die elke agent volgt. Bevat twee delen:
1. Ralph v2 discipline (de generieke workflow regels)
2. Project-specifieke context (tech stack, design richting, bestaande code)

### De iteratiecyclus

```
┌──────────────────────────────────────────────┐
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
│     ├── npm run typecheck                    │
│     ├── npm run build                        │
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
└──────────────────────────────────────────────┘
```

Elke iteratie doorloopt deze vijf stappen. Altijd. Geen uitzonderingen. De discipline zit in de herhaling.

---

## 5. De concepten in detail

### Concept 1: One Task Per Iteration

De belangrijkste regel. De agent doet exact één stap per iteratie. Niet "stap 3 en dan ook even snel stap 4 omdat die klein is". Niet "stap 3 en een kleine refactor die ik zag".

**Waarom dit werkt:**
- Elke commit is atomair: je kunt elke stap individueel reverten
- Fouten zijn geïsoleerd: als stap 5 breekt, weet je precies wat het was
- Scope creep is onmogelijk: de agent kán niet afdwalen

**Waarom agents dit moeilijk vinden:**
LLM's zijn geoptimaliseerd om behulpzaam te zijn. "Terwijl ik hier toch ben, fix ik ook even dat andere ding" is hun natuurlijke neiging. De CLAUDE.md regels dwingen discipline af die tegen hun natuur ingaat. Dat is het punt.

### Concept 2: File-Based State

Alles wat de agent "weet" over het project staat in bestanden, niet in zijn context window. Dit betekent:

- De agent kan op elk moment vervangen worden door een andere agent (of een ander model) die dezelfde bestanden leest
- Context windows kunnen niet corrupt raken door accumulatie
- State is verifiable: jij kunt de bestanden lezen en zien wat de agent denkt

**Het verschil met v1:** In v1 was er één bestand (`progress.txt`) dat steeds groeide. In v2 zijn er vier gespecialiseerde bestanden die elk compact blijven en een eigen functie hebben.

### Concept 3: Loop Detection

```
failures.log:
iteration:12|action:fix-auth-middleware|error:Cannot find module './utils'|hash:a3f2c1
iteration:14|action:fix-auth-middleware|error:Cannot find module './utils'|hash:a3f2c1
iteration:16|action:fix-auth-middleware|error:Cannot find module './utils'|hash:a3f2c1
→ STUCK — agent stopt automatisch
```

De hash wordt berekend op basis van actie + error. Drie identieke hashes = de agent probeert steeds hetzelfde en faalt steeds hetzelfde. Stop. Markeer als STUCK. Laat een mens (jij) kijken wat er echt aan de hand is.

**Waarom dit cruciaal is:** Zonder dit mechanisme kan een agent honderden iteraties (en tientallen dollars aan tokens) verbranden op hetzelfde onoplosbare probleem. Vooral 's nachts of wanneer je niet kijkt.

### Concept 4: Adaptive Replanning

Het originele plan is een startpunt, geen contract. Triggers voor herplanning:

1. **3 opeenvolgende failures** — de huidige aanpak werkt niet
2. **Fundamenteel verkeerde aanname** — bijv. een API die anders werkt dan verwacht
3. **Dependency failure** — iets waar je op bouwde blijkt niet te bestaan

Het herplanningsproces:
1. Agent schrijft in progress.md *waarom* het plan niet werkt
2. Agent reviewt wat al af is — wat is herbruikbaar?
3. Agent schrijft een nieuw plan vanuit de huidige staat
4. Herplanning wordt apart gecommit (zodat je het kunt tracken)

**Waarom dit beter is dan v1:** In v1 ging de agent braaf door met een kapot plan. In v2 mag (en moet) hij het plan bijstellen wanneer de realiteit anders is dan de theorie.

### Concept 5: Lessons Compound

Elke fout is een investering in de toekomst. Het format is bewust simpel en actionable:

```markdown
- DO NOT use next-auth/prisma-adapter — incompatible with WooCommerce user model (discovered iteration 8)
- DO run build after typecheck — some errors only surface during build (discovered iteration 3)  
- The cart provider uses localStorage, not server state — don't try to SSR cart data (discovered iteration 11)
```

Dit is anders dan de CLAUDE.md regels. CLAUDE.md bevat permanente projectregels. lessons.md bevat run-specifieke ontdekkingen die in de loop van het bouwen naar boven komen.

### Concept 6: Git Commit Per Iteratie

Elke iteratie = één commit. Format: `ralph: step N - [beschrijving]`

Dit geeft je:
- **Volledige git history** van het bouwproces
- **Rollback** naar elk punt: `git revert` of `git reset --hard`
- **Blame tracking:** welke iteratie introduceerde welke code
- **Diff review:** exact zien wat elke stap veranderde

In v1 werd er gecommit wanneer de agent eraan dacht (of niet). In v2 is het een verplichte stap in de cyclus.

---

## 6. Emdash: de orchestratielaag

### Wat Emdash doet

Emdash is een desktop applicatie die meerdere coding agents parallel laat draaien met een visueel dashboard. Het is de **cockpit** bovenop Ralph v2.

**Kernfeatures:**
- **Parallel agents:** Elk in een eigen git worktree, volledig geïsoleerd
- **Live dashboard:** Zie welke agent waaraan werkt, wie klaar is, wie vastloopt
- **Diff review:** Bekijk de wijzigingen van elke agent side-by-side
- **PR creation:** Open pull requests direct vanuit Emdash
- **Provider-agnostic:** Werkt met Claude Code, Codex, Gemini, Kimi, en 15+ andere CLI agents
- **Ticket integratie:** Linear, GitHub Issues, Jira tickets direct toewijzen aan agents

### Wat Emdash NIET doet

Emdash is geen orchestratie-agent. Het doet geen:
- Automatische task decomposition
- Planning of herplanning
- Loop detection of state management
- Learning across agents

**Dat is waar Ralph v2 het aanvult.** Emdash geeft je de visuele controle en parallelle executie. Ralph v2 geeft elke individuele agent de discipline om betrouwbaar te werken.

### Emdash + Ralph v2 = het volledige systeem

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
│  EMDASH (orchestratielaag)                          │
│  ├── Spawnt agents in geïsoleerde worktrees         │
│  ├── Toont live status per agent                    │
│  ├── Toont diffs per agent                          │
│  └── Kill switch per agent                          │
└──────────────────┬──────────────────────────────────┘
                   │
┌──────────────────▼──────────────────────────────────┐
│  AGENTS (Ralph v2 discipline)                       │
│  ├── Agent A: worktree-a, steps 1-4                 │
│  ├── Agent B: worktree-b, steps 5-7 (parallel)     │
│  └── Agent C: worktree-c, steps 8-10 (parallel)    │
│                                                     │
│  Elk volgt: read state → do one thing → verify      │
│             → save state → commit                   │
└─────────────────────────────────────────────────────┘
```

---

## 7. Praktische workflow: stap voor stap

### Fase 0: Setup (eenmalig)

1. Installeer Emdash op je laptop
2. Clone de ralph-v2 template: `git clone https://github.com/gutsassistent/ralph-v2`
3. Zorg dat Claude Code (of Codex, of beide) geïnstalleerd en ingelogd is

### Fase 1: Project voorbereiden

```bash
# Ga naar je project
cd ~/projects/mijn-project

# Initialiseer Ralph v2
bash ~/devvv/ralph-v2/scripts/init.sh "Beschrijving van wat ik bouw"

# Of als het project al een CLAUDE.md heeft (zoals Caferico):
# Merge de Ralph v2 regels handmatig in je bestaande CLAUDE.md
```

**Vul `ralph/spec.md` in.** Dit is het belangrijkste moment. Definieer:
- Wat je bouwt (concreet, niet vaag)
- Wanneer het af is (meetbare criteria)
- Wat NIET in scope is (even belangrijk)
- Technische constraints

Hoe scherper de spec, hoe beter de agents werken. Een vage spec = vage output.

### Fase 2: Planning

Open je project in Emdash. Spawn je eerste agent met deze taak:

> "Read ralph/spec.md. Explore the existing codebase thoroughly. Create a detailed numbered implementation plan in ralph/progress.md. Each step must be independently completable, testable, and small enough for one iteration (max ~50 lines changed). Mark dependencies between steps. Do NOT start coding."

**Review het plan.** Dit is waar jij de kwaliteitspoort bent. Check:
- Zijn de stappen klein genoeg?
- Zijn dependencies correct geïdentificeerd?
- Is de volgorde logisch?
- Mist er iets?

Optioneel (Boris' tip): spawn een tweede agent die het plan reviewt als "staff engineer":

> "Read ralph/progress.md. Review this implementation plan as a senior engineer. Identify: missing steps, wrong ordering, risky assumptions, steps that are too large, and potential conflicts if steps run in parallel. Write your review as comments in ralph/progress.md."

Pas het plan aan op basis van de review. Commit het goedgekeurde plan.

### Fase 3: Executie

Nu spawn je worker agents in Emdash. Twee strategieën:

**Strategie A: Sequentieel (veilig, voor eerste keer)**
Eén agent die alle stappen in volgorde doorloopt:

> "Follow the Ralph v2 protocol in CLAUDE.md. Execute the plan in ralph/progress.md starting from the first NOT STARTED step. One step per iteration. Read state files first. Verify after each step. Commit after each step."

**Strategie B: Parallel (sneller, als je weet welke stappen onafhankelijk zijn)**
Meerdere agents, elk een groep onafhankelijke stappen:

- Agent A: "Execute steps 1-3 from ralph/progress.md following Ralph v2 protocol"
- Agent B: "Execute steps 4-6 from ralph/progress.md following Ralph v2 protocol"

Elke agent draait in een eigen worktree (Emdash regelt dit). Geen conflicts mogelijk zolang de stappen echt onafhankelijk zijn.

### Fase 4: Monitoren

Via het Emdash dashboard:

**Groen pad (alles gaat goed):**
- Agents werken, commits komen binnen, progress.md wordt bijgewerkt
- Je ziet diffs verschijnen per agent
- Niets te doen behalve af en toe een diff reviewen

**Geel pad (agent loopt vast):**
- Agent markeert stap als STUCK in progress.md
- failures.log toont herhaalde pogingen
- Jij kijkt wat er mis is, past de stap aan of helpt de agent

**Rood pad (fundamenteel probleem):**
- Meerdere agents lopen vast
- Het plan klopt niet
- Stop alle agents, herplan (terug naar Fase 2)

### Fase 5: Mergen en afronden

Wanneer alle stappen DONE zijn:
1. Review de volledige diff per worktree in Emdash
2. Merge branches (Emdash kan PRs openen)
3. Run volledige test suite op de gemergte code
4. Deploy

---

## 8. Waarom v2 beter is

### vs. Ralph v1 (wat we hadden)

| Aspect | v1 | v2 |
|---|---|---|
| State management | Eén groot progress.txt (800+ regels) | 4 gespecialiseerde bestanden |
| Loop detection | Geen — agent loopt eindeloos vast | failures.log met automatische stop na 3x |
| Rollback | Geen — handmatig zoeken | Git commit per iteratie |
| Planning | Statisch PRD, nooit bijgesteld | Adaptive replanning bij failures |
| Learning | Geen — dezelfde fout meerdere keren | lessons.md accumuleert kennis |
| Parallelisme | Niet mogelijk | Via Emdash worktrees |
| Visuele controle | Geen — terminal output | Emdash dashboard |
| Verificatie | Soms vergeten | Verplichte stap in elke cyclus |

### vs. Ralph v1 uit de tweet (@spacepixel)

| Aspect | Tweet versie | v2 |
|---|---|---|
| Aanpak | "Build while you sleep" | "Build while you watch" |
| Controle | Fire-and-forget | Jij bent de orchestrator |
| Feedback | Pas achteraf | Real-time via dashboard |
| Fouten | Compound ongemerkt | Gestopt na 3 pogingen |
| Plan | Eenmalig | Adaptief |
| Kosten | Ongecontroleerd | Zichtbaar, stuurbaar |
| Parallellisme | Eén agent | Meerdere via Emdash |

### vs. Andere tools

| Aspect | Gas Town | Conductor | Claude Squad | Ralph v2 + Emdash |
|---|---|---|---|---|
| Complexiteit | Extreem (7 rollen) | Laag | Minimaal | Medium |
| Kosten | ~$100/uur | Normaal | Normaal | Normaal |
| Platform | Cross-platform | macOS only | Terminal | macOS + Linux |
| Discipline per agent | Geen standaard | Geen standaard | Geen standaard | Ralph v2 regels |
| Learning across runs | Nee | Nee | Nee | lessons.md |
| Loop detection | Nee | Nee | Nee | failures.log |
| State management | Eigen systeem (Beads) | Geen | Geen | File-based |
| Instapdrempel | Stage 7+ | Stage 4+ | Stage 3+ | Stage 3+ |

---

## 9. Tips en valkuilen

### De spec is alles
80% van het succes zit in `ralph/spec.md`. Een vage spec ("bouw een auth systeem") levert vage resultaten. Een scherpe spec ("implementeer NextAuth.js v5 met magic link login via Resend, Google OAuth als alternatief, sessie opslaan in JWT, bestaande WooCommerce klanten matchen op email") levert scherpe resultaten.

### Begin sequentieel
Je eerste project met Ralph v2: gebruik één agent, sequentieel. Leer hoe de state files werken, hoe de cyclus voelt, waar het schuurt. Pas daarna parallel.

### Review het plan alsof je leven ervan afhangt
Het plan is het fundament. Een fout in het plan vermenigvuldigt zich door elke iteratie. Besteed meer tijd aan het plan reviewen dan je denkt nodig te hebben.

### Laat lessons.md groeien
Verwijder nooit entries uit lessons.md tijdens een run. Ook niet als ze "niet meer relevant" lijken. De agent weet niet wat relevant is — jij wel, achteraf.

### Kleine stappen > grote stappen
Een stap die "max ~50 regels code verandert" is beter dan een stap die "een heel module implementeert". Hoe kleiner de stap, hoe beter de loop detection werkt, hoe makkelijker rollback is, hoe sneller je problemen vindt.

### Herplanning is geen falen
Als het plan niet werkt, is herplannen de juiste actie. Het voelt als tijdverlies, maar het alternatief (doorbouwen op een kapot fundament) is altijd erger.

### Parallelle agents: alleen bij echte onafhankelijkheid
Twee agents die allebei `package.json` moeten aanpassen zijn niet onafhankelijk, ook al raken ze verder verschillende bestanden. Wees conservatief met parallelliseren. Merge conflicts zijn tijdrovender dan sequentieel werken.

### Het dashboard is voor checkpoints, niet voor staren
Check het dashboard elke 10-15 minuten, niet continu. Als je continu kijkt, ben je aan het babysittten. Vertrouw de discipline van de cyclus en grijp in bij rood/geel signalen.

### Kosten in de gaten houden
Elke iteratie = een API call met fresh context. 50 iteraties × Sonnet = ~$5-10. 50 iteraties × Opus = ~$30-50. Gebruik het goedkoopste model dat de taak aankan. Routine implementatie → Sonnet. Architectuurbeslissingen → Opus.

---

## Bijlage: Quick Reference

### Bestanden die JIJ beheert:
- `ralph/spec.md` — wat we bouwen

### Bestanden die AGENTS beheren:
- `ralph/progress.md` — plan + state
- `ralph/lessons.md` — geleerde lessen
- `ralph/failures.log` — faaldetectie

### Bestanden die JIJ + AGENTS beheren:
- `CLAUDE.md` — project regels (jij schrijft, agents volgen)

### Agent starten (Emdash):
- Planning: "Read ralph/spec.md, create implementation plan in ralph/progress.md"
- Executie: "Follow Ralph v2 protocol in CLAUDE.md, execute from first NOT STARTED step"
- Review: "Review ralph/progress.md as senior engineer, identify risks"

### Signalen:
- ✅ Agent commit met "ralph: step N" = voortgang
- ⚠️ BLOCKED in progress.md = agent wacht op input
- 🛑 STUCK in progress.md = loop detected, menselijke interventie nodig
- 🔄 Replan commit = agent heeft het plan bijgesteld
