---
name: bmad-intake
description: Triage a unit of development work before starting it — decide whether it warrants the BMad Method planning process, goes straight to implementation, needs codebase reconnaissance first, or is really a human conversation rather than a technical task. Then prime brownfield context and hand off to the installed BMad workflow. Use this at the START of any non-trivial development work — when the user says "I need to add/build/change X", "let's start on Y", "kick off BMad for Z", "should we plan this out", or hands over a ticket, epic, or feature request. Use it even when BMad is not mentioned, since deciding not to use it is a valid and common outcome. Do NOT use this for understanding an existing codebase with no change in mind (use repo-recon) or for evaluating code that already exists (use java-code-review).
---

# BMad Intake

A triage gate that runs before the BMad Method, not a reimplementation of it.

BMad already right-sizes work once you are inside it: it routes among Quick Flow, BMad Method, and Enterprise tracks and escalates on its own when a request outgrows the track it started in. What it does not decide is whether to enter at all. A one-line null check does not need a PRD, and a disagreement about scope is not solved by generating documents. This skill makes that call, prepares good inputs when the answer is yes, and then gets out of the way.

## Core principles

**Discover, never recall.** BMad's command surface has changed across releases and differs between host tools — the same workflow appears as `/bmad-bmm-create-prd` in one version and `bmad pm create-prd` in another. Run `scripts/detect_bmad.sh` and use only what it reports. Inventing a plausible command wastes a session and teaches the user to distrust the skill. If discovery cannot find something, say so plainly.

**The default is no.** Process has real cost — hours of planning, artifacts that need maintaining, and a team that has to agree to read them. Recommend BMad when the cost of being wrong exceeds the cost of the process, not because a structured option exists. Most day-to-day work should exit this skill at step two and go straight to implementation.

**Never impose process on a team that has not agreed to it.** BMad produces PRDs, architecture documents, epics, and story files. If the organization already runs Jira, Confluence, and its own ceremonies, these artifacts either duplicate or conflict with what exists. On shared work, generating them is a proposal about how the team should operate, and that is a conversation to have with people, not a decision to make inside a tool. Flag the collision rather than quietly creating a parallel system.

**Resume beats restart.** If discovery finds `bmm-workflow-status.yaml` or existing planning artifacts, work is already underway. Read the state, tell the user where things stand, and continue from there. Starting fresh silently discards decisions someone already made.

**Brownfield needs grounding.** BMad's planning quality depends entirely on the accuracy of what it is told about the existing system. On an unfamiliar codebase, guessed context produces confidently wrong architecture. This is where the skill earns its place — see Phase 3.

## Workflow

### Phase 0 — Discover the environment

Run `scripts/detect_bmad.sh` from the project. It reports the installation root, modules present, configuration, output folder, existing artifacts, in-flight workflow state, and the real invocation surface. It is read-only and safe on any project.

Read the output before forming any opinion. Three findings change everything downstream: whether BMad is installed at all, whether a workflow is already in progress, and what commands actually exist here.

If BMad is not installed, do not stop. Triage still runs — the answer may well be that this work does not need BMad. Only if triage concludes BMad is warranted does installation become the topic, and then it is a recommendation to the user, not something to run unprompted. Installation touches the project tree and requires Node, Python, and `uv`; on a managed work machine that is a question for whoever owns the machine.

### Phase 1 — Characterize the work

Understand the request before judging it. Establish:

- **What outcome is wanted**, in the user's terms, and whether it can be stated as a testable condition.
- **Greenfield or brownfield.** Brownfield is the common case and the harder one.
- **Blast radius** — one function, one module, several services, or a cross-cutting concern.
- **Reversibility** — schema migrations, public API changes, data model changes, and anything with a deployment or contract dependency are expensive to undo.
- **Requirement clarity** — is there a specification, or a sentence someone said in a meeting?
- **Who else is affected** — solo work, or work that other people's work depends on.

Ask about whatever is genuinely unclear, but ask once and in a batch. An intake gate that interrogates the user is worse than no gate.

### Phase 2 — Triage

Pick exactly one of four routes. `references/triage-rubric.md` has the decision criteria and worked examples; consult it rather than improvising, because consistency across invocations is the point of having a rubric.

**A. Straight to implementation.** Clear requirement, contained blast radius, cheap to reverse. Exit this skill and do the work. This should be the most common outcome.

**B. Reconnaissance first, then implement.** The requirement is clear but the code is not. Run `repo-recon` scoped to the affected area, then implement with that context. No BMad.

**C. Recon, then BMad.** The work is large, ambiguous, architecturally consequential, or spans multiple work items. Proceed to Phase 3. On brownfield, recon is not optional here — it is the input.

**D. Escalate to a person.** The blocker is not technical. Unclear priority, contested scope, a missing decision that belongs to a product owner, or a requirement that appears to conflict with something already built. Say so directly and name the question to ask. Running a planning workflow to avoid an awkward conversation produces expensive documents that resolve nothing.

State the route and the reasoning in one or two sentences, then act. If the user disagrees, take their call — they have context the rubric does not.

### Phase 3 — Prime brownfield context

Only on route C, and only when existing code is involved.

The goal is a short, factual context pack that BMad's planning stages can consume instead of asking the user to describe their own system from memory. Assemble:

1. **An architecture brief.** Reuse an existing `ARCHITECTURE_BRIEF.md` if one is present and still current; otherwise run `repo-recon`. For a scoped change, run it scoped — a whole-repo brief for a single-module change is wasted effort.
2. **The specific seam.** Which modules, classes, endpoints, and tables the change actually touches, with paths. This is the difference between architecture advice that fits and architecture advice that reads like a greenfield tutorial.
3. **Binding constraints.** Language version ceiling, framework version, established conventions, how schema migrations are handled, what CI gates a merge, and the test posture in the affected area. These are the things a plan must not violate.
4. **Prior art.** Existing patterns in the codebase that the change should follow rather than reinvent, and any half-finished migration it will land in the middle of.
5. **Known constraints from the user** — deadlines, dependencies, things that must not change.

Write this to the discovered output folder alongside BMad's other planning artifacts, so the workflow and the human can both find it. Keep it factual and cite paths; this document's value is that it is verified rather than remembered.

### Phase 4 — Hand off

Invoke the appropriate entry point **from the list discovery produced**. If BMad exposes a universal entry point or help skill in this installation, prefer it — it knows the current lifecycle better than any hardcoded route.

Tell the user, briefly: which route was chosen, what context was prepared and where it lives, and what BMad will ask of them next. Planning workflows are interactive by design and expect real participation; a user who thinks they can walk away will get a poor result.

Then stop. Do not narrate BMad's internal steps or attempt to run its lifecycle manually.

### Phase 5 — Record the decision

Append a short entry to a triage log in the output folder: the date, the request, the route chosen, and the one-line reason. Two purposes. It builds a record of how this codebase's work actually gets sized, which is useful evidence when someone asks whether the process is worth it. And on a shared repo it shows teammates that skipping the process was a deliberate call rather than an oversight.

Keep it to a couple of lines. A triage log that becomes a chore stops being written.

## When this skill should say less

If the user has already decided — "kick off a PRD for the billing rework" — do not re-litigate the decision. Run discovery, confirm BMad is present and functional, prime context if it is brownfield, and hand off. Offer a one-line observation if the choice looks mismatched to the work, then defer. Triage is a service, not a checkpoint the user has to clear.
