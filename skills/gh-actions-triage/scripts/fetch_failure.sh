#!/usr/bin/env bash
# fetch_failure.sh — pull a failed GitHub Actions run down to the part that matters.
#
# Usage: ./fetch_failure.sh [run-id]     (defaults to latest failed run on current branch)
#
# Actions logs run to thousands of lines. Reading them into a model wholesale is
# expensive and mostly noise. This fetches only failed steps, extracts error
# signatures, and gathers the history needed to tell a real failure from a flake.
# Full logs are saved to disk so they can be grepped on demand rather than read.

set -uo pipefail

hr() { printf '\n=== %s ===\n' "$1"; }

# --- Preconditions -----------------------------------------------------------
if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI not found. Install: https://cli.github.com"
  echo "Without it, fetch logs from the Actions tab in the browser and paste the failed step."
  exit 127
fi
if ! gh auth status >/dev/null 2>&1; then
  echo "gh is installed but not authenticated. Run: gh auth login"
  exit 126
fi

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "Not a git repository."; exit 1; }
cd "$ROOT" || exit 1
OUT=".harness/ci"; mkdir -p "$OUT"

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
RUN_ID="${1:-}"

if [ -z "$RUN_ID" ]; then
  RUN_ID="$(gh run list --branch "$BRANCH" --status failure --limit 1 --json databaseId \
            --jq '.[0].databaseId' 2>/dev/null)"
fi
if [ -z "$RUN_ID" ] || [ "$RUN_ID" = "null" ]; then
  echo "No failed run found on branch '$BRANCH'."
  echo "Check for a run in progress: gh run list --branch $BRANCH --limit 5"
  exit 2
fi

# --- Run metadata ------------------------------------------------------------
hr "RUN"
gh run view "$RUN_ID" --json displayTitle,headBranch,event,conclusion,createdAt,updatedAt,workflowName,url \
  --jq '"Workflow:  \(.workflowName)
Title:     \(.displayTitle)
Branch:    \(.headBranch)
Event:     \(.event)
Result:    \(.conclusion)
Started:   \(.createdAt)
URL:       \(.url)"' 2>/dev/null

hr "FAILED JOBS AND STEPS"
gh run view "$RUN_ID" --json jobs \
  --jq '.jobs[] | select(.conclusion=="failure") |
        "JOB: \(.name)  (\(.startedAt) → \(.completedAt))",
        (.steps[] | select(.conclusion=="failure") | "  FAILED STEP: \(.name)")' 2>/dev/null

# --- Failed-step logs only. This is the single biggest token saving available.
gh run view "$RUN_ID" --log-failed > "$OUT/failed-$RUN_ID.log" 2>/dev/null
LINES="$(wc -l < "$OUT/failed-$RUN_ID.log" | tr -d ' ')"

hr "LOG"
echo "Failed-step log: $OUT/failed-$RUN_ID.log ($LINES lines)"
echo "Full run log available on demand: gh run view $RUN_ID --log > $OUT/full-$RUN_ID.log"

# --- Error signature extraction ---------------------------------------------
# Narrow to lines that usually contain the actual cause. Print with context so
# the surrounding frames are visible without reading the whole file.
hr "ERROR SIGNATURES (first 40 matches)"
grep -nE \
  '(\[ERROR\]|\bERROR\b|FAILURE|BUILD FAILED|FAILED|Exception|[A-Za-z]*Error\b|Caused by:|expected:.*but was|AssertionFailed|ComparisonFailure|error TS[0-9]+|error:|npm ERR!|\bfatal\b|Process completed with exit code|Cannot find module|ModuleNotFoundError|No such file|Permission denied|OutOfMemoryError|Killed|timed out|timeout)' \
  "$OUT/failed-$RUN_ID.log" 2>/dev/null | head -40

hr "ASSERTION DETAIL"
# The expected-vs-actual line is usually the most informative in the whole log.
grep -nE '(expected:|but was:|AssertionFailed|ComparisonFailure|Expected .* received)' \
  "$OUT/failed-$RUN_ID.log" 2>/dev/null | head -10
echo "(empty means the failure is not an assertion)"

hr "TEST FAILURES (parsed)"
# Surefire/Gradle style. Filter stack-frame matches like "OrderServiceTest.java",
# which look like test identifiers but are file references.
grep -oE '[A-Za-z0-9_.]+Test[A-Za-z0-9_]*[.#][a-zA-Z0-9_]+' "$OUT/failed-$RUN_ID.log" 2>/dev/null \
  | grep -vE '\.(java|kt|scala|groovy|class)$' | sed 's/#/./' | sort -u | head -20
# Jest/Vitest style
grep -oE '(✕|✗|●) .*' "$OUT/failed-$RUN_ID.log" 2>/dev/null | sort -u | head -20
echo "(empty means the failure is not a test assertion — likely build, lint, or infra)"

hr "EXIT CODE"
grep -oE 'Process completed with exit code [0-9]+' "$OUT/failed-$RUN_ID.log" 2>/dev/null | tail -3

# --- History. This is what separates a real failure from a flake, and it is the
# --- check people skip because it is tedious by hand.
DEFAULT_BRANCH="$(gh repo view --json defaultBranchRef --jq '.defaultBranchRef.name' 2>/dev/null || echo main)"
WORKFLOW="$(gh run view "$RUN_ID" --json workflowName --jq '.workflowName' 2>/dev/null)"

hr "SAME WORKFLOW ON $DEFAULT_BRANCH (last 10)"
gh run list --branch "$DEFAULT_BRANCH" --workflow "$WORKFLOW" --limit 10 \
  --json conclusion,createdAt,displayTitle \
  --jq '.[] | "  \(.conclusion // "running")  \(.createdAt[0:10])  \(.displayTitle[0:60])"' 2>/dev/null
echo "  >> Failures here mean the base branch is already broken. Do not debug your diff."

hr "THIS BRANCH, SAME WORKFLOW (last 10)"
gh run list --branch "$BRANCH" --workflow "$WORKFLOW" --limit 10 \
  --json conclusion,createdAt,displayTitle \
  --jq '.[] | "  \(.conclusion // "running")  \(.createdAt[0:10])  \(.displayTitle[0:60])"' 2>/dev/null
echo "  >> Alternating pass/fail on the same commit range is a flake signal."

hr "WHAT THIS RUN TESTED"
gh run view "$RUN_ID" --json headSha --jq '.headSha' 2>/dev/null | while read -r sha; do
  echo "Commit: $sha"
  git log -1 --format='  %s  (%an, %ar)' "$sha" 2>/dev/null || echo "  (not fetched locally)"
  echo "Files changed vs $DEFAULT_BRANCH:"
  git diff --name-only "$DEFAULT_BRANCH...$sha" 2>/dev/null | head -20 | sed 's/^/    /'
done

hr "DONE"
echo "Classify before proposing a fix. Taxonomy: references/failure-taxonomy.md"
echo "Grep the saved log for detail rather than reading it whole:"
echo "  grep -n -A15 'Caused by' $OUT/failed-$RUN_ID.log"
