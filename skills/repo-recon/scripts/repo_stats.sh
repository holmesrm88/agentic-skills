#!/usr/bin/env bash
# repo_stats.sh — Phase 0 reconnaissance. Read-only; makes no changes to the repo.
#
# Usage: ./repo_stats.sh [repo-root]   (defaults to current directory)
#
# Produces: language mix, build files, entry-point counts, largest files,
# churn hotspots, dormant directories, and a per-directory ownership map.
# Every section is independently useful; failures in one do not stop the rest.

set -uo pipefail
ROOT="${1:-.}"
cd "$ROOT" || { echo "Cannot enter $ROOT"; exit 1; }

EXCLUDE='-not -path */target/* -not -path */build/* -not -path */node_modules/*
         -not -path */.git/* -not -path */out/* -not -path */.gradle/*
         -not -path */dist/* -not -path */vendor/* -not -path */.idea/*'

hr() { printf '\n=== %s ===\n' "$1"; }

hr "REPO"
echo "Path: $(pwd)"
if git rev-parse --git-dir >/dev/null 2>&1; then
  echo "Commit: $(git rev-parse --short HEAD 2>/dev/null)"
  echo "Branch: $(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
  echo "First commit: $(git log --reverse --format=%as 2>/dev/null | head -1)"
  echo "Last commit: $(git log -1 --format=%as 2>/dev/null)"
  echo "Total commits: $(git rev-list --count HEAD 2>/dev/null)"
  echo "Contributors: $(git log --format=%ae 2>/dev/null | sort -u | wc -l | tr -d ' ')"
  GIT=1
else
  echo "(not a git repository — history sections will be skipped)"
  GIT=0
fi

hr "LANGUAGE MIX (file count / total lines)"
# shellcheck disable=SC2086
find . -type f $EXCLUDE -name '*.*' 2>/dev/null \
  | sed 's/.*\.//' | sort | uniq -c | sort -rn | head -25 \
  | while read -r count ext; do
      case "$ext" in
        png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot|jar|war|zip|gz|class|pdf|bin|so|dll)
          printf '%8s files  %10s        .%s\n' "$count" "(binary)" "$ext"; continue ;;
      esac
      lines=$(find . -type f -name "*.${ext}" $EXCLUDE -exec cat {} + 2>/dev/null | wc -l | tr -d ' ')
      printf '%8s files  %10s lines  .%s\n' "$count" "$lines" "$ext"
    done

hr "BUILD & CONFIG FILES"
# shellcheck disable=SC2086
find . -maxdepth 3 $EXCLUDE \( \
  -name 'pom.xml' -o -name 'build.gradle*' -o -name 'settings.gradle*' \
  -o -name 'build.xml' -o -name 'BUILD*' -o -name 'Makefile' \
  -o -name 'Dockerfile*' -o -name 'docker-compose*' \
  -o -name '*.tf' -o -name 'Chart.yaml' -o -name 'package.json' \
  -o -name 'requirements.txt' -o -name 'pyproject.toml' \) 2>/dev/null | sort | head -40

hr "CI CONFIGURATION"
# shellcheck disable=SC2086
find . $EXCLUDE \( -path '*.github/workflows*' -o -name '.gitlab-ci.yml' \
  -o -name 'Jenkinsfile*' -o -name '.circleci*' -o -name 'azure-pipelines*' \
  -o -name '.travis.yml' -o -name 'bitbucket-pipelines.yml' \) 2>/dev/null | head -20 | tee /tmp/.ci_found
[ -s /tmp/.ci_found ] || echo "  (none in-repo — CI is likely configured externally; ask the team)"
rm -f /tmp/.ci_found

hr "DOCUMENTATION"
# shellcheck disable=SC2086
find . -maxdepth 2 $EXCLUDE \( -iname 'README*' -o -iname 'CONTRIBUTING*' \
  -o -iname 'ARCHITECTURE*' -o -iname 'CHANGELOG*' -o -type d -name 'docs' \
  -o -type d -name 'adr' \) 2>/dev/null | head -20

hr "TOP-LEVEL DIRECTORIES BY SOURCE FILE COUNT"
for d in */; do
  [ -d "$d" ] || continue
  case "$d" in .git/|target/|build/|node_modules/|.gradle/|.idea/) continue ;; esac
  # shellcheck disable=SC2086
  n=$(find "$d" -type f $EXCLUDE \( -name '*.java' -o -name '*.kt' -o -name '*.scala' \
      -o -name '*.groovy' -o -name '*.py' -o -name '*.js' -o -name '*.ts' \) 2>/dev/null | wc -l | tr -d ' ')
  [ "$n" -gt 0 ] && printf '%8s  %s\n' "$n" "$d"
done | sort -rn | tee /tmp/.topdirs
# A single source directory tells you nothing; drill down to find the real modules.
if [ "$(wc -l < /tmp/.topdirs | tr -d ' ')" -le 1 ]; then
  echo "  --- only one top-level source dir; showing package/module depth instead ---"
  # shellcheck disable=SC2086
  find . -type d $EXCLUDE -not -path '*/src/main/resources/*' 2>/dev/null \
    | while read -r sub; do
        n=$(find "$sub" -maxdepth 1 -type f \( -name '*.java' -o -name '*.kt' \) 2>/dev/null | wc -l | tr -d ' ')
        [ "$n" -gt 0 ] && printf '%8s  %s\n' "$n" "$sub"
      done | sort -rn | head -20
