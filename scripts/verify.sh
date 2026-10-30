#!/bin/sh
# Usage: sh scripts/verify.sh [module]
# With a module (release checks), only that module is checked and trivy is left to
# the release's own gate. Plain POSIX sh: the hashicorp/terraform image has no bash.
# No set -e: every module gets checked, and all failures are reported at the end.
set -u

only=${1:-}

cd "$(dirname "$0")/.."
root=$(pwd)
PATH="$root/.tools/bin:$PATH"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Lock files aren't committed here, so without this Terraform ignores the cache
# and downloads the provider again for every module.
export TF_PLUGIN_CACHE_DIR="$root/.tools/plugin-cache"
export TF_PLUGIN_CACHE_MAY_BREAK_DEPENDENCY_LOCK_FILE=true
mkdir -p "$TF_PLUGIN_CACHE_DIR"

failures=""
check() {
  label=$1
  shift
  echo "--- $label"
  if ! "$@"; then
    failures="$failures  $label
"
  fi
}

fmt_target=.
[ -z "$only" ] || fmt_target="modules/$only"
check "fmt" terraform fmt -check -recursive "$fmt_target"
check "tflint plugins" tflint --init --config="$root/.tflint.hcl"

for dir in modules/*/; do
  dir=${dir%/}
  [ -z "$only" ] || [ "$dir" = "modules/$only" ] || continue
  set -- "$dir"/*.tf
  [ -e "$1" ] || continue

  echo "=== $dir"
  # A throwaway data dir gives the same clean start locally as on a CI runner.
  TF_DATA_DIR="$work/$(basename "$dir")"
  export TF_DATA_DIR

  check "$dir: init" terraform -chdir="$dir" init -backend=false -input=false
  check "$dir: validate" terraform -chdir="$dir" validate
  check "$dir: tflint" tflint --chdir="$dir" --config="$root/.tflint.hcl"
  if [ -z "$only" ]; then
    check "$dir: trivy" trivy config --severity HIGH,CRITICAL --exit-code 1 --ignorefile "$root/.trivyignore" "$dir"
  fi
  # README.md is optional, but one that exists must carry current generated docs.
  if [ -f "$dir/README.md" ]; then
    # --lockfile=false: init just wrote a lock file, and reading it would pin provider versions in the docs.
    check "$dir: terraform-docs" terraform-docs markdown table --lockfile=false --output-file README.md --output-mode inject --output-check "$dir"
  fi
  if [ -d "$dir/tests" ]; then
    check "$dir: test" terraform -chdir="$dir" test
  fi
done

if [ -n "$failures" ]; then
  printf '\nFailed checks:\n%s' "$failures"
  exit 1
fi
echo "All checks passed."
