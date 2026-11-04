#!/bin/sh
# Usage: sh scripts/check-bot-patch.sh <patch>
# The gate between the AI agent and the repo. Passes only regular text files under
# modules/, and never applies anything. An empty patch passes: no changes were needed.
set -u

case "${1:-}" in
  "")
    echo "Usage: sh scripts/check-bot-patch.sh <patch>" >&2
    exit 2
    ;;
  /*) patch=$1 ;;
  *) patch="$(pwd)/$1" ;;
esac
[ -f "$patch" ] || {
  echo "No such patch: $patch" >&2
  exit 2
}

# Run from the root: inside a subfolder, git apply silently skips paths outside it.
cd "$(dirname "$0")/.."

[ -s "$patch" ] || {
  echo "Empty patch."
  exit 0
}

reject() {
  echo "Rejected: $1" >&2
  exit 1
}

# File modes only appear in these header lines. Hunk lines always start with +, - or a space.
if grep -Eq '^(index [0-9a-f]+\.\.[0-9a-f]+ (120000|160000)|(new file|deleted file|old|new) mode (120000|160000))' "$patch"; then
  reject "symlink or submodule"
fi

numstat=$(git apply --numstat "$patch") || reject "git can't read this patch"
summary=$(git apply --summary "$patch") || reject "git can't read this patch"
[ -n "$numstat" ] || reject "patch has content but changes no files"

tab=$(printf '\t')
while IFS="$tab" read -r added _ path; do
  [ "$added" != "-" ] || reject "binary file: $path"
  # Renames show as "a => b", and unusual names arrive quoted; neither starts plainly with modules/.
  case "$path" in
    *" => "* | *"{"*) reject "rename: $path" ;;
    modules/*) ;;
    *) reject "outside modules/: $path" ;;
  esac
  case "/$path/" in
    */../* | */./* | */.*/*) reject "unsafe or hidden path: $path" ;;
  esac
done <<EOF
$numstat
EOF

# Only new and deleted regular files may appear here; mode changes, renames and copies can't.
if [ -n "$summary" ]; then
  unexpected=$(printf '%s\n' "$summary" | grep -Ev '^ (create|delete) mode 100644 ')
  [ -z "$unexpected" ] || reject "$unexpected"
fi

echo "Patch accepted."
