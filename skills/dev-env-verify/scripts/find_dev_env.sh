#!/usr/bin/env bash
# find_dev_env.sh — locate the ephemeral environment for the current PR.
#
# Usage: ./find_dev_env.sh [pr-number]   (defaults to the PR for the current branch)
#
# Ephemeral environment URLs surface in several different places depending on how
# the workflow publishes them. This checks all of them and reports every candidate
# rather than picking one silently — testing against the wrong URL produces a
# confident, wrong verification result.

set -uo pipefail

hr() { printf '\n=== %s ===\n' "$1"; }

if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI not found. Install: https://cli.github.com"
  exit 127
fi
if ! gh auth status >/dev/null 2>&1; then
  echo "gh is installed but not authenticated. Run: gh auth login"
  exit 126
fi

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "Not a git repository."; exit 1; }
cd "$ROOT" || exit 1

BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
PR="${1:-}"
if [ -z "$PR" ]; then
  PR="$(gh pr view --json number --jq '.number' 2>/dev/null)"
fi
if [ -z "$PR" ] || [ "$PR" = "null" ]; then
  echo "No PR found for branch '$BRANCH'."
  echo "The environment is created on PR open — create a draft PR first."
  exit 2
fi

REPO="$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null)"

hr "PULL REQUEST"
gh pr view "$PR" --json number,title,isDraft,state,headRefName,headRefOid,url \
  --jq '"PR:      #\(.number) \(.title)",
        "State:   \(.state)\(if .isDraft then " (draft)" else "" end)",
        "Branch:  \(.headRefName)",
        "Commit:  \(.headRefOid[0:7])",
        "URL:     \(.url)"' 2>/dev/null

# --- Build status first. An environment from a previous commit is worse than no
# --- environment, because it looks valid and tests the wrong code.
hr "BUILD STATUS FOR HEAD COMMIT"
gh pr view "$PR" --json statusCheckRollup \
  --jq '.statusCheckRollup[]? | "  \(.conclusion // .state // "PENDING")  \(.name // .context)"' 2>/dev/null \
  | sort -u

PENDING="$(gh pr view "$PR" --json statusCheckRollup \
  --jq '[.statusCheckRollup[]? | select((.conclusion // .state) == null or (.conclusion // .state) == "PENDING" or (.conclusion // .state) == "IN_PROGRESS")] | length' 2>/dev/null)"
FAILING="$(gh pr view "$PR" --json statusCheckRollup \
  --jq '[.statusCheckRollup[]? | select((.conclusion // .state) == "FAILURE" or (.conclusion // .state) == "ERROR")] | length' 2>/dev/null)"

echo
[ "${PENDING:-0}" -gt 0 ] && echo "  >> ${PENDING} check(s) still running. The environment may not be current."
[ "${FAILING:-0}" -gt 0 ] && echo "  >> ${FAILING} check(s) FAILING. Triage the build before verifying — run gh-actions-triage."

# --- Candidate 1: GitHub Deployments API. The most reliable source when the
# --- workflow publishes a deployment, which is the documented pattern.
hr "CANDIDATE: DEPLOYMENTS API"
gh api "repos/$REPO/deployments?ref=$BRANCH&per_page=5" \
  --jq '.[] | "  id=\(.id)  env=\(.environment)  created=\(.created_at)"' 2>/dev/null \
  || echo "  (none, or no permission to read deployments)"

for dep in $(gh api "repos/$REPO/deployments?ref=$BRANCH&per_page=3" --jq '.[].id' 2>/dev/null); do
  gh api "repos/$REPO/deployments/$dep/statuses" \
    --jq '.[0] | "  deployment \('"$dep"'): state=\(.state)  url=\(.environment_url // .target_url // "none")"' 2>/dev/null
done

# --- Candidate 2: check-run details. Many workflows put the URL here instead.
hr "CANDIDATE: CHECK RUN TARGET URLS"
gh pr view "$PR" --json statusCheckRollup \
  --jq '.statusCheckRollup[]? | select(.targetUrl != null and .targetUrl != "") | "  \(.name // .context): \(.targetUrl)"' 2>/dev/null \
  | grep -v 'github.com/.*/actions/runs' | sort -u
echo "  (Actions run links filtered out — those are logs, not environments)"

# --- Candidate 3: bot comments. Common pattern for preview environments.
hr "CANDIDATE: URLS IN PR COMMENTS"
gh pr view "$PR" --json comments \
  --jq '.comments[]? | "\(.author.login): \(.body)"' 2>/dev/null \
  | grep -oE 'https?://[A-Za-z0-9._~:/?#@!$&+,;=%-]+' \
  | grep -viE 'github\.com|githubusercontent|shields\.io' \
  | sort -u | head -10
echo "  (empty means no bot has posted a URL)"

# --- Candidate 4: the PR body.
hr "CANDIDATE: URLS IN PR BODY"
gh pr view "$PR" --json body --jq '.body // ""' 2>/dev/null \
  | grep -oE 'https?://[A-Za-z0-9._~:/?#@!$&+,;=%-]+' \
  | grep -viE 'github\.com|githubusercontent' | sort -u | head -5
echo "  (empty means none in the description)"

hr "NEXT"
cat <<'EOF'
Pick the URL that matches this PR's head commit. If several candidates appeared and
it is not obvious which is current, ask rather than guessing — verifying against a
stale environment produces a confident wrong answer.

If nothing was found, the workflow may publish the URL somewhere this script does not
check. Look at the Actions run summary or the Environments tab once, then say where
it lives so this can be narrowed next time.

Authentication is manual: open the URL and log in yourself before verification starts.
EOF
