#!/bin/sh
# Usage: sh scripts/publish-bot-pr.sh <version> <dir with the agent's files>
# Turns the agent's patch into a draft PR. No AI runs here, and this is the only step
# with write access. Never runs code from the patch. Stops before pushing on any problem.
set -eu

version=${1:-}
input=${2:-}
if ! echo "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || [ ! -d "$input" ]; then
  echo "Usage: sh scripts/publish-bot-pr.sh <version> <dir>" >&2
  exit 2
fi
input=$(cd "$input" && pwd)

cd "$(dirname "$0")/.."

# An empty patch alone could mean the agent crashed, so only its description proves it finished.
if [ ! -s "$input/pr-body.md" ]; then
  echo "No pr-body.md: the agent didn't finish, so no PR." >&2
  exit 1
fi
[ -f "$input/agent-patch.diff" ] || {
  echo "No agent-patch.diff, so no PR." >&2
  exit 1
}
sh scripts/check-bot-patch.sh "$input/agent-patch.diff"

# What Verify printed last, or a plain note when it never finished.
verify_summary() {
  if [ ! -f "$1" ]; then
    echo "No result."
  elif grep -q '^All checks passed\.$' "$1"; then
    echo "All checks passed."
  elif grep -q '^Failed checks:$' "$1"; then
    sed -n '/^Failed checks:$/,$p' "$1"
  else
    echo "Verify didn't finish."
  fi
}

branch="bot/azurerm-$version"
git switch -c "$branch"
if [ -s "$input/agent-patch.diff" ]; then
  git apply "$input/agent-patch.diff"
fi
echo "$version" > .azurerm-reviewed-version
git add modules .azurerm-reviewed-version

git -c user.name='github-actions[bot]' \
  -c user.email='41898282+github-actions[bot]@users.noreply.github.com' \
  commit -q -m "chore: review azurerm $version"
git push origin "$branch"

body=$(mktemp)
trap 'rm -f "$body"' EXIT
{
  head -c 60000 "$input/pr-body.md"
  printf '\n\n## Verify, run without the agent\n\nFrom the job that ran the agent, so it is informational only. The CI checks on this PR are the result to trust.\n\n### Before the agent\n\n```text\n'
  verify_summary "$input/verify-baseline.txt"
  printf '```\n\n### After the agent\n\n```text\n'
  verify_summary "$input/verify-final.txt"
  printf '```\n'
} | sed 's/@/\&#64;/g' > "$body" # agent text and module output must not notify anyone

gh pr create --draft --base main --head "$branch" \
  --title "azurerm $version: proposed module changes" --body-file "$body"
