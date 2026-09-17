# ghost-test-detector

Checks whether tests actually verify behaviour, rather than merely existing.

A ghost test is one that cannot fail, or that passes whether or not the code is correct. It is worse than a missing test, because it reports safety that does not exist — in the coverage number, in review, and in everyone's confidence.

Supports **Java** (JUnit 5, Mockito, AssertJ) and **Playwright**.

---

## What it does

**Pass 1 — static scan.** Deterministic pattern matching, milliseconds, no model call.

```bash
python3 scripts/static_scan.py --staged
```

Catches: tests with no assertion, tautologies (`assertTrue(true)`, `assertEquals(x, x)`), mock-only verification, disabled and skipped tests, flake sources (`Thread.sleep`, `waitForTimeout`, unseeded `Random`), swallowed exceptions, and two silent killers:

- **Java: a method with assertions but no `@Test` annotation.** JUnit never runs it. The code looks correct, sits in the right file, has real assertions, and protects nothing. Invisible in review. Methods called by other tests are recognised as shared helpers and not flagged; classes extending `TestCase` keep JUnit 3's `testFoo()` name convention.
- **Playwright: an assertion missing `await`.** The matcher returns a promise nobody checks, so the test always passes. The line reads as completely correct.

**Pass 2 — semantic review.** Claude reads the test diff against the production code it covers and the story's acceptance criteria, then asks what a script cannot:

- Would this fail if the code were wrong? (mutation thought experiment)
- Does it assert the outcome, or just the mechanism?
- Does it exercise the code that actually changed?
- Does every acceptance criterion have an assertion behind it?
- Are the negative cases there, or is it happy-path only?
- Which edge cases are missing, and why do they matter here?

---

## Honest scope

Scored against "ensure code is well written and doesn't introduce bugs":

| Question | Coverage |
|---|---|
| Did they write tests? | high |
| Are they ghost tests? | high — static catches blatant, semantic catches subtle |
| Do they test what we expect? | medium — only as good as the acceptance criteria |
| Do they cover edge cases? | medium — good at generic cases, blind to domain-specific ones |
| Does it prevent bugs? | **low** |

That last row is the important one. Bugs arrive through doors this tool does not watch: a correct implementation of a wrong requirement, integration seams, concurrency, performance under real data volumes, config drift between environments. No test-quality check catches any of those.

**Claim this catches the tests we forgot and the tests that test nothing.** Do not claim it ensures correctness — that gets falsified the first time a bug ships, and then nobody trusts any of it.

The tool also *reasons* about whether a test would fail; it does not prove it. Only mutation testing proves it.

---

## Where it runs

| Trigger | Covers | Notes |
|---|---|---|
| Before committing | Commits where it is invoked | Fast; static + semantic on staged diff |
| On every PR | **Everything**, including hand-written commits | `anthropics/claude-code-action@v1` runs the same skill |
| Mutation testing in CI | Ground truth | PIT for Java; minutes to hours |

The CI path matters most: it is the only layer that runs regardless of who committed or how. See `references/ci-integration.md` for the workflow file.

---

## Acceptance criteria

The semantic pass is much stronger with them. `scripts/get_story_context.sh` resolves the story key from, in order: an explicit argument, a cached value, the branch name, the PR body.

```bash
scripts/get_story_context.sh PROJ-1234     # explicit, then cached for later runs
scripts/get_story_context.sh               # resolve from cache, branch, or PR
```

**With no key it degrades honestly.** It still checks whether the tests exercise the changed code and could fail; it cannot check whether they cover what was asked for — and it says which question it answered rather than implying both.

To make the full check routine, require a story key on every PR. Five lines of workflow, in `references/ci-integration.md`.

---

## Files

| File | Role |
|---|---|
| `SKILL.md` | The semantic review — what Claude reads |
| `scripts/static_scan.py` | Deterministic scan. `--staged`, file paths, or `--json` |
| `scripts/get_story_context.sh` | Resolves the story key for acceptance criteria |
| `references/semantic-review.md` | Per-framework guidance for the semantic pass |
| `references/ci-integration.md` | PR workflow, story-key enforcement, mutation testing |

Standalone. No dependency on any other skill.

---

## Tuning

The static scan is deliberately conservative — it reports only patterns that are close to unambiguous, because false positives are how these tools die. A few spurious findings and people stop reading the output, at which point the real findings are invisible too.

If it misfires, the patterns are at the top of `static_scan.py` in named groups (`JAVA_TAUTOLOGIES`, `PW_FLAKE`, and so on). Adding a framework means adding a pattern group and a `scan_*` function, not restructuring.

Known limits:

- Test blocks are found by brace matching, so unusual formatting can confuse block boundaries.
- Assertions inside helper methods the test calls are not followed; a test delegating all its assertions to a private helper may be reported as assertion-free.
- The `await` check covers Playwright's async matchers. A custom async matcher would need adding to `PW_ASYNC_MATCHERS`.
