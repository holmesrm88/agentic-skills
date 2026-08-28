#!/usr/bin/env bash
# collect_diff.sh — assemble the review packet for the subagent panel.
#
# Usage: ./collect_diff.sh [base-branch]   (auto-detects main/master/develop)
#
# Produces .harness/reviews/packet/ containing the story diff, the changed-line
# map, and the commit list. The changed-line map is the important artifact: it
# makes "is this finding in scope?" a lookup instead of a judgment call, which
# is what stops the panel from smuggling pre-existing problems into the story.

set -uo pipefail
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "Not a git repository."; exit 1; }
cd "$ROOT" || exit 1

OUT=".harness/reviews/packet"
mkdir -p "$OUT"

# --- Base branch detection. Do not assume main.
BASE="${1:-}"
if [ -z "$BASE" ]; then
  for cand in main master develop trunk; do
    if git show-ref --verify --quiet "refs/heads/$cand"; then BASE="$cand"; break; fi
    if git show-ref --verify --quiet "refs/remotes/origin/$cand"; then BASE="origin/$cand"; break; fi
  done
fi
[ -z "$BASE" ] && { echo "Cannot determine base branch. Pass it explicitly."; exit 1; }

HEAD_REF="$(git rev-parse --abbrev-ref HEAD)"
MERGE_BASE="$(git merge-base "$BASE" HEAD 2>/dev/null)" || { echo "No merge base with $BASE."; exit 1; }

if [ "$MERGE_BASE" = "$(git rev-parse HEAD)" ]; then
  echo "HEAD is identical to the merge base with $BASE — nothing to review."
  exit 2
fi

# --- Working tree must be clean; a dirty tree means the diff under review is
# --- not the diff that will be pushed.
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  echo "REFUSING: working tree is dirty. Commit or stash before review."
  git status --short
  exit 3
fi

{
  echo "base_branch: $BASE"
  echo "head_branch: $HEAD_REF"
  echo "merge_base: $MERGE_BASE"
  echo "head: $(git rev-parse HEAD)"
  echo "generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$OUT/meta.yaml"

git log --format='%h %s' "$MERGE_BASE"..HEAD > "$OUT/commits.txt"
git diff "$MERGE_BASE"..HEAD > "$OUT/story.diff"
git diff --stat "$MERGE_BASE"..HEAD > "$OUT/diffstat.txt"
git diff --name-status "$MERGE_BASE"..HEAD > "$OUT/changed-files.txt"

# --- Changed-line map. For each file, the line ranges the story actually
# --- touched in their post-change numbering. A finding outside these ranges is
# --- pre-existing code, however bad it looks.
: > "$OUT/changed-lines.txt"
git diff --unified=0 "$MERGE_BASE"..HEAD \
  | awk '
      /^\+\+\+ b\// { file = substr($0, 7); next }
      /^@@/ {
        # @@ -old,cnt +new,cnt @@
        match($0, /\+[0-9]+(,[0-9]+)?/)
        spec = substr($0, RSTART+1, RLENGTH-1)
        split(spec, a, ",")
        start = a[1]
        cnt = (length(a) > 1) ? a[2] : 1
        if (cnt > 0 && file != "" && file != "/dev/null")
          printf "%s:%d-%d\n", file, start, start + cnt - 1
      }
    ' >> "$OUT/changed-lines.txt"

# --- Split test changes from production changes. Ghost-test detection cares
# --- about the first set; security review cares mostly about the second.
grep -E '(^|/)(src/test/|test/|tests/)' "$OUT/changed-files.txt" > "$OUT/changed-tests.txt" 2>/dev/null || : > "$OUT/changed-tests.txt"
grep -vE '(^|/)(src/test/|test/|tests/)' "$OUT/changed-files.txt" > "$OUT/changed-prod.txt" 2>/dev/null || : > "$OUT/changed-prod.txt"

# --- Round detection from previously written reviews.
ROUND=1
if [ -d .harness/reviews ]; then
  PREV="$(find .harness/reviews -maxdepth 1 -name 'round-*.md' 2>/dev/null | wc -l | tr -d ' ')"
  ROUND=$((PREV + 1))
fi
echo "round: $ROUND" >> "$OUT/meta.yaml"

echo "=== REVIEW PACKET ==="
echo "Base:        $BASE ($MERGE_BASE)"
echo "Head:        $HEAD_REF"
echo "Round:       $ROUND"
echo "Commits:     $(wc -l < "$OUT/commits.txt" | tr -d ' ')"
echo "Files:       $(wc -l < "$OUT/changed-files.txt" | tr -d ' ') ($(wc -l < "$OUT/changed-prod.txt" | tr -d ' ') prod, $(wc -l < "$OUT/changed-tests.txt" | tr -d ' ') test)"
echo "Diff size:   $(wc -l < "$OUT/story.diff" | tr -d ' ') lines"
echo "Scope ranges:$(wc -l < "$OUT/changed-lines.txt" | tr -d ' ') hunks"
echo
echo "Packet: $ROOT/$OUT"

if [ "$ROUND" -gt 2 ]; then
  echo
  echo "WARNING: round $ROUND. The cap is 2. Stop and escalate to a human"
  echo "         rather than running another remediation cycle."
fi
