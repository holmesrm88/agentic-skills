---
name: java-code-review
description: Review Java code against a senior-engineer checklist covering correctness, resource handling, concurrency, exception discipline, API design, persistence, and security, and return prioritized findings with file locations and concrete fixes. Use this whenever the user asks for review, critique, feedback, or a second opinion on Java or Kotlin code — a pull request, a diff, a single class, a method, or "does this look right?" — and also proactively before the user submits Java code they have just written or asks whether it is ready to ship. Use it even when the request is casual ("take a look at this", "anything wrong here?"). This is for evaluating specific code that already exists, NOT for mapping an unfamiliar codebase (use repo-recon) and NOT for writing new code from scratch.
---

# Java Code Review

Review Java code the way a strong senior engineer does: find the things that will actually cause an incident, explain why they matter, and stay out of the way on everything else.

## What good review looks like

**Rank ruthlessly.** A review that lists thirty items ranked equally is a review that gets skimmed and ignored. Lead with what will break in production. Most reviews should surface two to five things that matter, plus a short tail of smaller notes.

**Match the codebase before improving it.** Existing conventions win over personal preference, even where the convention is not what you would have chosen. If the file uses field injection throughout, a lone constructor-injection suggestion creates inconsistency, which is its own cost. Flag a convention only when it is actively causing the bug in front of you, and then flag it as a codebase-level observation rather than a line comment on one unlucky author.

**Say why, not just what.** "Use try-with-resources" teaches nothing. "This stream is not closed on the exception path, so a request that throws leaks a file handle — under load this exhausts the descriptor limit and the service stops accepting connections" teaches the reader to catch it themselves next time. The failure mode is the payload.

**Distinguish what you know from what you suspect.** With a diff you often cannot see the caller, the transaction boundary, or the threading model. Say "if this is called from multiple threads, this is a race" rather than asserting it is one. Confident wrongness is the fastest way for a reviewer to lose standing.

**Acknowledge what is good, briefly and specifically.** One sentence naming an actual good decision — not generic praise — makes the critical findings land as collaboration rather than gatekeeping. Skip it if there is nothing specific to say; hollow praise is worse than none.

## Severity ladder

Assign exactly one level per finding:

- **Blocking** — will cause data loss, corruption, a security breach, or an outage. Correctness bugs, injection vulnerabilities, resource leaks on hot paths, broken concurrency.
- **Should fix** — real bug or real risk, but bounded. Missing edge case, swallowed exception, N+1 query, absent test for new branching logic.
- **Consider** — design and maintainability. Would improve the code; reasonable people could ship without it.
- **Nit** — style and naming. Cap these at five per review and mark them clearly as optional. If a formatter or linter would catch it, it usually does not belong in a human review at all.

When uncertain between two levels, state the condition that decides it: "Blocking if this endpoint is public; Consider if it is internal-only."

## Workflow

1. **Establish context.** What is the change trying to do? Is this a diff or a whole file? What Java version, what frameworks? If a `pom.xml` or `build.gradle` is available, check the language level — suggesting records to a Java 8 project wastes everyone's time. Ask if the intent is genuinely unclear; guessing produces reviews that argue against the wrong thing.

2. **Read for intent first.** Understand what the code is meant to do before judging how it does it. Many apparent bugs are deliberate, and the ones that are not become obvious once you know the goal.

3. **Pass the checklist.** Work through `references/checklist.md`, which covers the failure modes by category with the specific Java shapes they take. Do not paste the checklist into your output — use it to look, then report only what you actually found.

4. **Trace the paths that are easy to miss.** Explicitly walk the exception path, the empty-input path, the null path, and the concurrent path. These are where real defects hide, because the happy path is what the author tested.

5. **Check the tests.** New branching logic without a test covering it is a finding. So is a test that asserts nothing meaningful, or one so coupled to implementation that any refactor breaks it. Absent tests are as reviewable as present ones.

6. **Write the review** in the format below.

## Output format

```markdown
## Review: [what was reviewed]
[One or two sentences: what the change does and the overall verdict.]

### Blocking
**[Short title]** · `path/File.java:42`
[What is wrong, the concrete failure mode, and the fix. Include a code snippet
only when it clarifies faster than prose.]

### Should fix
[Same structure.]

### Consider
[Same structure. Brief.]

### Nits
- `path/File.java:88` — [one line each]

### What's solid
[One sentence, specific, or omit entirely.]
```

Drop any section with no findings rather than writing "None." — an empty heading is noise. If nothing at all is wrong, say so plainly and name what made the code good; a clean review is a legitimate outcome and inventing findings to seem thorough is a real failure mode.

## Calibration

**Do not flag:**
- Formatting a formatter owns.
- Personal preference presented as a rule ("I'd extract this" with no cost named).
- Patterns used consistently across the codebase, unless they cause the specific bug at hand.
- Missing tests for pure refactors with existing coverage.
- Theoretical performance concerns with no evidence of a hot path. Nanoseconds in a method called once per request are not a finding.

**Always flag:**
- Any user-controlled input reaching SQL, a shell, a file path, a deserializer, or a URL.
- Silently swallowed exceptions, including empty catch blocks and `catch` blocks that only log at debug level.
- Resources acquired without guaranteed release.
- Mutable state shared across threads without a synchronization story.
- Credentials, tokens, or PII in source or logs.
- `equals` overridden without `hashCode`, or either one inconsistent with the fields used in a collection.

## Adapting to context

- **Pre-merge PR review** — the default. Full checklist, prioritized.
- **"Is this ready to ship?"** — weight Blocking and Should fix; compress the rest to a line.
- **Learning-oriented review** — expand the *why* on each finding and link the general principle. More teaching, same findings.
- **Legacy code the author inherited** — separate "problems this change introduces" from "problems this change inherits." Holding someone responsible for pre-existing debt they merely touched is how review turns adversarial.
- **New codebase, first weeks** — lean toward questions over assertions where a local convention might explain the code. "Is there a reason this uses X rather than Y?" surfaces the same issue and stays open to the answer being good.
