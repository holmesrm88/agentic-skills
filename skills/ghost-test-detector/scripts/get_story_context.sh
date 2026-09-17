#!/usr/bin/env bash
# get_story_context.sh — find the story key for the work being committed.
#
# Usage: ./get_story_context.sh [STORY-KEY]
#
# The acceptance criteria are what let the semantic pass ask "do these tests
# check what was asked for?" rather than only "can these tests fail?". Without
# them the review still works, but it answers the narrower question — and must
# say so rather than implying otherwise.
#
# Resolution order, most to least reliable:
#   1. A key passed on the command line
#   2. The cached key from a previous run in this repo
#   3. The branch name, if it happens to contain one
#   4. The PR body or title, if a PR exists
#   5. Nothing — report honestly and let the caller degrade

set -uo pipefail

CACHE=".ghost-check/story"
KEY_RE='[A-Z][A-Z0-9]+-[0-9]+'

emit() {
  mkdir -p "$(dirname "$CACHE")" 2>/dev/null
  printf '%s\n' "$1" > "$CACHE" 2>/dev/null
  echo "STORY_KEY=$1"
  echo "SOURCE=$2"
}

# 1. Explicit
if [ -n "${1:-}" ]; then
  K="$(printf '%s' "$1" | grep -oE "$KEY_RE" | head -1)"
  if [ -n "$K" ]; then emit "$K" "explicit argument"; exit 0; fi
  echo "'$1' does not look like a story key (expected e.g. PROJ-1234)." >&2
  exit 1
fi

# 2. Cache
if [ -f "$CACHE" ]; then
  K="$(grep -oE "$KEY_RE" "$CACHE" 2>/dev/null | head -1)"
  if [ -n "$K" ]; then
    echo "STORY_KEY=$K"
    echo "SOURCE=cached (.ghost-check/story) — pass a key explicitly if this is stale"
    exit 0
  fi
fi

# 3. Branch name
BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
if [ -n "$BRANCH" ]; then
  K="$(printf '%s' "$BRANCH" | grep -oE "$KEY_RE" | head -1)"
  if [ -n "$K" ]; then emit "$K" "branch name"; exit 0; fi
fi

# 4. PR, if one exists
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  BODY="$(gh pr view --json title,body --jq '.title + " " + (.body // "")' 2>/dev/null || true)"
  if [ -n "$BODY" ]; then
    K="$(printf '%s' "$BODY" | grep -oE "$KEY_RE" | head -1)"
    if [ -n "$K" ]; then emit "$K" "pull request"; exit 0; fi
  fi
fi

# 5. Nothing
echo "STORY_KEY="
echo "SOURCE=none"
echo "No story key found. The semantic review can still check whether the tests"
echo "exercise the changed code and could fail, but not whether they cover the"
echo "acceptance criteria. Pass one explicitly to enable the full check:"
echo "    $0 PROJ-1234"
exit 0
