#!/bin/sh
# Usage: sh scripts/publish-bot-pr.sh <version> <dir with the agent's files> [github|azure]
# Turns the agent's patch into a draft PR. No AI runs here, and this is the only step
# with write access. Never runs code from the patch. Stops before pushing on any problem.
# github (the default) uses gh. azure uses the Azure Repos REST API and needs
# SYSTEM_ACCESSTOKEN, SYSTEM_COLLECTIONURI, SYSTEM_TEAMPROJECT and BUILD_REPOSITORY_ID.
set -eu

version=${1:-}
input=${2:-}
platform=${3:-github}
if ! echo "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || [ ! -d "$input" ] ||
  { [ "$platform" != github ] && [ "$platform" != azure ]; }; then
  echo "Usage: sh scripts/publish-bot-pr.sh <version> <dir> [github|azure]" >&2
  exit 2
fi
input=$(cd "$input" && pwd)
if [ "$platform" = azure ]; then
  for name in SYSTEM_ACCESSTOKEN SYSTEM_COLLECTIONURI SYSTEM_TEAMPROJECT BUILD_REPOSITORY_ID; do
    eval "value=\${$name:-}"
    [ -n "$value" ] || {
      echo "$name isn't set, so no PR." >&2
      exit 1
    }
  done
fi

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

if [ "$platform" = azure ]; then
  author_name='Azure Pipelines'
  author_email='azure-pipelines@noreply.dev.azure.com'
else
  author_name='github-actions[bot]'
  author_email='41898282+github-actions[bot]@users.noreply.github.com'
fi
git -c user.name="$author_name" -c user.email="$author_email" \
  commit -q -m "chore: review azurerm $version"
# --force: this only runs when no PR exists for the branch, so an existing branch is left
# over from a run whose PR creation failed. Replacing it lets this run retry the PR.
git push --force origin "$branch"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
body="$work/body.md"
{
  # Escape before cutting: each @ becomes 5 characters, so the cut must come after.
  sed 's/@/\&#64;/g' "$input/pr-body.md" | head -c 60000
  printf '\n\n## Verify, run without the agent\n\nFrom the job that ran the agent, so it is informational only. The CI checks on this PR are the result to trust.\n\n### Before the agent\n\n```text\n'
  verify_summary "$input/verify-baseline.txt"
  printf '```\n\n### After the agent\n\n```text\n'
  verify_summary "$input/verify-final.txt"
  printf '```\n'
} | sed 's/@/\&#64;/g' > "$body" # agent text and module output must not notify anyone

title="azurerm $version: proposed module changes"
if [ "$platform" = github ]; then
  gh pr create --draft --base main --head "$branch" --title "$title" --body-file "$body"
  exit 0
fi

# Azure Repos caps a PR description at 4,000 characters, so the description is the start of
# the proposal and the full text, with both Verify summaries, goes in the first comment.
api=$(python3 -I -c '
import sys, urllib.parse
print(sys.argv[1].rstrip("/") + "/" + urllib.parse.quote(sys.argv[2]) + "/_apis/git/repositories/" + sys.argv[3])
' "$SYSTEM_COLLECTIONURI" "$SYSTEM_TEAMPROJECT" "$BUILD_REPOSITORY_ID")
python3 -I -c '
import json, sys
# errors="ignore": the 60,000-byte cut above can end inside a character.
body = open(sys.argv[1], encoding="utf-8", errors="ignore").read()
note = "\n\n[cut here: the full proposal, with both Verify summaries, is in the first comment]"
def units(text):  # Azure counts .NET string length, which is UTF-16 code units
    return len(text.encode("utf-16-le")) // 2
description = body
if units(body) > 4000:
    description = body[:4000 - units(note)]
    while units(description) + units(note) > 4000:
        description = description[:-1]
    description += note
json.dump({"sourceRefName": "refs/heads/" + sys.argv[2], "targetRefName": "refs/heads/main",
           "title": sys.argv[3], "description": description, "isDraft": True}, open(sys.argv[4], "w"))
json.dump({"comments": [{"parentCommentId": 0, "content": body, "commentType": 1}], "status": 1},
          open(sys.argv[5], "w"))
' "$body" "$branch" "$title" "$work/pr.json" "$work/thread.json"
# A header file keeps the token out of the process list.
printf 'Authorization: Bearer %s\nContent-Type: application/json\n' "$SYSTEM_ACCESSTOKEN" > "$work/headers"

# POSTs <request file> to <url> and saves the answer; on an HTTP error, shows Azure's message.
post() {
  curl -sS --fail-with-body -H "@$work/headers" -X POST --data-binary "@$1" -o "$work/response.json" "$2" || {
    cat "$work/response.json" >&2
    exit 1
  }
}
post "$work/pr.json" "$api/pullrequests?api-version=7.1"
id=$(python3 -I -c 'import json, sys; print(int(json.load(open(sys.argv[1]))["pullRequestId"]))' "$work/response.json")
post "$work/thread.json" "$api/pullRequests/$id/threads?api-version=7.1"
echo "Opened draft PR $id."
