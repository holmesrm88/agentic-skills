# Comment Format

One comment per story, posted before grooming.

## Ordering

Questions and assumptions first. Estimate last.

The comment is visible before the team discusses, so the number will anchor the room if it leads. Putting it at the bottom, framed as a starting point, costs nothing and preserves the discussion that makes grooming worth holding. The moment where two people say different numbers is where the hidden complexity surfaces; a number already on the screen suppresses it.

## Template

```markdown
**Grooming prep** — generated before the session. Questions first; the estimate at
the bottom is a starting point for discussion, not a decision.

**Questions to resolve**
1. Should this apply to archived orders, or only active ones?
2. What should happen when the tenant header is missing — 400, or fall back to default?
3. Is the frontend change in scope, or a separate story?

**Assumptions made**
- Existing orders are backfilled with the default tenant rather than migrated per-customer.
- No change to the public API contract.
- Covered by existing integration tests; no new test infrastructure needed.

If any assumption is wrong, the estimate changes.

**Similar completed work**
- PROJ-1180 — tenant scoping on invoices — pointed 2, took 3.5 days
- PROJ-1244 — added org filter to reports — pointed 2, took 3 days

**Estimate: 3 points** · confidence: medium

Reasoning: closest matches were pointed 2 but consistently took 3–4 days. This one
also touches the query layer in two places rather than one. Questions 1 and 3 could
each move this — if the frontend is in scope, it is closer to 5 and should be split.
```

## Section notes

**Questions** — the primary output. Specific and answerable, not "needs clarification." If there are none, say the story is well-specified; that is worth knowing and worth encouraging.

**Assumptions** — every assumption is a question you answered yourself. Making them visible lets someone correct one cheaply, before the work starts. The line about assumptions changing the estimate is not boilerplate; it is the mechanism by which the estimate stays honest.

**Similar completed work** — cite actual keys with actual durations. This is what makes the estimate arguable. Someone who knows PROJ-1180 was unusual can say so, and that is a better conversation than disputing a number.

**Estimate** — the number, confidence, and reasoning in a few sentences. Name what would change it.

## Special cases

**Cannot estimate.** Replace the estimate section:

```markdown
**Estimate: not yet** — this cannot be sized until question 1 is answered. If the
migration is in scope it is roughly 5; if not, roughly 1.
```

That is a more useful contribution to grooming than a number split down the middle.

**Recommend splitting:**

```markdown
**Estimate: 5+ points, recommend splitting**

Suggested split:
1. Add tenant column and migration — 1
2. Filter order queries by tenant — 2
3. Update the order list UI — 2

Each is independently shippable and testable.
```

**Spike:**

```markdown
**Estimate: recommend a 1-day timeboxed spike**

"Investigate why imports are slow" has no size until someone looks. A day of
investigation should produce an estimate for the fix.
```

## Tone

Write as a colleague who did the prep, not as a system issuing a verdict. "I've assumed X — correct me if that is wrong" invites the response that makes the estimate better. "ESTIMATE: 3 POINTS" does not.

Keep it short enough to be read during grooming. If the comment is longer than the story description, it will be skimmed and the questions will be missed.

## Never write to the story points field

A comment is a suggestion. A populated field looks like a decision already made, and it will be ratified without discussion more often than it is corrected. The team sets the field during grooming; that act is part of what makes the estimate theirs.
