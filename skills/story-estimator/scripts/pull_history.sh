#!/usr/bin/env bash
# pull_history.sh — fetch completed, pointed stories for calibration.
#
# Usage: ./pull_history.sh PROJECT_KEY [months-back]     (default 6 months)
#
# Writes raw JSON to .estimator/raw-history.json for analyze_history.py.
# Fetches only; all analysis and PII stripping happen in the analyzer.
#
# Notes on acli, from its documented behaviour:
#   - Always --json. Other output formats fail more often.
#   - --fields is unreliable with custom fields, and story points IS a custom
#     field, so this pulls full work items rather than a field subset.
#   - acli has intermittent "unexpected error" responses. Every call retries.

set -uo pipefail

PROJECT="${1:-}"
MONTHS="${2:-6}"
if [ -z "$PROJECT" ]; then
  echo "Usage: $0 PROJECT_KEY [months-back]"
  exit 1
fi

OUT=".estimator"; mkdir -p "$OUT"

if ! command -v acli >/dev/null 2>&1; then
  echo "acli not found. Install: https://developer.atlassian.com/cloud/acli/"
  exit 127
fi
if ! acli jira auth status >/dev/null 2>&1 && ! acli auth status >/dev/null 2>&1; then
  echo "acli is not authenticated. Run: acli jira auth login"
  exit 126
fi

# --- Retry wrapper. acli fails intermittently for reasons unrelated to syntax;
# --- a failed call here would otherwise look like "no data" and silently skew
# --- the calibration.
acli_retry() {
  local attempt=1 max=4 out=""
  while [ "$attempt" -le "$max" ]; do
    if out="$(acli "$@" 2>&1)"; then
      printf '%s' "$out"
      return 0
    fi
    if printf '%s' "$out" | grep -qi 'unexpected error\|trace id\|timeout\|502\|503'; then
      echo "  (attempt $attempt/$max failed, retrying)" >&2
      sleep $((attempt * 2))
      attempt=$((attempt + 1))
      continue
    fi
    printf '%s' "$out" >&2
    return 1
  done
  echo "  Failed after $max attempts." >&2
  return 1
}

echo "=== FIELD DISCOVERY ==="
# Story point field IDs differ per instance. Discover rather than assume.
acli_retry jira field list --json > "$OUT/fields.json" 2>/dev/null \
  || acli_retry jira field --json > "$OUT/fields.json" 2>/dev/null \
  || echo "  Could not list fields; the analyzer will infer from work item payloads."

if [ -s "$OUT/fields.json" ]; then
  python3 - "$OUT/fields.json" <<'PY' 2>/dev/null || true
import json,sys
try: d=json.load(open(sys.argv[1]))
except Exception: sys.exit(0)
items = d if isinstance(d,list) else d.get("values") or d.get("fields") or []
for f in items:
    n=(f.get("name") or "").lower()
    if any(k in n for k in ("story point","storypoint","point estimate","sprint")):
        print(f"  {f.get('id')}  {f.get('name')}")
PY
fi

echo
echo "=== FETCHING COMPLETED STORIES ==="
JQL="project = $PROJECT AND statusCategory = Done AND resolutiondate >= -${MONTHS}d"
# JQL uses days; convert months for clarity.
DAYS=$((MONTHS * 30))
JQL="project = $PROJECT AND statusCategory = Done AND resolutiondate >= -${DAYS}d ORDER BY resolutiondate DESC"
echo "JQL: $JQL"

acli_retry jira workitem search --jql "$JQL" --paginate --json > "$OUT/raw-history.json"
RC=$?

if [ "$RC" -ne 0 ] || [ ! -s "$OUT/raw-history.json" ]; then
  echo "Fetch failed or returned nothing."
  echo "Verify the project key and that you can see the project:"
  echo "  acli jira workitem search --jql \"project = $PROJECT\" --count"
  exit 2
fi

COUNT="$(python3 -c "
import json,sys
try:
    d=json.load(open('$OUT/raw-history.json'))
    items = d if isinstance(d,list) else (d.get('issues') or d.get('values') or d.get('workItems') or [])
    print(len(items))
except Exception as e:
    print(0)
" 2>/dev/null)"

echo "Fetched $COUNT completed work item(s) → $OUT/raw-history.json"
echo
echo "Next: python3 scripts/analyze_history.py $OUT/raw-history.json"
echo
echo "NOTE: this file contains assignee and reporter names as returned by Jira."
echo "      The analyzer strips them before any analysis. Do not commit it;"
echo "      .estimator/ should be excluded from version control."
