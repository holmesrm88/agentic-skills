# BMad v6 Environment Reference

Background for interpreting `detect_bmad.sh` output. **This describes v6 as of mid-2026 and will drift.** Where this file and discovery disagree, discovery wins — it is looking at the actual installation, this file is a memory.

## Contents
- What BMad is
- Directory layout
- Modules
- The lifecycle
- Scale-adaptive tracks
- State and artifacts
- Invocation surface
- Known issues
- Corporate environment notes

## What BMad is

An open-source (MIT) AI-driven agile development framework from BMad Code, LLC, at `github.com/bmad-code-org/BMAD-METHOD`. Roughly 50k GitHub stars and active near-daily development. It provides specialized agent personas — PM, Architect, Developer, UX, Scrum Master, QA and others — plus guided workflows spanning analysis, planning, architecture, and implementation handoff.

Its design premise is that the human keeps making the decisions while the workflows make those decisions explicit and carry them forward as context. It is a *facilitation* framework, not an autocomplete. Workflows expect real participation.

Note the trademark: BMad and BMAD-METHOD are trademarks of BMad Code, LLC, separate from the MIT code license. Referring to it is fine; naming internal artifacts after it deserves a moment's thought.

## Directory layout

A v6 install writes into the project root:

```
project/
├── _bmad/                      installation root
│   ├── _config/                user customizations (survives updates)
│   ├── core/                   universal framework
│   ├── bmm/                    BMad Method — the development module
│   ├── bmb/                    BMad Builder — create custom agents/workflows
│   └── ...                     other installed modules
├── _bmad-output/               artifacts (configurable name)
│   ├── planning-artifacts/
│   └── implementation-artifacts/
└── .claude/                    host tool integration, when claude-code selected
```

The underscore prefix is deliberate — v6 moved off `.bmad` specifically because dot-directories get filtered out by IDE indexing and LLM context systems, which made the framework's own content invisible to the agents meant to use it.

**Legacy layouts** from v4/v5 — `.bmad`, `.bmad-core`, `.bmad-method`, a plain `bmad/`, or `_cfg` — are not migrated automatically and must be removed by hand. Stale IDE command folders from a previous version can shadow current ones, which produces confusing failures where a command exists but behaves like an older release.

## Modules

Installed independently; only what was selected will be present.

| Code | Name | Purpose |
|---|---|---|
| `core` | BMad Core | Universal framework, `bmad-master`, help system |
| `bmm` | BMad Method | Software development lifecycle — the main one |
| `bmb` | BMad Builder | Create custom agents, workflows, and modules |
| `tea` | Test Architect | Risk-based test strategy, automation, release gates |
| `cis` | Creative Intelligence Suite | Brainstorming, innovation, design thinking |
| `gds` / `bmgd` | Game Dev Studio | Unity, Unreal, Godot workflows |

`bmb` is the answer to "I want to build my own agent personas" — that capability already exists and does not need reimplementing.

## The lifecycle

BMM runs a four-phase lifecycle:

1. **Analysis** — brainstorming, product brief, market and domain research. Optional; skipped for smaller work.
2. **Planning** — PRD, requirements, success metrics. Produces the specification.
3. **Solutioning** — architecture and ADRs, then epic and story breakdown. Note the v6 ordering change: **stories are created after architecture**, so the work breakdown is technically informed rather than guessed. Ends with an implementation-readiness gate.
4. **Implementation** — story drafting, approval, context generation, development, and review, one story at a time.

## Scale-adaptive tracks

BMad routes among three tracks by assessed complexity (levels 0–4):

- **Quick Flow (0–1)** — bug fixes and clear-scope features. Tech spec only, no PRD, one or two stories. Targets hours, not days.
- **BMad Method (2–3)** — the full PRD → architecture → epics → stories path.
- **Enterprise (3–4)** — adds deeper compliance, security, and test-strategy work, typically with TEA.

**This is why the intake skill does not pre-select a track.** BMad performs its own assessment and will raise a scope alert and recommend escalation when a request outgrows the track it started in, both at invocation and mid-discovery. Pre-selecting fights a mechanism that has better information.

## State and artifacts

`bmm-workflow-status.yaml`, written by workflow initialization, tracks progress through the planning phases. Its presence means a workflow is in flight and restarting would discard decisions.

Planning artifacts — brief, PRD, UX spec, architecture — land in the planning artifacts folder. Story files carry context between the planning and implementation phases; they are the mechanism by which decisions persist across sessions rather than being re-explained.

## Invocation surface

Command naming has varied across releases and host tools. Documented forms include slash commands like `/bmad-help`, `/bmad-bmm-create-prd`, and `/bmad-bmm-create-architecture`, while other sources show a CLI-ish `bmad <agent> <workflow>` form. Hosts that do not use slash prefixes may use `$`-prefixed names instead.

**Do not rely on any of these.** Enumerate the installed commands and use what exists. Where a universal entry point or help skill is available, prefer it — it resolves the current lifecycle correctly without hardcoding.

## Known issues

- **Literal `{output_folder}` directory.** A long-running installer bug creates an unresolved template directory at the project root. Reported fixed in 6.4.0 but reproduced as recently as 6.7.1. The dedicated `--output-folder` flag works; `--set core.output_folder=...` does not, because `--set` is applied as a post-write patch after directories are created. If discovery finds this directory, artifacts may be split across two locations.
- **Config path drift.** Early v6 used per-module `config.yaml`; later releases use a central `config.toml` with `[core]` and `[modules.*]` sections. Check both.
- **Host restart required.** Newly installed skills and commands often do not appear until the host tool restarts. "The command does not exist" frequently means "restart first."

## Corporate environment notes

Relevant on a managed work machine:

- **Prerequisites** are Node 20.12+, Python 3.10+, and `uv`. The last is likely to be unfamiliar to a security reviewer.
- **`npx bmad-method install` fetches at install time** and writes into the project tree. On a shared repo, that is a commit that changes how the team works — raise it before running it.
- **GitHub anonymous API calls are capped at 60/hour per IP,** and each external module resolution consumes one. Behind corporate NAT or on shared CI runners, that budget is shared with everyone else on the same egress address, so installs can fail for reasons unrelated to the machine doing them.
- **Artifacts are documents about the product.** PRDs and architecture documents describing internal systems are company IP and belong in the repo or the sanctioned document store, not in a personal workspace or a web-based bundle.
