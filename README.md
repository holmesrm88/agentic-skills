# Agentic Engineering Skills

A set of Claude Skills for Java development work: estimating and orienting to unfamiliar code, reviewing it, and running a disciplined implementation loop from a ticket through to a reviewed, deployed-and-verified, committed change.

Each skill is a folder containing a `SKILL.md` (the instructions), optional `references/` (detail loaded on demand), and optional `scripts/` (deterministic work that shouldn't be re-derived every run). Nothing needs installing beyond copying the folders into place.

## The skills

| Skill | Use it when | Key output |
|---|---|---|
| [`story-estimator`](skills/story-estimator) | Prepping a backlog for grooming | Calibrated points, questions, ticket comments |
| [`repo-recon`](skills/repo-recon) | Orienting to code you didn't write | `ARCHITECTURE_BRIEF.md` |
| [`java-code-review`](skills/java-code-review) | Reviewing a diff, class, or PR | Severity-ranked findings |
| [`bmad-intake`](skills/bmad-intake) | Starting a unit of work, before deciding how | A route: build, recon, plan, or escalate |
| [`harness`](skills/harness) | Implementing a story, feature by feature | Commits, gated by tests |
| [`review-panel`](skills/review-panel) | A story is done and heading for a PR | Triaged findings, some as new work |
| [`gh-actions-triage`](skills/gh-actions-triage) | A GitHub Actions run fails | Classified cause, proposed fix |
| [`dev-env-verify`](skills/dev-env-verify) | A PR's build is green, before marking it ready for review | Pass/fail per acceptance criterion, with evidence |

### story-estimator

Estimates story points for unpointed Jira stories ahead of grooming, calibrated against how the team's past work actually went rather than against generic heuristics.

Two hard rules. **Never model individuals** — `analyze_history.py` strips assignee, reporter, and every other person field before any analysis runs; this is an estimation aid, not a throughput-surveillance tool. **Refuse rather than guess** — if the calibration history is too thin or too corrupted, it says so and stops instead of producing a confident number nobody should trust.

Runs in two phases: calibrate first, alone, until the team trusts what it says about their own past work — often a finding like "your 3s carry over 89% of the time and take a median of 7.5 days" — then estimate by reference class against real completed stories, not a fitted formula. Clarifying questions are posted before the number, never to the story-points field itself, because a populated field reads as a decision that's already been made.

### repo-recon

Maps an unfamiliar codebase and writes an architecture brief: build system, module topology and dependency direction, entry points, data layer, test and CI posture, ownership from git history, and a load-bearing-vs-debt split.

Includes `repo_stats.sh`, a read-only script that gathers language mix, churn hotspots, dormant directories, and a per-directory ownership map in one pass. The ownership map is the part that matters most on a new team — it turns "I don't know who to ask" into a name.

The Java reference covers build-tool fingerprints, framework detection, entry-point and persistence discovery, and version-specific gotchas.

### java-code-review

Reviews Java against a senior-level checklist, ranked by severity, with file locations and concrete fixes. Leads with what will cause an incident rather than listing thirty equally-weighted items.

The checklist covers thirteen categories: correctness, null and `Optional`, resource management, concurrency, exceptions, collections and equality, API design, streams, persistence and transactions, security, performance, tests, and modernization opportunities — each with the specific shapes those failures take in Java.

Deliberately calibrated to match an existing codebase's conventions rather than impose preferences, and to state what it can't verify from a diff alone instead of asserting it.

### bmad-intake

A triage gate that runs *before* the [BMad Method](https://github.com/bmad-code-org/BMAD-METHOD), not a reimplementation of it. BMad already right-sizes work once you're inside it; what it doesn't decide is whether to enter at all.

Scores work across six signals — requirement clarity, blast radius, reversibility, codebase familiarity, duration, coordination — and routes to one of four outcomes: straight to implementation, recon first, recon then BMad, or escalate to a human because the blocker isn't technical.

`detect_bmad.sh` discovers what's actually installed rather than assuming a command surface, since BMad's invocation syntax has changed across releases. It reports honestly when something is missing instead of substituting remembered syntax.

### harness

A two-phase TDD implementation loop with state on disk, so a context window ending mid-feature costs nothing.

**`harness init`** decomposes a story into small, independently committable features and generates `init.sh` — a test gate that compares against a captured baseline rather than demanding green, because most real codebases have pre-existing failures. Two lanes: a fast one scoped to the affected module for the per-feature cycle, and a full one before handoff. Stops for review before any code is written.

**`harness code`** implements one feature through red → green → commit, pausing for human approval at each transition. The red step classifies the failure: a valid red fails on its assertion for the reason the feature describes; a compile error or a test that passes immediately are both stop conditions.

State lives in `.harness/`, excluded via `.git/info/exclude` — local only, and without touching the tracked `.gitignore`.

### review-panel

Runs four isolated reviewers in parallel over a completed story's diff — security, ghost tests, clean code, correctness — then deduplicates, ranks, and presents one batch for approval.

Isolation is the design. Independent agreement between reviewers is evidence; agreement after one has seen another's report is an echo that reads identically in the output. So: same packet to all four, no cross-talk, synthesis only in the orchestrator.

`collect_diff.sh` computes the exact line ranges the story touched, which makes in-scope-vs-pre-existing a lookup rather than an argument. That boundary is what keeps a reviewer's unrelated discovery from quietly doubling the size of the PR.

Approved findings become new harness features, tickets, or inline fixes. Round cap of two, because the loop doesn't naturally terminate.

### gh-actions-triage

Diagnoses a failed GitHub Actions run: fetches only the failed steps, extracts the
error from the noise, classifies it, and proposes a fix.

Classification comes before diagnosis. Five categories — base-branch breakage, real
failure, flake, config drift, infrastructure — checked in that order, because
debugging your own diff against an already-red pipeline is the most expensive
mistake available. A flake classification requires positive evidence; "just re-run
it" is how real failures ship.

Token-conscious by design: `gh run view --log-failed` pulls only failed steps, the
full log is saved to disk for grepping rather than read into context.

### dev-env-verify

Confirms a deployed change does what the story asked, in the ephemeral environment its PR spun up, before a human reviewer spends time on it. Local tests passing means the code does what its tests say; this asks whether the deployed thing does what the *story* said — those come apart more often than they should.

**Never handles credentials.** The person logs into the environment themselves; the skill drives the session already established in the browser. If a login wall appears mid-run, it stops and hands back rather than attempting to authenticate around it.

Writes the check list from the acceptance criteria *before* opening the browser — exploring first and judging afterward produces confirmation bias. Each check reports pass, fail, or **blocked**, and blocked is not pass: a check that couldn't run because of a login wall or missing data is unverified, not green. Capped at three verification rounds before it stops and brings in a person.

## How they compose

```
                  story-estimator  ──► calibrated points  ──► grooming
                                                     │
                    new intent ──► [planning] ──► stories
                                                     │
existing ticket ─────────────────────────────────────┤
                                                     ▼
                          bmad-intake  ──► route the work
                                                     │
                    repo-recon ◄────────────────────┤  (unfamiliar code)
                                                     ▼
                               harness init  ──► features + test gate
                                                     ▼
                               harness code  ──► red → green → commit
                                                     ▼
                               review-panel  ──► findings ──┐
                                                     ▼      │
                                              verify A.C.   │ new features
                                                     ▼      │ loop back ───┘
                                                   push        (max 2 rounds)
                                                     │
                                       CI fails ◄────┴────► CI green
                                            │                    │
                                  gh-actions-triage       dev-env-verify
                                            │                    │
                                      fix, push, rerun     ready for review
```

`java-code-review` is used standalone and also serves as the correctness reviewer inside `review-panel`. `repo-recon` feeds brownfield context into planning and into `harness init`. `story-estimator` runs upstream of all of it, ahead of grooming; `gh-actions-triage` and `dev-env-verify` are the two gates a pushed change passes through before a human reviews it.

## Install

Copy the skill folders where your Claude environment looks for them:

```bash
git clone <this-repo> agentic-skills
cp -r agentic-skills/skills/* ~/.claude/skills/
```

Per-project instead of global:

```bash
mkdir -p .claude/skills && cp -r /path/to/agentic-skills/skills/* .claude/skills/
```

Restart the host afterwards — newly added skills often don't appear until it reloads. Verify the scripts are executable:

```bash
chmod +x ~/.claude/skills/*/scripts/*.sh
```

## Design principles

These are consistent across all eight and worth preserving in anything added later.

**Don't guess.** Discover the environment at runtime rather than reciting remembered syntax. `detect_bmad.sh` enumerates installed commands instead of assuming them; `repo_stats.sh` reports UNKNOWN rather than inferring. A confidently wrong answer is worse than an admitted gap, because it can't be spotted.

**Verify before asserting.** Check the config before claiming a bug. During development, a suspected dirty-checking issue evaporated once `open-in-view=false` was confirmed — and a missing-404 finding survived the same scrutiny. Both outcomes are the process working.

**Match the codebase.** Existing conventions beat personal preference. Flag a convention only when it causes the specific problem at hand.

**Fail loudly, never silently green.** A gate that reports success without testing anything is worse than no gate. `init.sh` asserts that tests actually executed and exits `2` for "gate invalid" — treated as a stop, not a pass.

**Human at every state transition.** Red, green, and commit are three separate decisions. Findings become work only after a person approves the batch. The judgment steps are the point.

**Terminate explicitly.** Any loop that generates its own work needs a cap and a provenance chain. Two rounds, then escalate.

## Status

Developed against [`spring-petclinic`](https://github.com/spring-projects/spring-petclinic) as a test codebase. Every script has been run; the review and recon outputs were produced against real code rather than illustrated.

Not yet exercised against a production codebase. Expect the gate scoping, the triage thresholds in `bmad-intake`, and the decomposition sizing in `harness` to need calibration against how work is actually sized in practice.

## License

MIT — see [LICENSE](LICENSE).

BMad and BMAD-METHOD are trademarks of BMad Code, LLC. `bmad-intake` interoperates with the BMad Method but is not affiliated with or endorsed by BMad Code, LLC.
