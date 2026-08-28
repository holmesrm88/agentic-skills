---
name: harness
description: Run a disciplined TDD implementation loop against a Jira story or a small idea. Two phases — init decomposes the work into small, independently committable features and generates a deterministic pre/post test gate; code implements one feature at a time through a red-green-commit cycle with human approval at each step. Use when the user says "harness init", "harness code", "start the harness", "let's implement PROJ-1234", "break this story into features", or otherwise wants to begin or continue structured implementation work on a specific story. Also use to resume — the skill reads its own state from disk and picks up mid-feature. Do NOT use for deciding whether work needs planning (use bmad-intake) or for reviewing code that already exists (use java-code-review).
---

# Harness

A two-phase implementation loop that keeps long agentic work honest: decompose first, then implement one feature at a time with a test gate on both sides and a human at every state transition.

The phases are separate invocations by design. Everything the second phase needs lives on disk, so a context window ending mid-feature costs nothing — the next session reads the state and continues.

## Phase selection

Route on what the user asked for:

- **"harness init"**, or a story/idea with no `.harness/` present → Phase 1.
- **"harness code"**, or continuing work with `.harness/` present → Phase 2.
- **Ambiguous** → read `.harness/change-log.md`. Its current-state header says where things stand. If it does not exist, run Phase 1.

Always read the change-log header before doing anything else. Acting on assumed state is the main way this loop corrupts itself.

## Non-negotiables

**Never push, never open a PR, never merge.** This skill commits locally. Everything downstream is a separate stage with its own review.

**Never run a generated script without showing it first.** `init.sh` executes build and test commands. Display it and get approval before its first run.

**Stop at every checkpoint.** Red, green, and commit are three separate human decisions. Do not chain them because the outcome looks obvious. The whole value of the loop is that a person sees each transition.

**One feature per invocation.** When a feature is committed, report and stop. Do not start the next one.

**Never edit `.gitignore`.** Local exclusions go in `.git/info/exclude`, which is untracked. See Phase 1.

---

# Phase 1 — `harness init`

Turn a story or idea into a reviewed plan plus a working test gate. No production code is written in this phase.

### 1.1 Check the ground

Verify a clean working tree (`git status`). A dirty tree means either uncommitted work to deal with first or an abandoned harness run — resolve it before scaffolding.

If `.harness/` already exists, do not overwrite it. Report what is there and ask whether to resume, extend with a new story, or archive and restart.

### 1.2 Understand the work

For a Jira story: read it, and read what it references. For an idea: get enough to state a testable outcome.

Scope check — if the work is large, ambiguous, architecturally consequential, or naturally spans multiple stories, say so and recommend planning first rather than decomposing it here. This skill's idea path is the escape hatch for small, clear work. Decomposing a genuinely large intent here duplicates the planning layer and produces worse boundaries than it would.

Ground the work in the codebase before decomposing. Where does this change land, what conventions govern that area, what already exists that it should reuse. If the area is unfamiliar, run reconnaissance first — feature boundaries drawn without knowing the code are guesses, and every downstream step inherits them.

**Name the gaps explicitly.** Anything the story does not specify that implementation will need: unstated acceptance criteria, unclear error behavior, undefined edge cases, missing non-functional requirements. Surface these to the user now. A gap found during decomposition costs a question; the same gap found during implementation costs a rewrite.

### 1.3 Scaffold

Run `scripts/scaffold.sh`. It creates `.harness/`, registers it in `.git/info/exclude`, and writes skeleton files. Read the script before running it if the project layout is unusual.

### 1.4 Generate the gate

Write `.harness/init.sh` — the deterministic check run before and after every feature. `references/init-sh-design.md` has the design and per-build-tool templates.

Three things matter and are easy to get wrong:

**It gates on new failures, not on green.** Most real codebases have pre-existing failures or flakes. A gate demanding green refuses to start. Capture a baseline first, then compare against it.

**It has two lanes.** A fast lane (affected module or package) for the per-feature cycle, and a full lane for final verification. A full suite on both sides of every feature makes the loop unusable at enterprise test-suite runtimes.

**It is deterministic.** Fixed seeds, no network where avoidable, no dependence on wall-clock time or test ordering. A gate that flakes teaches the user to ignore it.

