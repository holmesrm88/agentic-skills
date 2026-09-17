---
name: ghost-test-detector
description: Evaluate whether tests actually verify behaviour, rather than just existing. Runs a deterministic scan for tests that cannot fail — no assertions, tautologies, mock-only verification, Playwright assertions missing await — then a semantic review comparing the tests against the code they cover and the story's acceptance criteria, checking for happy-path-only coverage, missing negative cases, and untested edge cases. Use before committing test changes, when reviewing a PR's tests, or whenever someone asks whether tests are any good, whether they're ghost tests, whether they cover edge cases, or whether they test the right thing. Supports Java (JUnit 5, Mockito, AssertJ) and Playwright. Works standalone.
---

# Ghost Test Detector

A ghost test is one that cannot fail, or that passes regardless of whether the code is correct. It is worse than a missing test, because it reports safety that does not exist — in coverage numbers, in review, and in everyone's confidence.

This skill answers three questions in increasing order of difficulty:

1. **Can these tests fail?** — deterministic, a script answers it.
2. **Do they exercise the code that changed?** — needs reading the diff.
3. **Do they verify what was asked for, including edge cases?** — needs the acceptance criteria and judgement.

## Two passes

### Pass 1 — Static scan

```bash
python3 scripts/static_scan.py --staged        # or pass file paths
```

Deterministic pattern matching. Milliseconds, no model call. Catches tests with no assertion, tautologies, mock-only verification, disabled tests, flake sources, and — for Playwright — assertions missing `await`, which is the highest-frequency ghost in that framework because the matcher returns an unchecked promise and the test always passes.

Run this first. It is cheap, and its findings are facts rather than opinions. Everything it reports is worth fixing before spending attention on the semantic pass.

Exit 1 means findings. Exit 0 means the blatant cases are absent — **not** that the tests are good.

### Pass 2 — Semantic review

This is the part a script cannot do, and the reason this is a skill.

**Gather three things:**

1. **The staged test diff** — `git diff --cached` on test files.
2. **The production code it covers** — the staged non-test changes, and the existing code those tests exercise.
3. **The acceptance criteria** — run `scripts/get_story_context.sh` to resolve the story key from an explicit argument, cache, branch name, or PR. Then fetch the criteria (`acli jira workitem view KEY --json`, or whatever the project uses).

If no story key is found, **say so and continue in reduced mode.** You can still evaluate whether the tests exercise the changed code and could fail. You cannot evaluate whether they cover what was asked for. State which question you answered; implying the fuller check happened is worse than the reduced check.

**Then evaluate each test:**

**Would it fail if the code were wrong?** The central question. Mentally delete or stub the production code the test covers — return a constant, remove the branch, invert the condition — and ask whether the assertion would still pass. Reason it through explicitly rather than asserting a conclusion. If it would still pass, it is a ghost regardless of how it looks.

**Does it assert the outcome, or the mechanism?** `verify(repo).save(any())` confirms a call happened. It says nothing about what was saved or what the caller received. Tests coupled to mechanism break on every refactor and catch no bugs — the worst combination.

**Does it exercise the code that changed?** A test can be perfectly good and irrelevant to this diff. Map each changed production method to the tests that reach it. Changed code with no test reaching it is a finding even when the commit contains test changes.

**Are the acceptance criteria covered?** Each criterion should map to at least one assertion. A criterion with no corresponding assertion means the story is not actually verified — report it as high severity, since that is the definition of done going unchecked.

**Are the negative cases there?** Almost every criterion implies one. "Rejects invalid input" needs a test proving valid input is *not* rejected and invalid input *is*. A filter needs proof it excludes as well as includes. An authorization check needs a denial case. Positive-only testing is the most common real weakness and the static scan cannot see it.

**Which edge cases are missing?** Enumerate against what the code actually does: null and empty, boundary values on any comparison, zero and negative numbers, collections of size 0 and 1, duplicates, unicode and very long strings, concurrent access where relevant, and the error path of anything that can throw. Be specific about which ones matter for this change rather than listing all of them — a generic checklist is noise.

`references/semantic-review.md` covers what to look for per framework.

## Output

Lead with the verdict. Then:

**Ghosts** — tests that cannot fail, with the reasoning for why not.
**Gaps** — changed behaviour with no test reaching it, and acceptance criteria with no assertion.
**Weak** — tests that verify mechanism rather than outcome, or cover only the happy path.
**Missing edge cases** — specific, with why each one matters here.

For each, name the file and test, say what is wrong, and give the concrete fix. Where the conclusion depends on something you could not see — the caller, the transaction boundary, existing tests elsewhere — say so rather than asserting.

**A clean result is a legitimate outcome.** If the tests are good, say so and name what makes them good. Inventing findings to appear thorough trains people to ignore the output.

## What this cannot do

Be direct about the ceiling, because the failure mode is a team believing their code is verified when it is not.

- It reasons about whether a test *would* fail. It does not prove it. Only mutation testing does that — see `references/ci-integration.md` for PIT on Java.
- It cannot judge tests against requirements nobody wrote down.
- It evaluates unit and E2E test quality. It says nothing about integration seams, concurrency, performance under load, or a correct implementation of a wrong requirement. Those bugs arrive through other doors.

Tests being adequate is not the same as code being correct, and this skill only addresses the first.

## Where it runs

**Before committing** — the primary use. Static scan, then semantic review of the staged diff.

**On every PR** — the same skill runs in CI via `anthropics/claude-code-action`, which covers commits made without invoking it locally. See `references/ci-integration.md`.

**On demand** — reviewing someone else's tests, or auditing an existing suite.
