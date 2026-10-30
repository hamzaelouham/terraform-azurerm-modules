#!/bin/sh
# Usage: sh scripts/trivy-scan.sh <LOW|MEDIUM|HIGH|CRITICAL> [module]
# Fails on findings at that severity or above, so new HIGH or CRITICAL rules can't
# slip past a MEDIUM gate. Scans every module unless one is named. Uses the latest rules.
set -u

case "${1:-}" in
  LOW) severities=LOW,MEDIUM,HIGH,CRITICAL ;;
  MEDIUM) severities=MEDIUM,HIGH,CRITICAL ;;
  HIGH) severities=HIGH,CRITICAL ;;
  CRITICAL) severities=CRITICAL ;;
  *)
    echo "Usage: sh scripts/trivy-scan.sh <LOW|MEDIUM|HIGH|CRITICAL> [module]" >&2
    exit 2
    ;;
esac
only=${2:-}

cd "$(dirname "$0")/.."
root=$(pwd)
PATH="$root/.tools/bin:$PATH"

failures=""
for dir in modules/*/; do
  dir=${dir%/}
  [ -z "$only" ] || [ "$dir" = "modules/$only" ] || continue
  set -- "$dir"/*.tf
  [ -e "$1" ] || continue

  echo "=== $dir"
  if ! trivy config --severity "$severities" --exit-code 1 --ignorefile "$root/.trivyignore" "$dir"; then
    failures="$failures  $dir
"
  fi
done

if [ -n "$failures" ]; then
  printf '\nFindings in:\n%s' "$failures"
  exit 1
fi
echo "No findings."
