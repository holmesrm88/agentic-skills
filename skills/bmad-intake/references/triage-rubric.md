# Triage Rubric

How to choose among the four routes. Read this during Phase 2.

The rubric exists so the same request gets the same answer twice. Deviate when the situation genuinely warrants it, but say that you are deviating and why.

## Contents
- The six signals
- Scoring
- Route definitions
- Worked examples
- Overrides
- Common mistakes

## The six signals

Score each from the characterization in Phase 1. Assign the higher value when torn — the cost of a slightly oversized process is hours, while the cost of an undersized one is rework.

**1. Requirement clarity**
- 0 — Acceptance criteria are already stated, or statable in one sentence.
- 1 — The goal is clear but the edges are not; a few decisions remain.
- 2 — Genuine ambiguity about what "done" means, or stakeholders would not agree on it.

**2. Blast radius**
- 0 — One function, class, or file.
- 1 — One module or a coherent feature area.
- 2 — Multiple modules, services, or teams; a cross-cutting concern.

**3. Reversibility**
- 0 — A revert fixes it entirely.
- 1 — Awkward to undo but contained.
- 2 — Schema migration, public API or contract change, data model change, or anything with production data or external consumers downstream.

**4. Codebase familiarity**
- 0 — You know this code.
- 1 — You know the project, not this corner.
- 2 — Unfamiliar code, inherited service, or no one currently on the team wrote it.

**5. Duration**
- 0 — Hours.
- 1 — A few days.
- 2 — Weeks, or naturally splits into multiple work items.

**6. Coordination**
- 0 — Solo, no one waiting.
- 1 — One or two others touching adjacent code.
- 2 — Multiple people or agents working in parallel on the same system, or work others are blocked on.

## Scoring

**Total 0–2** → Route A, straight to implementation.
**Total 3–5** → Route A or B; familiarity (signal 4) decides. A 2 there means B.
**Total 6+** → Route C, BMad planning.

**Any single 2 on reversibility or coordination pulls up at least one route,** regardless of total. Irreversible changes and parallel work are where insufficient planning gets expensive, and both are cheap to plan relative to what they cost to get wrong.

**Route D is orthogonal to the score.** It applies whenever the actual blocker is a decision no amount of technical work resolves. Check for it first — a high score plus an unresolved product question is still Route D, and running planning workflows over a contested requirement produces a well-structured document about the wrong thing.

## Route definitions

**A — Straight to implementation.** Do the work. No artifacts, no planning session. Most work lands here and that is correct.

**B — Recon, then implement.** Run `repo-recon` scoped to the affected area first, then build. The requirement is not in question; the code is. Typically a few minutes of orientation that saves an hour of wrong assumptions.

**C — Recon, then BMad.** Proceed to Phase 3 of the skill, assemble the context pack, hand off to the installed BMad entry point. Let BMad pick its own track from there — it will route among Quick Flow, BMad Method, and Enterprise on its own, and it escalates when a request outgrows the track it started in. Do not attempt to pre-select the track; that decision belongs to BMad and it has more signal than this rubric does once it is inside its own discovery.

**D — Escalate.** Name the specific question and who likely owns it. Then stop. If the user wants to proceed anyway, do so, but note what remains unresolved so it does not surface as a surprise later.

## Worked examples

**"The vets endpoint returns all records; add pagination."**
Clarity 0, blast radius 1, reversibility 1 (an API shape change, but additive if the parameters are optional), familiarity 1, duration 0, coordination 0. Total 3, familiarity is not 2. **Route A.** If existing consumers depend on the unpaginated response, reversibility becomes 2 and this moves to B, with the compatibility question raised explicitly.

**"We're moving from a single-tenant to a multi-tenant data model."**
Clarity 2, blast radius 2, reversibility 2, familiarity 1, duration 2, coordination 2. Total 11. **Route C**, unambiguously. Every entity, every query, and the entire authorization model are implicated. This is exactly the work BMad is for.

**"Fix the NPE in OrderValidator line 88."**
All zeros or near. **Route A.** Running any process here is theater.

**"Add SSO. Marketing says customers want it."**
Clarity 2, blast radius 2, reversibility 2, coordination 2 — but which identity provider, which protocol, do existing password accounts migrate, and who is asking? **Route D first.** Those are product and security decisions with cost implications, and no planning workflow can invent the answers. Once they exist, this becomes a clear Route C.

**"Refactor the payment module — I've never seen this code and it's from an acquisition."**
Clarity 1, blast radius 2, reversibility 2, familiarity 2, duration 2, coordination 1. Total 10. **Route C**, and the recon phase is the important part. Planning against a system nobody understands produces plausible architecture that does not survive contact with the code. Recon first, then plan.

**"Three of us are adding endpoints to the same controller this sprint."**
Individually each endpoint might score 2. But coordination is 2, and parallel work on shared files is precisely where conflicting decisions surface late. **Route C** on the strength of the coordination signal alone — one agreed shape up front prevents three incompatible ones.

## Overrides

**The user has already decided.** Their call. Confirm the environment, prime context, hand off. Offer at most one sentence if the fit looks wrong.

**BMad is not installed and the route is C.** Say that the work warrants structured planning, and that BMad would be one way to get it. Do not install anything. On a managed machine that is not your decision, and the prerequisites are non-trivial.

**The team does not use BMad.** Then producing its artifacts creates a parallel process. Say so. The right move is usually to do the *thinking* BMad prescribes and record it in whatever system the team actually reads.

**Exploratory or throwaway work.** Spikes, prototypes, and proof-of-concept code that will be deleted score low on reversibility no matter how large they are, because the whole thing is reversible. Route A, and note that the resulting code should not quietly become production.

## Common mistakes

- **Scoring the ideal version of the request instead of the request.** "Add a health endpoint" is not "design an observability strategy," even though the second is more interesting.
- **Treating unfamiliarity as complexity.** Unfamiliar simple code is Route B, not C. Recon is cheap; planning is not.
- **Letting a high score override Route D.** Complexity and ambiguity are not the same thing. An ambiguous requirement gets worse under planning, not better, because the process lends it false precision.
- **Recommending process to appear thorough.** The score exists to be honest, including when honest means "just write the code."
