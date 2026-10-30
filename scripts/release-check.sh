#!/bin/sh
# Validates the release tag in RELEASE_TAG, checks that one module, and writes
# release-notes.md (git-ignored). Only reads the repo: it never creates or moves a tag.
set -eu

fail() {
  echo "Release check failed: $1" >&2
  exit 1
}

cd "$(dirname "$0")/.."

tag=${RELEASE_TAG:-}
case "$tag" in
  *[!a-z0-9./-]*) fail "the tag has characters outside <module>/vX.Y.Z" ;;
esac
printf '%s\n' "$tag" | grep -Eq '^[a-z0-9-]+/v[0-9]+\.[0-9]+\.[0-9]+$' ||
  fail "the tag must look like <module>/vX.Y.Z"
module=${tag%/v*}

set -- "modules/$module"/*.tf
[ -e "$1" ] || fail "modules/$module doesn't exist or has no Terraform files"

git fetch --quiet --tags origin +refs/heads/main:refs/remotes/origin/main
commit=$(git rev-parse "refs/tags/$tag^{commit}")
git merge-base --is-ancestor "$commit" origin/main ||
  fail "$tag points at a commit that isn't on main"

sh scripts/verify.sh "$module"
sh scripts/trivy-scan.sh MEDIUM "$module"

previous=$(git tag --list "$module/v*" --sort=-v:refname --merged "$commit" | grep -Fxv "$tag" | head -n 1 || true)
range=$commit
[ -z "$previous" ] || range="$previous..$commit"

{
  echo "## $tag"
  echo
  if [ -n "$previous" ]; then
    echo "Changes since \`$previous\`:"
  else
    echo "First release of this module."
  fi
  echo
  git log --format='- %h %s' "$range" -- "modules/$module/"
  echo
  echo '```hcl'
  echo "source = \"git::https://github.com/hamzaelouham/terraform-azurerm-modules.git//modules/$module?ref=$tag\""
  echo '```'
} > release-notes.md
