#!/usr/bin/env bash
# detect_bmad.sh — discover what BMAD is actually installed here, without assuming.
#
# Usage: ./detect_bmad.sh [project-root]   (defaults to current directory)
#
# Read-only. Reports the installation root, modules present, configuration,
# existing artifacts, in-flight workflow state, and the real invocation surface.
# Prints UNKNOWN rather than guessing. Exit code is always 0 — absence of BMAD
# is a finding, not an error.

set -uo pipefail
START="${1:-.}"
cd "$START" 2>/dev/null || { echo "Cannot enter $START"; exit 0; }

hr() { printf '\n=== %s ===\n' "$1"; }

# --- Locate the installation root by walking up, since the skill may be
# --- invoked from a subdirectory of the project.
BMAD_ROOT=""
PROJECT_ROOT=""
d="$(pwd)"
while [ "$d" != "/" ]; do
  if [ -d "$d/_bmad" ]; then BMAD_ROOT="$d/_bmad"; PROJECT_ROOT="$d"; break; fi
  d="$(dirname "$d")"
done

hr "INSTALLATION"
if [ -n "$BMAD_ROOT" ]; then
  echo "Status:       INSTALLED"
  echo "Project root: $PROJECT_ROOT"
  echo "BMad root:    $BMAD_ROOT"
else
  echo "Status:       NOT FOUND (no _bmad/ directory in this tree)"
  echo "Project root: $(pwd)"
fi

hr "LEGACY / CONFLICTING INSTALLS"
# Check at the project root, not the working directory — this skill is often
# invoked from a subdirectory and these artifacts always live at the top.
SCAN_ROOT="${PROJECT_ROOT:-$(pwd)}"
# v6 migrated from dot-prefixed folders. Leftovers cause the installer to warn
# and can shadow current commands with stale ones.
LEGACY=0
for legacy in .bmad .bmad-core .bmad-method bmad _cfg; do
  if [ -e "$SCAN_ROOT/$legacy" ]; then
    echo "  FOUND: $SCAN_ROOT/$legacy  (pre-v6 layout — likely stale)"; LEGACY=1
  fi
done
if [ -e "$SCAN_ROOT/{output_folder}" ]; then
  echo "  FOUND: $SCAN_ROOT/{output_folder}  (literal unresolved template directory)"
  echo "         Known installer bug. The working fix is the dedicated"
  echo "         --output-folder flag, not --set core.output_folder=..."
  LEGACY=1
fi
[ "$LEGACY" = "0" ] && echo "  (none)"

if [ -z "$BMAD_ROOT" ]; then
  hr "PREREQUISITES (for a future install)"
  for tool in node python3 uv npx; do
    if command -v "$tool" >/dev/null 2>&1; then
      printf '  %-8s %s\n' "$tool" "$($tool --version 2>&1 | head -1)"
    else
      printf '  %-8s MISSING\n' "$tool"
    fi
  done
  echo
  echo "  BMad v6 requires Node >=20.12, Python >=3.10, and uv."
  echo "  Install with: npx bmad-method install"
  echo "  On a managed machine, confirm this is permitted before running it."
  hr "DONE"
  echo "No BMad installation. Triage can still proceed — it may conclude BMad is unnecessary."
  exit 0
fi

