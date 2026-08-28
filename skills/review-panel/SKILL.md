---
name: review-panel
description: Orchestrate a panel of isolated review subagents over a completed story's full diff, then triage their findings into new harness features, tickets, or inline fixes. Runs security, ghost-test, clean-code, and correctness reviewers in parallel with no cross-talk, deduplicates and ranks what they find, and presents one batch for human approval. Use when all features for a story are committed and the work is heading toward a PR — "run the panel", "review the story", "we're ready for PR", "check PROJ-1234 before I push". Do NOT use for reviewing a single file or a work-in-progress diff (use java-code-review directly) or for implementing features (use harness).
---

# Review Panel

A fan-out of independent reviewers over a finished story, joined into one ranked, deduplicated, human-approved list of findings — some of which become new work.

This runs once per story, after every feature is committed and before the PR exists. It is the last gate before code leaves your machine.

## Why isolation matters

The four reviewers see the same packet and none of them sees another's output. That is the entire source of signal quality.

Independent agreement is evidence. When three reviewers separately flag the same line, that is three observations. When one flags it and the others see that report first, that is one observation and two echoes — but it reads identically in the output, which makes it worse than useless. It looks like corroboration.

So: same input, parallel execution, no shared scratch space, no sequencing. Synthesis happens once, in the orchestrator, after everything has reported.

## Phase 0 — Preconditions

Refuse to run unless all of these hold. Each one is a case where the panel would review something other than what ships.

- **All features committed.** Read `.harness/features/`. Anything in `red`, `green`, or `blocked` means the story is not done. Report which and stop.
- **Working tree clean.** `collect_diff.sh` enforces this. A dirty tree means the reviewed diff is not the pushed diff.
- **Full gate passes.** Run `./init.sh full`. Reviewing code that does not build wastes four agent runs. An exit of `2` — gate invalid, zero tests executed — is a stop, not a pass.
- **Round cap not exceeded.** See Termination.

## Phase 1 — Assemble the packet

Run `scripts/collect_diff.sh`. It writes `.harness/reviews/packet/` containing the story diff against its merge base, the commit list, the changed-files list split into production and test, and — most importantly — `changed-lines.txt`, a map of the exact line ranges this story touched.

**That map defines scope.** A finding inside those ranges is about this story. A finding outside them is pre-existing code that the story merely sits near. Reviewers will surface both; the orchestrator uses the map to classify, so the distinction is a lookup rather than an argument.

Add to the packet, for every reviewer:

- The story's acceptance criteria and the feature files.
- The conventions governing the affected area — read from the code, not assumed.
- `baseline.txt`, so pre-existing test failures are not reported as regressions.
- The round number, and on round 2, the previous round's findings so the same issues are not re-litigated.

## Phase 2 — Fan out

Spawn four subagents in parallel. Each gets the identical packet and the brief from `references/subagent-briefs.md`:

1. **Security** — injection, secrets, authorization, crypto, deserialization, SSRF, path traversal.
2. **Ghost tests** — tests that cannot fail, assert nothing meaningful, or verify mocks rather than behavior.
3. **Clean code** — convention adherence, duplication, dead code, naming, structure. Measured against this codebase, not an ideal one.
4. **Correctness** — the `java-code-review` checklist applied to the full diff.

Each returns findings in the fixed schema in `references/finding-triage.md`. A fixed schema is what makes deduplication mechanical instead of interpretive.

If parallel subagents are unavailable in the current environment, say so rather than degrading to sequential runs in one context. Sequential runs share context, which destroys the independence the panel exists for. Running the four checks as four separate manual invocations is an acceptable fallback; pretending one context is four reviewers is not.

## Phase 3 — Join, deduplicate, corroborate

Merge all findings. Deduplicate on file, approximate line, and issue class — not on wording, since four agents will describe the same problem four ways.

For each deduplicated finding, record how many reviewers independently raised it. **Report that count.** Three-of-four independent agreement on a medium-severity finding often deserves more attention than a lone high-severity call, and the human reading the batch should be able to see the difference.

Where reviewers genuinely disagree — one calls something a bug, another calls it intentional — surface the disagreement rather than picking a winner. That is real information about ambiguity in the code.

## Phase 4 — Classify

Apply the severity-by-scope matrix in `references/finding-triage.md`. Every finding gets exactly one disposition: new feature, ticket recommendation, inline fix, or drop.

One carve-out overrides the matrix: **a blocking security finding is escalated immediately, in or out of scope, regardless of round.** You do not sit on a discovered vulnerability because it fell outside the ticket boundary. Classify it as out-of-scope for the PR if that is accurate, and say clearly that it needs someone's attention today regardless.

## Phase 5 — Present the batch

One table, ranked by disposition then severity. For each row: title, file and line, severity, scope, how many reviewers flagged it, and the proposed disposition.

Below the table, the full detail for anything blocking or should-fix. Findings dispositioned as drop get one line each — visible, not argued.

Then stop and wait. The user approves the batch, amends individual dispositions, or rejects it. Nothing is written until they respond.

## Phase 6 — Route the approved batch

- **New features** — write feature files following the harness state contract, with `generated_by`, `round`, and `parent_feature` set so the provenance chain is visible. Number them after the existing features. Update the change-log to reflect the new work.
- **Ticket recommendations** — write `.harness/reviews/round-N-tickets.md` with enough detail to file each one. Do not create features from these; they are not this story's work.
- **Inline fixes** — nits worth fixing now. Make them, run the fast gate, and commit separately from feature work so the diff stays readable.
- **Dropped** — recorded in the round file and not mentioned again.

Write the full round record to `.harness/reviews/round-N.md`: raw findings, dedupe decisions, classifications, what the human changed, and final dispositions. This is the audit trail. It is also what tells you, three rounds later, whether the panel is finding real things or generating noise.

## Termination

The loop back into implementation does not naturally stop. Enforce these:

- **Round 1** — full panel. Any severity may spawn features.
- **Round 2** — panel re-runs on the remediation diff only. **Only blocking findings may spawn features.** Everything else becomes a ticket or a drop.
- **Round 3** — forbidden. Stop, report everything outstanding, and hand it to a human. If two remediation rounds have not converged, the problem is the plan or the requirements, and another cycle will not fix either.

Track the round in every generated feature file. If you find yourself writing `round: 3`, something upstream went wrong — say so instead of proceeding.

## What this skill will not do

It does not open the PR, push, or merge. It produces findings, work items, and an audit trail. Everything after that is a separate stage with its own human gate.
