# Estimating

How to produce a number, and when not to.

## The unit

On this team a point is roughly a day, with quarter increments: 0.25, 0.5, 0.75, 1, and up.

Be honest about what that means. Points-as-days is an existing team norm, but it has a built-in ambiguity: a day *for whom*? The same story is one day for someone who wrote the module and three for someone seeing it first. Estimate for a notional competent team member familiar with the codebase but not with this specific story, and say so when it matters — a story deep in an unfamiliar subsystem should carry that caveat rather than a falsely precise number.

Quarter points imply precision that rarely exists. Use 0.25 and 0.75 only when the reference class genuinely supports them. Reaching for 1.75 to seem careful is false accuracy.

## The method

Reference-class forecasting. Find completed stories that resemble this one, look at what they actually took, adjust for the differences.

1. **Find two or three analogues.** Same component or area, similar kind of work, comparable unknowns. The calibration profile supplies exemplars per point value.
2. **Use actual duration, not assigned points.** If the analogues were pointed 2 and took 3–4 days, the reference class is 3–4 days.
3. **Adjust for specific differences**, and name them. "Similar to PROJ-1180 but also touches the notification path, so a little larger."
4. **State the references in the output.** An estimate whose comparisons are visible can be corrected by someone who knows the code better.

## What raises an estimate

- **Unfamiliar area** — no team history, or the last person who touched it has left.
- **Cross-cutting change** — multiple modules, or both repos. Two repos means two PRs, two reviews, two deploys; the coordination cost is real and consistently underestimated.
- **Schema or data migration** — irreversible, needs care, usually needs a rollback plan.
- **External dependency** — a third-party API, another team's work, an unreleased change.
- **Unclear acceptance criteria** — ambiguity resolves into scope more often than out of it.
- **No existing test coverage** in the affected area — the work includes building the safety net.
- **Investigation component** — anything phrased as "look into", "figure out", or "determine". Unbounded by construction; consider recommending a timeboxed spike instead of a point value.

## What lowers an estimate

- **A close, recent analogue** the team has done before.
- **Well-specified acceptance criteria** with concrete examples.
- **Isolated change** — one module, existing patterns to follow.
- **Existing test coverage** in the area.
- **Pure configuration or content** with no logic change.

## Signals that are not size

Easy to mistake for complexity:

- **A long description** often means a thorough writer, not a large story. Sometimes it means an unsplit epic — read it rather than counting it.
- **High priority** is urgency, not effort.
- **Many comments** usually means confusion, which suggests unresolved questions rather than a bigger number. Surface the questions.
- **An intimidating component name** means unfamiliar, which is a real factor, but check the reference class before inflating.

## When not to give a number

Some stories should come back without an estimate, and saying so is the useful output.

**No acceptance criteria at all.** There is nothing to size. Ask what "done" means.

**Unbounded investigation.** "Find out why the import is slow" has no size until someone looks. Recommend a timeboxed spike.

**Obviously multiple stories.** If it contains "and" between unrelated pieces of work, recommend the split and estimate the pieces if they are clear.

**No reference class.** Genuinely novel work — a new integration, an unfamiliar technology — has nothing to compare against. Say so, give a range if one is defensible, and mark confidence low. A range with honest uncertainty beats a point value with false precision.

**A blocking unanswered question.** If the answer changes the estimate by more than a factor of two, the question has to be answered first. Ask it and hold the number.

## Splitting

Recommend a split when a story exceeds roughly three days, contains unrelated pieces of work, spans both repos in separable ways, or has one part that is clear and another that is not — the clear part can proceed while the rest is refined.

Propose concrete splits, not the principle. "Split into: (1) add the tenant column and migration, (2) filter queries by tenant, (3) update the UI" is actionable. "This should be split" is not.

## Calibrating against the team's own bias

Where calibration shows a point value is systematically under-pointed, estimate against what those stories actually took rather than perpetuating the pattern.

Say it explicitly: "the closest matches were pointed 2 but took 3–4 days, so I've estimated 3." That gives the team the chance to either accept the correction or explain why the historical stories were unusual. Silently inflating estimates to compensate would produce the right numbers with no visible reasoning, and the team would learn nothing.
