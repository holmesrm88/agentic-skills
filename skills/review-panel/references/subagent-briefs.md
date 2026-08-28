# Subagent Briefs

Four reviewers, one packet each, no cross-talk. Each brief is what that subagent is told; none of them is told what the others found.

## Shared preamble

Give every subagent the same framing:

> You are reviewing a completed story's diff. `changed-lines.txt` lists the exact
> line ranges this story touched. Report findings both inside and outside those
> ranges, but set `in_scope` accurately — the orchestrator uses it to decide
> whether something becomes this story's work or a separate ticket.
>
> Match the conventions already present in this codebase. A consistent pattern you
> would not have chosen is not a finding unless it causes the specific problem you
> are reporting.
>
> Report only what you can point at. If you suspect something but cannot verify it
> from the packet, say so with `confidence: low` and name what you would need to
> check. Do not guess.
>
> Return findings in the schema in the finding-triage reference. Return an empty
> list if you find nothing — a clean report is a legitimate outcome and inventing
> findings to appear thorough corrupts the panel's signal.

## 1. Security

Focus strictly on exploitable conditions, not general hardening opinions.

- Injection — SQL, JPQL, command, LDAP, expression language. Any query or command assembled from input.
- Path traversal — user input reaching file paths without canonicalization.
- Deserialization — native Java deserialization of untrusted data, Jackson polymorphic typing, unsafe YAML constructors.
- XXE — XML parsers without external entity processing disabled.
- Authorization — new endpoints without an access check; object-level checks missing (authenticated but not authorized for *that* record).
- Secrets — credentials, tokens, keys in source, config, or logs. Also full request or entity dumps in log statements.
- Crypto — weak algorithms, ECB mode, static or reused IVs, `Random` where `SecureRandom` is required, non-constant-time secret comparison, general-purpose digests used for password hashing.
- SSRF — user-supplied URLs fetched server-side without an allowlist.
- Disabled TLS verification, usually left over from local debugging.

For every finding, state the attack: what an attacker controls, what they achieve. A security finding without an exploit path is a design opinion and should be reported as such or not at all.

Severity here is calibrated differently. Anything with a realistic exploit path against untrusted input is **blocking**, regardless of how small the diff is.

## 2. Ghost tests

The distinctive reviewer. Its question is not "are there tests" but "would these tests fail if the code were wrong?"

Examine every test in `changed-tests.txt`:

- **Tautologies** — assertions that cannot fail. `assertThat(x).isEqualTo(x)`, asserting on a value just assigned, asserting a mock returns what it was stubbed to return.
- **No meaningful assertion** — tests that only check no exception was thrown, or assert only on mock interactions rather than outcomes.
- **Mock-only verification** — `verify(repo).save(any())` with no assertion about resulting state. This confirms a call happened, not that the behavior is right.
- **Over-mocking** — the class under test partially mocked, or value objects mocked. These pass regardless of implementation.
- **Would it survive deletion?** The core question: if the production code this test covers were deleted or stubbed to return a constant, would the test fail? Reason it through explicitly and say so.
- **Coverage without verification** — a test that executes a code path but asserts nothing about it. Inflates coverage numbers, catches nothing.
- **Missing negative cases** — only the happy path tested; no assertion on error handling, empty input, or boundaries the feature's acceptance criteria imply.
- **Flake sources** — `Thread.sleep`, wall-clock dependence, execution-order dependence, shared mutable static state.

A ghost test is more dangerous than a missing test, because it reports safety that does not exist. Treat a confirmed tautology or assertion-free test on new behavior as **blocking** — the story's acceptance criteria are not actually verified.

## 3. Clean code

The reviewer most likely to generate noise, so it gets the tightest constraints.

- **Convention adherence** — measured against the surrounding code. Read neighboring files to establish what the convention is before judging a deviation.
- **Duplication introduced by this story** — copy-pasted blocks, repeated logic that already exists elsewhere in the codebase.
- **Dead code** — unused parameters, unreachable branches, methods nothing calls, commented-out code.
- **Naming** — only where a name is actively misleading about what something does. Not where a different name would be marginally nicer.
- **Method and class size** — judged by responsibility count, not line count.
- **Structure** — logic in the wrong layer, a controller doing persistence work, business rules in a mapper.

Explicitly do **not** report:

- Anything a formatter or existing linter owns.
- Preference dressed as principle. If you cannot name a cost, it is not a finding.
- Pre-existing patterns used consistently, unless this story made them worse.
- Suggestions to adopt a pattern the codebase does not use.

Cap at ten findings. If there are more than ten, the most important ten are what matters and the rest is noise.

## 4. Correctness

Apply the `java-code-review` checklist to the full diff — correctness, null and Optional handling, resource management, concurrency, exceptions, collections and equality, API design, streams, persistence and transactions, and performance where there is a plausible path to real impact.

This reviewer overlaps the others by design. Overlap is how corroboration gets measured; the orchestrator deduplicates. Do not withhold a finding because another reviewer might also catch it.

Additionally, verify the diff against the story's stated acceptance criteria: is each criterion actually implemented, and is each one actually tested? A criterion with no corresponding assertion is a finding — report it as **blocking**, since the story is not done.

## Isolation rules

Enforced by the orchestrator, not the subagents:

1. Identical packet to all four. No reviewer gets extra context.
2. No reviewer sees another's output, partial results, or even that the others exist.
3. No shared scratch directory. Each writes only its own findings.
4. Parallel execution. Sequencing creates ordering effects even without shared output.
5. On round 2, all four get the previous round's findings — the same set, so isolation between reviewers is preserved while avoiding re-litigation of settled items.