Show the script to the user, then capture the baseline and show them what it found. Pre-existing failures are useful information about the codebase in their own right.

### 1.5 Decompose

Break the work into features. This is the highest-leverage step in the entire loop — everything downstream inherits these boundaries.

Each feature must be:

- **Independently testable.** A specific test can be written that fails before and passes after.
- **Independently committable.** The repo builds and the gate passes at every feature boundary.
- **Dependency-ordered.** Later features may depend on earlier ones; never the reverse.
- **Session-sized.** Finishable in one sitting. If it needs more than a handful of files or a couple of hours, split it.
- **Behavior-shaped, not layer-shaped.** "Add tenant filtering to order lookup" is a feature. "Add the repository layer" is not — it cannot be tested or shipped alone.

Mark any feature where TDD does not apply and say why. See `references/state-contract.md` for the exclusions and the file format.

### 1.6 Review gate

Write the feature files and the change-log, then **stop and present the decomposition for review**. Show the ordered list with one line each, plus the gaps found in 1.2 and what the baseline captured.

Do not proceed to implementation. `harness code` is a separate invocation, and the user reviewing the plan before code exists is the point of splitting the phases.

---

# Phase 2 — `harness code`

Implement exactly one feature through red → green → commit, pausing for approval at each transition.

### 2.1 Load state

Read `.harness/change-log.md` — the current-state header tells you the active feature and the position within it. Confirm against the feature files' `status` fields; if the two disagree, trust the feature files and say so, since they are written per-transition while the header is a summary.

Check `git status`. Uncommitted changes with a feature in `red` status are expected — that is a written failing test. Uncommitted changes with a feature in `pending` are not; report and ask.

Then resume at the right point: `pending` → 2.2, `red` → 2.3, `green` → 2.4.

### 2.2 Red

Run the fast gate first to confirm a clean starting point relative to baseline.

Write the failing test the feature file specifies. Test only; no production code.

Run the fast gate again and **classify the failure**:

- **Valid red** — the test executes and fails on its assertion, for the reason the feature describes. Proceed.
- **Invalid red** — compilation error, failure in setup or fixtures, missing class, or a failure unrelated to the feature's intent. The test is wrong, not the code. Report exactly what happened and fix the test before continuing.
- **Passed immediately** — stop. Either the behavior already exists, or the test asserts nothing meaningful. Both matter. A test that cannot fail is worse than no test, because it reports safety that is not there.

Set status to `red`, update the change-log, tell the user which case occurred with the actual failure output, and **wait**.

### 2.3 Green

Only on explicit go-ahead.

Write the minimum production code to pass the test. Follow the conventions established for the affected area — matching the codebase matters more here than any general preference.

Run the fast gate. Report against baseline: the target test passes, and no new failures elsewhere. If something else broke, that is the news — lead with it.

Set status to `green`, update the change-log, and **wait**.

### 2.4 Commit

Only on explicit approval.

Commit test and implementation together. Match the repository's existing commit conventions — read recent history rather than imposing a format. Include the story key if the project uses one.

Never commit `.harness/` itself; it is excluded, and verifying that stays true is cheap.

Update the feature file to `committed`, rewrite the change-log header to point at the next feature, and append to history.

Then **report and stop.** State what was committed, what remains, and what the next feature is. Do not begin it.

### 2.5 When TDD does not apply

For features marked as such — pure refactors under existing coverage, dependency bumps, configuration, generated code — skip the red step. Run the gate before, make the change, run the gate after, and require that the existing tests behave identically. Say plainly that TDD was skipped and why. Still stop for approval before committing.

### 2.6 Gate exit codes

`0` passed, `1` regression, `2` gate invalid. Treat `2` as a hard stop — it means the gate ran but tested nothing, usually a `gate_scope` that matches no tests. A gate that executed zero tests is a broken instrument reporting success, and accepting it silently is how a regression reaches the PR. Fix the scope, do not proceed.

Every gate report to the user should include how many tests actually ran, so a shrinking count is visible rather than silent.

### 2.7 When something goes wrong

Set the feature's status to `blocked`, record what happened in the change-log, and stop. Do not attempt recovery by trying alternatives — a loop that improvises past a failed gate is how silent breakage enters a codebase. Report, and let the user decide.