hr "MODULES PRESENT"
# Do not assume which modules exist; list what is actually on disk.
for m in "$BMAD_ROOT"/*/; do
  name="$(basename "$m")"
  case "$name" in _config|_cfg) continue ;; esac
  ver=""
  for vf in "$m/config.yaml" "$m/module.yaml" "$m/manifest.yaml" "$m/package.json"; do
    [ -f "$vf" ] && ver="$(grep -oE '"?version"?[: ]+"?v?[0-9]+\.[0-9]+\.[0-9]+' "$vf" 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')" && [ -n "$ver" ] && break
  done
  printf '  %-10s %s\n' "$name" "${ver:+v$ver}"
done

hr "CONFIGURATION"
# Layout has moved between releases: per-module config.yaml in early v6,
# a central config.toml later. Check both rather than picking one.
found_cfg=0
for cfg in "$PROJECT_ROOT/_bmad/config.toml" "$PROJECT_ROOT/_bmad/_config/config.toml" \
           "$PROJECT_ROOT/_bmad/core/config.yaml" "$PROJECT_ROOT/_bmad/bmm/config.yaml"; do
  if [ -f "$cfg" ]; then
    echo "  --- ${cfg#$PROJECT_ROOT/} ---"
    grep -vE '^\s*(#|$)' "$cfg" 2>/dev/null | head -25 | sed 's/^/    /'
    found_cfg=1
  fi
done
[ "$found_cfg" = "0" ] && echo "  UNKNOWN — no config file at any known path. Inspect $BMAD_ROOT manually."

# Surface the resolved output folder, which the rest of the triage depends on.
OUT=""
for cand in "$PROJECT_ROOT/_bmad-output" "$PROJECT_ROOT/docs" "$PROJECT_ROOT/{output_folder}"; do
  [ -d "$cand" ] && OUT="$cand" && break
done
echo
echo "  Output folder: ${OUT:-UNKNOWN}"

hr "EXISTING ARTIFACTS"
if [ -n "$OUT" ]; then
  find "$OUT" -maxdepth 3 -type f \( -name '*.md' -o -name '*.yaml' -o -name '*.yml' \) 2>/dev/null \
    | head -40 | while read -r f; do
        printf '  %-60s %s\n' "${f#$PROJECT_ROOT/}" "$(date -r "$f" +%Y-%m-%d 2>/dev/null)"
      done
  [ -z "$(find "$OUT" -type f 2>/dev/null | head -1)" ] && echo "  (output folder exists but is empty)"
else
  echo "  UNKNOWN — output folder not located"
fi

hr "IN-FLIGHT WORKFLOW STATE"
# workflow-init writes a status file; its presence means work is already underway
# and starting fresh would discard context.
STATUS="$(find "$PROJECT_ROOT" -maxdepth 4 -name 'bmm-workflow-status.yaml' \
          -not -path '*/node_modules/*' 2>/dev/null | head -1)"
if [ -n "$STATUS" ]; then
  echo "  FOUND: ${STATUS#$PROJECT_ROOT/}"
  echo "  --- contents ---"
  sed 's/^/    /' "$STATUS" 2>/dev/null | head -30
  echo
  echo "  >> Work is already in progress. Resume rather than restart."
else
  echo "  None — no workflow has been initialized in this project."
fi

hr "INVOCATION SURFACE (actual, not assumed)"
# Command naming has differed across releases and across host tools. Enumerate
# what this installation really provides instead of reciting remembered syntax.
SURFACE=0
for dir in "$PROJECT_ROOT/.claude/commands" "$PROJECT_ROOT/.claude/skills" \
           "$HOME/.claude/commands" "$HOME/.claude/skills"; do
  if [ -d "$dir" ]; then
    hits="$(find "$dir" -maxdepth 2 \( -iname '*bmad*' -o -iname '*bmm*' \) 2>/dev/null | head -40)"
    if [ -n "$hits" ]; then
      echo "  --- ${dir/#$HOME/\~} ---"
      echo "$hits" | sed "s|$dir/||" | sed 's/^/    /'
      SURFACE=1
    fi
  fi
done
if [ "$SURFACE" = "0" ]; then
  echo "  No BMad commands or skills found in the usual host directories."
  echo "  The install may target a different tool, or the host may need a restart."
  echo "  Workflow directories present under the module tree:"
  find "$BMAD_ROOT" -maxdepth 3 -type d -name 'workflows' 2>/dev/null \
    | sed "s|$PROJECT_ROOT/||" | sed 's/^/    /' | head -10
fi

hr "AVAILABLE WORKFLOWS (from module tree)"
find "$BMAD_ROOT" -maxdepth 4 -type d -path '*workflows*' -mindepth 3 2>/dev/null \
  | sed "s|$BMAD_ROOT/||" | sort | head -40
echo "  (directory names, not necessarily invocable command names)"

hr "DONE"
echo "Discovery complete. Use only the commands and paths listed above."
echo "If something needed is absent, say so — do not substitute remembered syntax."
