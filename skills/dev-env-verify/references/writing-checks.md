# Writing Verification Checks

Turning acceptance criteria into checks you can actually execute, and deciding what counts as having verified something.

## The shape of a check

```
CHECK 3 — Rejecting an order with negative quantity
  Setup:    Logged in as a standard user. On the order form.
  Action:   Enter quantity -1, submit.
  Expect:   Inline error "Quantity must be at least 1". Order not created.
  Evidence: Screenshot of the error; GET /api/orders returns no new record.
```

Four parts, all required. A check missing `Expect` is exploration, not verification — it cannot fail, so running it proves nothing.

`Evidence` is what you will capture to show the result. Deciding it up front stops the after-the-fact rationalization where a screenshot of a page that happened to load becomes proof the feature works.

## Deriving checks from criteria

Acceptance criteria are written for humans and usually underspecify. Common gaps and how to close them:

**"The user can filter orders by status."** No stated expectation. What should the filtered list contain, and what should it exclude? A check needs both — that matching records appear *and* non-matching ones do not. Verifying only the positive half is how a filter that returns everything passes review.

**"Invalid input shows an error."** Which input, which error? Pick concrete values. If the criterion does not say, choose and state your choice in the report, so a reviewer can disagree with it.

**"Performance should be acceptable."** Not verifiable as written. Either find a number or mark it unverifiable and say why. Do not silently substitute "it felt fast."

**Criteria describing internals** — "the service calls the tenant resolver" — are not dev-environment checks. They are unit-test concerns. Verify the observable behavior instead, and note the mismatch.

## What to check beyond the happy path

The story states what should work. Verification should also confirm the change did not break its neighbors.

- **The stated criteria**, each one, individually.
- **The negative case** for each criterion that implies one — rejection actually rejects, the filter actually excludes, the permission check actually denies.
- **The adjacent path** the change most plausibly disturbed. If the story modified order creation, confirm order listing still works. One or two checks, not a regression suite.
- **The reported bug's reproduction steps**, if the story is a bug fix. The exact steps from the ticket, which should now produce the correct behavior.

Resist expanding beyond this. Verification is not exploratory testing, and a check list that takes an hour will not get run.

## Evidence standards

A claim without evidence is an opinion about a page you looked at.

| Check type | Acceptable evidence |
|---|---|
| UI state | Screenshot showing the specific element and its content |
| UI absence | Screenshot plus a statement of what was searched for |
| API behavior | Status code and the relevant response fields |
| Data change | The record before and after, or its absence |
| Error handling | The actual message text, quoted |
| Log behavior | The matching log line with its timestamp |

**"It worked" is not evidence.** Neither is a screenshot of a page that loaded — a page can load with the feature entirely absent.

For a failing check, capture more, not less: the error, the console, the network response, what you did immediately before. That is what turns a failure report into a diagnosis instead of a bug report you have to reproduce yourself.

## Blocked versus failed

Keep these separate and never collapse them.

- **Failed** — the check ran and the result was wrong. This is a finding about the code.
- **Blocked** — the check could not run. A login wall, missing test data, a page that would not load, a dependency unavailable. This is a finding about the environment or the setup.

Blocked checks are unverified. Do not infer them from neighbouring passes — "checks 1 and 3 passed so 2 probably does too" is how a broken feature ships. Report the block, say what it would take to unblock, and leave the criterion unverified.

## Writing it up

Order the report by outcome, not by check number: failures first, then blocked, then passes. The reader wants the verdict, then the problems.

For each failure, state the check, what happened instead, and the evidence. Add a diagnosis only if you have one — a guess dressed as a cause sends the fix in the wrong direction.

Keep passes brief. One line each is enough; the detail matters only when something is wrong.
