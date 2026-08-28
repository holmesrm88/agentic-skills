---
name: repo-recon
description: Systematically map an unfamiliar codebase and produce a written architecture brief covering build system, module topology, entry points, data layer, test posture, team ownership, and a risk register. Use this whenever the user is orienting to code they did not write — onboarding at a new job, inheriting a service, picking up a legacy repo, or asking things like "help me understand this codebase", "what does this service actually do", "give me the lay of the land", "where do I start", or "map this repo for me". Use it even when the request sounds casual or the user only points at a directory without saying the word "architecture". This skill is for orientation to a whole codebase or subsystem, NOT for critiquing the quality of a specific diff or class (use java-code-review for that).
---

# Repo Recon

Produce a written architecture brief for a codebase the reader does not know, fast enough to be useful on day one and accurate enough to be trusted in week three.

The output is a document, not a chat response. Someone should be able to read it cold and know where to put their hands.

## Operating principles

**Evidence over inference, and label the difference.** Every structural claim should point at a file, a config key, or a command's output. When you infer something you could not verify — "this looks like it was extracted from a monolith" — mark it as an inference. A brief that mixes confident fact with confident guess is worse than no brief, because the reader cannot tell which parts to trust.

**Breadth first, depth on request.** Resist the urge to read every file. Map the whole territory at a shallow depth, then go deep only where the reader's stated purpose demands it. A brief that covers 100% of the repo at 20% depth is more useful on day one than one covering 20% at 100%.

**Read the repo's history, not just its present.** Git tells you what is alive, what is fossilized, and who to ask. A directory nobody has touched in three years and a directory with commits from last Tuesday deserve very different amounts of the reader's attention.

**Never invent.** If you cannot determine the framework, the deployment target, or what a module does, say so and say what you would need to find out. "Unknown — no CI config found in the repo; likely configured externally" is a genuinely useful line. A fabricated answer is a landmine.

**Note conventions, not just structure.** The unwritten rules matter more than the folder layout for someone about to open their first pull request. How are packages named? Do they use constructor injection or field injection? Are tests colocated? Is there a house error-handling pattern? These are what make a newcomer's first PR look native or foreign.

## Workflow

Work through these phases in order. Each builds on the last. Skip a phase only if it is genuinely inapplicable, and say so in the brief rather than silently omitting it.

### Phase 0 — Orient before reading

Establish size and shape so you can budget attention. Run `scripts/repo_stats.sh` from the repo root — it produces file counts by language, build file inventory, directory sizes, churn hotspots, and a contributor map in one pass. If the script cannot run (no bash, no git), fall back to the equivalent commands documented inside it.

Read the README, CONTRIBUTING, and any `docs/` or `adr/` directory first. Treat these as claims to be verified, not ground truth — documentation drifts. Note explicitly where docs and code disagree; that gap is often the most valuable thing in the brief.

### Phase 1 — Build system and dependencies

Identify the build tool and how the project is actually assembled: what commands build it, test it, and run it locally. Extract the module graph if it is multi-module. Note the language version target, since it constrains everything the reader can write.

Survey dependencies for the frameworks that dictate the code's shape, the age of key dependencies, and anything unmaintained or pinned suspiciously old. Do not run vulnerability scans and report CVEs unless asked — flag "these look old" and let the reader decide.

For Java specifics — Maven vs Gradle, framework fingerprints, common project layouts — read `references/java.md`.

### Phase 2 — Module topology and dependency direction

Map the top-level modules or packages and, more importantly, which depend on which. Direction matters more than inventory: a domain layer that imports the web layer is a finding, not a detail.

Identify the architectural pattern in use if there is one — layered, hexagonal, package-by-feature, package-by-layer — and whether it is followed consistently or aspirationally. Name the places where it breaks down.

### Phase 3 — Entry points and runtime surface

Find every way the outside world gets in: HTTP endpoints, message consumers, scheduled jobs, CLI commands, gRPC services, servlet or filter chains. This is the highest-value section for a newcomer, because tracing inward from an entry point is how you learn a codebase by doing.

For each entry point family, note where the handlers live so the reader can jump straight there.

### Phase 4 — Data and state

Identify persistence technology, where the schema lives, and how migrations are managed. Locate the boundary objects — entities, DTOs, domain models — and note whether they are kept separate or whether persistence types leak into the API layer.

Also map external state: caches, queues, third-party services, and feature flags. Anything the process talks to that it does not own.

### Phase 5 — Test and CI posture

Characterize the testing strategy honestly: what layers are tested, what frameworks are in use, what the naming and structure conventions are, and roughly how much of the code has tests near it. Distinguish unit from integration from end-to-end, and note anything that requires infrastructure to run.

Find the CI configuration and describe what actually gates a merge. "Tests run but do not block" is a critical thing for a newcomer to know before their first PR.

### Phase 6 — Ownership and activity

From git history, build a picture of who works where. For each major module, identify the most frequent recent committers. This gives the reader a name to ask instead of a wall to stare at.

Separately, flag directories with no commits in over a year. Dormant code is either stable and load-bearing or dead and removable, and the brief should say which one it cannot tell.

### Phase 7 — Synthesis: load-bearing vs. debt

This is the judgment section and the reason a human values the brief. Sort what you found into two lists:

**Load-bearing** — code that is central, heavily depended upon, or touched constantly. Change here is expensive and reviewed hard. The reader should approach it with care.

**Likely debt** — duplicated logic, dead code, dependencies frozen in time, TODO clusters, sprawling classes, patterns abandoned halfway through a migration. Frame these neutrally and with evidence. The reader may be talking to the person who wrote it, so "three competing HTTP client wrappers exist (paths…), suggesting an incomplete consolidation" lands well where "this is a mess" does not.

Close with open questions: the specific things you could not determine and would ask a teammate on day one. A good brief makes the reader look prepared, not ignorant.

## Output format

Write the brief to `ARCHITECTURE_BRIEF.md` in the working directory (not inside the repo being analyzed, unless asked). Use this structure:

```markdown
# Architecture Brief: [repo name]
*Generated [date] · [commit sha] · [N] files, [N] KLOC*

## TL;DR
[Five sentences maximum. What this system is, what it does, what shape it is in.
Written for someone who will read only this section.]

## How to build and run it
[Exact commands. Prerequisites. Anything that will not work on a fresh machine.]

## Module map
[Table or tree: module → responsibility → depends on]

## Entry points
[Table: type → route/trigger → handler location]

## Data layer
[Persistence tech, schema location, migration tooling, entity/DTO boundary]

## Testing and CI
[What is tested, how it is run, what gates a merge]

## Conventions to follow
[The unwritten rules a first PR should respect]

## Ownership map
[Module → recent primary committers]

## Load-bearing areas
[What to touch carefully, and why]

## Likely debt
[Neutral, evidenced observations]

## Open questions
[What to ask on day one]
```

Adapt the sections to the repo — drop what genuinely does not apply and say why. Keep prose tight; the reader is orienting, not studying.

## Adapting to purpose

Ask what the reader is orienting *for* if it is not already clear, because it changes the depth allocation:

- **General onboarding** — even coverage, weight Phase 6 and Conventions heavily.
- **Fixing a specific bug** — go deep on the relevant entry point and trace inward; keep the rest shallow.
- **Adding a feature** — weight the module map, conventions, and the seam where the feature lands.
- **Assessing for a migration or rewrite** — weight dependencies, debt, and test coverage; this is the one case where the debt list is the main event.

If the purpose is unclear and the user is not around to ask, default to general onboarding and note the assumption at the top of the brief.
