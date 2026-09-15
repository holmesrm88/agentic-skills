---
name: gh-actions-triage
description: Diagnose a failed GitHub Actions run — fetch the failed-step logs, find the actual error in the noise, classify it as a real failure, a flake, base-branch breakage, config drift, or infrastructure, and propose a specific fix. Use whenever CI is red — "the build failed", "CI is broken", "why did the pipeline fail", "check the Actions run", "my PR won't build" — or after pushing when a run needs checking. Do NOT use for local test failures that never reached CI, or for reviewing code quality (use java-code-review).
---

# GitHub Actions Triage

Turn a red build into a classified cause and a specific fix, without reading ten thousand lines of log.

Most CI failures are not what they look like at first glance. The most expensive mistake is debugging your own diff for an hour when the base branch was already broken, and the second most expensive is re-running a flake until it passes and shipping a real bug behind it. Classification comes before diagnosis, always.

## Token discipline

Actions logs are enormous and mostly noise — dependency downloads, step banners, timestamps. Reading one wholesale is expensive and makes the real error harder to find, not easier.

The approach, in order:

1. `scripts/fetch_failure.sh` pulls **only failed steps** (`gh run view --log-failed`), extracts error signatures with context, and saves the full log to `.harness/ci/` for grepping.
2. Read the script's summary, not the log file.
3. Grep the saved log for specifics when you need them — `grep -n -A15 'Caused by' .harness/ci/failed-<id>.log`.
4. Pull the complete run log only when the failed-step log genuinely lacks the cause, which is uncommon.

Never cat a log file into context to "have a look." Search it.

## Workflow

### 1. Fetch

Run `scripts/fetch_failure.sh` — with a run ID, or with no argument to take the latest failed run on the current branch. It needs `gh` installed and authenticated; it reports clearly and exits if either is missing rather than failing obscurely.

It returns run metadata, the failed jobs and steps, extracted error signatures, assertion detail, parsed test names, the exit code, and the history needed for classification.

### 2. Classify before diagnosing

Use `references/failure-taxonomy.md`. Five categories:

- **Base-branch breakage** — already failing before your change.
- **Real failure** — your diff broke something.
- **Flake** — nondeterminism, passes on re-run.
- **Config drift** — passes locally, fails in CI.
- **Infrastructure** — the runner, network, or cache failed.

**Check base-branch breakage first.** The script lists the last ten runs of the same workflow on the default branch. If those are red, stop — the problem is not yours, and the correct output is "main is broken, here's what's failing, this blocks everyone." Say it plainly rather than burying it.

State the classification with the evidence behind it. A classification without evidence is a guess.

### 3. Diagnose

Once classified, find the specific cause. Work from the assertion detail and the `Caused by:` chain — the deepest cause frame, not the top of the stack. For non-test failures, find the first error chronologically; later errors are usually consequences.

Cross-reference with what changed. The script lists files changed against the default branch. A failure in code the diff never touched points at flake, drift, or a pre-existing issue rather than the change.

### 4. Propose a fix

Be specific: the file, the change, and why it addresses the cause. If the fix is uncertain, say what would confirm it.

Then state the **recommended action**, which differs by classification:

| Classification | Action |
|---|---|
| Base-branch breakage | Report it. Do not fix it inside your PR. |
| Real failure | Fix locally, run the local gate, push. |
| Flake | Re-run **once**. If it passes, file the flake — do not just move on. |
| Config drift | Fix the CI config or the local/CI mismatch. |
| Infrastructure | Re-run. If it recurs, escalate — it is not yours. |

**Never recommend a re-run without evidence of nondeterminism.** "Just re-run it" is how real failures ship. A flake classification requires something concrete: an alternating pass/fail history, a timing-related error, or a known-flaky test. Absent that, treat it as real.

### 5. Do not push

Propose the fix and stop. The person decides whether to apply it, runs the local gate first, and pushes. Every push consumes a build and, on a PR, an environment spin-up — that is their call to spend.

## Where this sits in the loop

After a push, before dev-environment testing. A build failure means there is nothing deployed to test against yet.

**A CI failure is usually not a reason to re-plan.** Most are a lint error, a flaky test, a missing environment variable, or a dependency that resolves differently on the runner — fix, run the local gate, push again. Returning to decomposition is warranted only when diagnosis shows the *approach* was wrong, not the code. That is rarer than it feels in the moment, and it should be a deliberate call.

## Repeat failures

If the same run fails three times with different causes each time, stop fixing symptoms. Three unrelated failures on one change usually means the change is fighting something structural — a wrong assumption about the environment, or a test suite that was never green in CI to begin with. Say so instead of starting a fourth round.

If the same failure recurs after a fix, the diagnosis was wrong. Re-classify from the top rather than trying a variation on the same fix.
