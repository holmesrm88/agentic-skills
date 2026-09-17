# CI Integration

Running the same evaluation on every pull request, so commits made without invoking the skill locally still get checked — and adding mutation testing as the ground truth the semantic pass can only approximate.

## Why CI matters here

The pre-commit path only runs when someone invokes it. A human committing from their IDE bypasses it entirely. CI runs on every push regardless of who wrote the code or how, which makes it the only layer with complete coverage.

It is also where anything slow belongs. Mutation testing takes minutes to hours; that is fine on a runner and impossible in a hook.

## Running this skill on every PR

`anthropics/claude-code-action@v1` runs the Claude Code runtime inside a GitHub Actions runner. Check out the repository first so the skill files are present, then pass the skill name as the prompt.

```yaml
name: Test Quality Review
on:
  pull_request:
    types: [opened, synchronize, reopened, ready_for_review]

jobs:
  review-tests:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pull-requests: write
      id-token: write
    steps:
      - uses: actions/checkout@v6
        with:
          fetch-depth: 0          # full history so the diff against base works

      - uses: anthropics/claude-code-action@v1
        with:
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
          prompt: |
            /ghost-test-detector

            REPO: ${{ github.repository }}
            PR: ${{ github.event.pull_request.number }}

            Review the test changes in this pull request. Compare the diff against
            the base branch rather than the staged index, since there is no staged
            index here. Extract the story key from the PR title or body if one is
            present and fetch its acceptance criteria; if none is present, say so
            and run the reduced review.

            Post findings as a PR comment. Report a clean result plainly if the
            tests are sound.
```

The skill must be at `.claude/skills/ghost-test-detector/` in the repository for `/ghost-test-detector` to resolve.

### Requiring a story key

Since the acceptance-criteria check depends on a story key, enforce one on the PR:

```yaml
      - name: Require a story key in the PR
        run: |
          echo "${{ github.event.pull_request.title }} ${{ github.event.pull_request.body }}" \
            | grep -qE '[A-Z][A-Z0-9]+-[0-9]+' \
            || { echo "PR must reference a story key, e.g. PROJ-1234."; exit 1; }
```

Five lines, and it turns the fullest version of the check from optional into routine.

### Two cautions

**Prompt injection.** Anthropic's own security-review action carries a warning that it is not hardened against prompt injection and should only review trusted pull requests. The same applies here: the model reads diff content, and diff content is attacker-controlled on an untrusted PR. For an internal repository with employees this is low risk. If forks or external contributors are ever in scope, require approval before workflows run.

**Cost.** This runs a model on every push to every PR. Trigger on `opened` and `ready_for_review` rather than every `synchronize` if that matters, at the cost of missing later pushes.

There is also an Anthropic-hosted Code Review service an organization admin can enable, which posts inline comments with no workflow to write. Less controllable than the action, but zero setup — worth considering before building.

## Mutation testing — the ground truth

Everything in the semantic pass *reasons* about whether a test would fail if the code were wrong. Mutation testing *proves* it: the tool changes the production code, reruns the tests, and reports which mutations survived. A surviving mutation is a behaviour no test protects.

This is the only layer that gives a definitive answer, which is why it is worth the runtime.

### Java — PIT

```xml
<plugin>
  <groupId>org.pitest</groupId>
  <artifactId>pitest-maven</artifactId>
  <version>1.16.1</version>
  <configuration>
    <targetClasses><param>com.yourco.*</param></targetClasses>
    <targetTests><param>com.yourco.*Test</param></targetTests>
    <mutationThreshold>60</mutationThreshold>
  </configuration>
</plugin>
```

```bash
./mvnw org.pitest:pitest-maven:mutationCoverage
```

**Run it on changed classes only in PR builds.** A full-repository mutation run on a large codebase takes hours. PIT supports scoping with `withHistory` and incremental analysis; scope `targetClasses` to the packages the PR touched.

**Read the surviving mutations, not the score.** The number is a summary; the list of survivors is the actionable part, and each survivor names a specific behaviour nothing tests. Treat a threshold as a floor to avoid regression, not a target to optimize — mutation scores are as gameable as coverage if you aim at them.

### Playwright

There is no established mutation-testing tool for E2E suites, and the economics are poor — each mutation requires a full browser run. The practical substitute is deliberate: once, break a piece of production code on purpose and confirm the relevant E2E test goes red. If it does not, the test is a ghost regardless of what it looks like.

Do this when adding a new E2E test rather than as a recurring job.

## The layered picture

| Layer | Question | Cost | Where |
|---|---|---|---|
| Static scan | Can these tests fail at all? | ms | hook, CI |
| Semantic review | Do they test the right thing? | seconds | pre-commit, CI |
| Mutation testing | Would they fail if the code broke? | minutes–hours | CI |
| Human review | Is this the right thing to build? | — | PR |

Each catches what the one above it cannot. None of them, together, makes bugs impossible.
