#!/bin/sh
# Usage: sh scripts/install-terraform.sh <version>
# Installs Terraform into .tools/bin, for jobs whose image has python3 but no Terraform.
set -eu

version=$1

cd "$(dirname "$0")/.."
bin="$(pwd)/.tools/bin"
mkdir -p "$bin"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

wget -qO "$work/terraform.zip" "https://releases.hashicorp.com/terraform/${version}/terraform_${version}_linux_amd64.zip"
unzip -qo "$work/terraform.zip" terraform -d "$bin"
chmod +x "$bin/terraform"