fi
rm -f /tmp/.topdirs

hr "JVM ENTRY POINT SIGNALS (occurrence counts)"
# Word-boundary matching: plain "@Path" would also match "@PathVariable",
# which would falsely suggest JAX-RS in a Spring MVC codebase.
EP_FOUND=0
for pat in '@RestController' '@Controller' '@Path' '@RequestMapping' \
           '@GetMapping' '@PostMapping' '@PutMapping' '@DeleteMapping' \
           '@KafkaListener' '@JmsListener' '@RabbitListener' '@SqsListener' \
           '@Scheduled' 'public static void main' \
           '@Entity' '@Repository' '@Service' '@Component' '@Transactional' \
           '@SpringBootApplication' '@ConfigurationProperties'; do
  n=$(grep -rE "${pat}([^A-Za-z0-9_]|$)" --include='*.java' --include='*.kt' . 2>/dev/null \
      | grep -v '/target/\|/build/' | wc -l | tr -d ' ')
  if [ "$n" -gt 0 ]; then printf '%6s  %s\n' "$n" "$pat"; EP_FOUND=1; fi
done
[ "$EP_FOUND" = "0" ] && echo "  (none — not a Spring/Jakarta-style JVM codebase)"

hr "OTHER PROTOCOL SURFACES"
# shellcheck disable=SC2086
find . -type f $EXCLUDE \( -name '*.proto' -o -name '*.graphqls' -o -name '*.graphql' \
  -o -name 'web.xml' -o -name '*.wsdl' -o -name 'openapi*.y*ml' -o -name 'swagger*.y*ml' \) 2>/dev/null | head -15
echo "(empty means no gRPC/GraphQL/SOAP/OpenAPI artifacts in-repo)"

hr "LARGEST SOURCE FILES (lines) — often the load-bearing ones"
# shellcheck disable=SC2086
find . -type f $EXCLUDE \( -name '*.java' -o -name '*.kt' -o -name '*.scala' \
  -o -name '*.py' -o -name '*.ts' -o -name '*.js' \) -exec wc -l {} + 2>/dev/null \
  | sort -rn | grep -v ' total$' | head -15

if [ "$GIT" = "1" ]; then
  hr "CHURN HOTSPOTS (commits touching each file, last 2 years)"
  git log --since='2 years ago' --name-only --format='' 2>/dev/null \
    | grep -v '^$' | sort | uniq -c | sort -rn | head -20

  hr "MOST ACTIVE DIRECTORIES (last 12 months)"
  git log --since='12 months ago' --name-only --format='' 2>/dev/null \
    | grep -v '^$' | xargs -n1 dirname 2>/dev/null | sort | uniq -c | sort -rn | head -15

  hr "DORMANT TOP-LEVEL DIRECTORIES (no commits in 12 months)"
  for d in */; do
    [ -d "$d" ] || continue
    case "$d" in .git/|target/|build/|node_modules/|.gradle/|.idea/) continue ;; esac
    last=$(git log -1 --format=%as -- "$d" 2>/dev/null)
    if [ -n "$last" ]; then
      cutoff=$(date -d '12 months ago' +%Y-%m-%d 2>/dev/null || date -v-12m +%Y-%m-%d 2>/dev/null)
      [ -n "$cutoff" ] && [ "$last" \< "$cutoff" ] && printf '  %s  last touched %s\n' "$d" "$last"
    fi
  done
  echo "(nothing listed means all directories have recent activity)"

  hr "OWNERSHIP: top committers per top-level directory (last 18 months)"
  for d in */; do
    [ -d "$d" ] || continue
    case "$d" in .git/|target/|build/|node_modules/|.gradle/|.idea/) continue ;; esac
    out=$(git log --since='18 months ago' --format='%an' -- "$d" 2>/dev/null \
          | sort | uniq -c | sort -rn | head -3 | awk '{$1=$1};1' | paste -sd '; ' -)
    [ -n "$out" ] && printf '  %-30s %s\n' "$d" "$out"
  done

  hr "RECENT COMMIT SUBJECTS (last 15) — reveals current workstream"
  git log -15 --format='  %as  %an: %s' 2>/dev/null
fi

hr "TODO / FIXME / HACK DENSITY"
for pat in TODO FIXME HACK XXX DEPRECATED; do
  # shellcheck disable=SC2086
  n=$(grep -rF "$pat" --include='*.java' --include='*.kt' --include='*.py' \
      --include='*.ts' --include='*.js' . 2>/dev/null \
      | grep -v '/target/\|/build/\|/node_modules/' | wc -l | tr -d ' ')
  [ "$n" -gt 0 ] && printf '%6s  %s\n' "$n" "$pat"
done

hr "DONE"
echo "Phase 0 complete. Proceed to Phase 1 (build system and dependencies)."
