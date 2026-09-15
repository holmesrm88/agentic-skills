# CI Failure Taxonomy

Five categories, checked in this order. The order matters — each rules out work the later ones would waste.

## 1. Base-branch breakage

**Check this first, always.** Debugging your own diff against an already-broken pipeline is the single most expensive mistake available here.

**Signals**
- The same workflow is red on the default branch in recent runs.
- The failure is in code your diff does not touch.
- The failing test is unrelated to the change's subject.

**Evidence to cite:** the default-branch run history from the fetch script, plus the changed-files list showing no overlap.

**Action:** report it and stop. Do not fix main inside your PR — that entangles two changes and makes both harder to review. If it blocks you, that is a conversation with the team, not a commit.

---

## 2. Real failure

Your change broke something. The default case, and the one you want to be in — it is the only category with a clean fix.

**Signals**
- An assertion failure with a concrete expected-vs-actual.
- A compilation error in files the diff touched.
- The failing test covers behavior the change affects.
- Reproduces locally.

**Diagnose from the bottom of the cause chain.** In Java, follow `Caused by:` to the deepest frame — the top of a stack trace is usually a wrapper. The assertion detail line (`expected: <400> but was: <500>`) is typically more informative than the exception type.

**Action:** fix locally, run the local fast gate, push.

---

## 3. Flake

Nondeterminism. Real, common, and dangerous because the fix — re-run — is also the way real failures get ignored.

**Requires positive evidence.** Do not classify as flake because you cannot find the cause.

**Signals**
- Alternating pass/fail across runs on the same or similar commits.
- Timing language: `timeout`, `timed out`, `Connection refused`, `Read timed out`.
- Known-flaky area: tests using `Thread.sleep`, wall-clock time, real network, or shared fixtures.
- Ordering dependence — fails only when the suite runs in a particular order, or only in parallel.
- Resource contention: port already in use, database lock, container not ready.

**Java specifics:** Testcontainers startup races, `@DirtiesContext` interacting with a shared Spring context, static state leaking between tests, `LocalDateTime.now()` crossing a boundary.

**Frontend specifics:** unawaited promises, `waitFor` with too short a timeout, animation and transition timing, fake timers not reset between tests.

**Action:** re-run **once**. If it passes, file the flake with the run URL — a flake nobody records is a flake nobody fixes, and it erodes trust in the whole suite until people stop reading failures at all. If it fails again the same way, it is not a flake; re-classify.

---

## 4. Config drift

Passes locally, fails in CI. The environments genuinely differ, and the difference is the bug.

**Signals**
- Works on your machine, fails on the runner, same commit.
- `Cannot find module`, `ClassNotFoundException`, `No such file` for something that exists locally.
- Version mismatches in the log versus your local toolchain.
- Missing environment variable or secret.

**The classic:** **filename case sensitivity.** macOS is case-insensitive, Linux runners are not. `import Button from './components/button'` resolves locally and fails in CI with `Cannot find module`. This is the single most common frontend drift failure and it is invisible on the developer's machine. Suspect it immediately on any CI-only module-resolution error.

**Java drift**
- JDK version mismatch between `setup-java` and your local toolchain.
- A Maven profile active locally but not in CI, or a missing `settings.xml` for a private repository.
- `~/.m2` cache state that exists locally and not on a clean runner.
- Tests depending on a locally-running database that CI does not provide.
- Default locale, timezone, or charset differing between machines.

**Frontend drift**
- `npm ci` (strict lockfile) versus a local `npm install` that silently updated it.
- Node version differences between `.nvmrc` and the workflow.
- `devDependencies` not installed under a production install.
- Peer dependency resolution differing between npm versions.

**Action:** fix the mismatch, not the symptom. Pin the version, add the variable, correct the filename case. And note it — drift failures recur across a team until the config is fixed at the source.

---

## 5. Infrastructure

The runner, the network, or the cache failed. Not your code and not your config.

**Signals**
- Runner ran out of disk or memory. `Killed`, exit 137, `OutOfMemoryError` at the JVM or container level.
- Registry or download timeouts: npm, Maven Central, Docker Hub.
- Cache restore failure or corruption.
- An action version deprecated or yanked.
- The job was cancelled or the runner disconnected.

**Exit code hints:** 137 is SIGKILL, usually out-of-memory. 143 is SIGTERM, usually cancellation or timeout.

**Action:** re-run. If it recurs, it is a platform or workflow-config problem and belongs with whoever owns CI — not something to work around inside a feature PR.

---

## Classification checklist

Run through these before committing to a diagnosis:

1. Is the same workflow red on the default branch? → base-branch breakage.
2. Does the failure touch files the diff changed? → leans real failure.
3. Has this exact step passed and failed alternately? → leans flake.
4. Does it reproduce locally? → real failure. Does it not? → drift or flake.
5. Is the error about the environment rather than the code? → drift or infrastructure.

**When two categories fit, say so and name what would decide it.** "Real failure if it reproduces locally; config drift if it does not — run the test locally and we will know" is a more useful answer than a confident wrong one.

## Anti-patterns

- **Re-running without classifying.** The most common failure mode. It works often enough to become a habit, and the times it hides a real bug are the times that matter.
- **Fixing the top of the stack trace.** The wrapper exception is rarely the cause.
- **Treating the last error as the cause.** Later errors are usually consequences; find the first one chronologically.
- **Fixing main inside a feature PR.** Entangles two changes.
- **Loosening a test to make CI green.** If the assertion was right, the code is wrong. Changing the assertion to match broken behavior is how a suite stops meaning anything.
