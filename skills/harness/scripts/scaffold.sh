#!/usr/bin/env bash
# scaffold.sh — create the .harness workspace. Idempotent; never overwrites existing state.
#
# Usage: ./scaffold.sh [repo-root]   (defaults to git toplevel, else cwd)

set -uo pipefail

ROOT="${1:-}"
if [ -z "$ROOT" ]; then
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || ROOT="$(pwd)"
fi
cd "$ROOT" || { echo "Cannot enter $ROOT"; exit 1; }

H=".harness"

if [ -d "$H" ]; then
  echo "REFUSING: $ROOT/$H already exists."
  echo "Existing state:"
  [ -f "$H/change-log.md" ] && sed -n '/## Current state/,/^<!-- HISTORY/p' "$H/change-log.md" | sed 's/^/  /'
  ls -1 "$H/features" 2>/dev/null | sed 's/^/  feature: /'
  echo
  echo "Resume, extend, or archive it — do not scaffold over it."
  exit 2
fi

mkdir -p "$H/features"

# Exclude locally without touching .gitignore, which is tracked and shared.
EXCLUDE=".git/info/exclude"
if [ -d .git ]; then
  mkdir -p .git/info
  if ! grep -qx '\.harness/' "$EXCLUDE" 2>/dev/null; then
    printf '\n# Local agentic harness state — not shared\n.harness/\n' >> "$EXCLUDE"
    echo "Registered .harness/ in $EXCLUDE (local only, not committed)."
  else
    echo ".harness/ already excluded in $EXCLUDE."
  fi
else
  echo "WARNING: not a git repository. State will not be excluded and there is"
  echo "         nothing to commit against. The loop expects git."
fi

cat > "$H/change-log.md" <<'EOF'
# Harness Change Log

<!-- CURRENT STATE — rewritten on every transition. Read this first. -->
## Current state

- **Story:** _not set_
- **Branch:** _not set_
- **Feature:** _none — decomposition not complete_
- **Phase:** init
- **Last gate:** never run
- **Uncommitted:** none
- **Blocked on:** nothing
- **Next:** capture baseline, then decompose

<!-- HISTORY — append only, newest at the bottom. Never edit past entries. -->
## History

EOF

cat > "$H/.gitattributes" <<'EOF'
* -diff
EOF

echo
echo "Scaffolded:"
echo "  $ROOT/$H/change-log.md"
echo "  $ROOT/$H/features/"
echo
echo "Next: generate init.sh, capture the baseline, then decompose."
echo "Confirm exclusion is working:  git status --porcelain | grep harness   (expect no output)"
