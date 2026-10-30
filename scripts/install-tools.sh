#!/bin/sh
# Installs the pinned CI tools into .tools/bin (Terraform comes from each platform).
# Plain POSIX sh and wget: the hashicorp/terraform image has no bash or curl.
set -eu

TFLINT_VERSION=0.65.0
TRIVY_VERSION=0.76.1
TERRAFORM_DOCS_VERSION=0.24.0

cd "$(dirname "$0")/.."
bin="$(pwd)/.tools/bin"
mkdir -p "$bin"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

wget -qO "$work/tflint.zip" "https://github.com/terraform-linters/tflint/releases/download/v${TFLINT_VERSION}/tflint_linux_amd64.zip"
unzip -qo "$work/tflint.zip" tflint -d "$bin"

wget -qO "$work/trivy.tar.gz" "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz"
tar -xzf "$work/trivy.tar.gz" -C "$bin" trivy

wget -qO "$work/terraform-docs.tar.gz" "https://github.com/terraform-docs/terraform-docs/releases/download/v${TERRAFORM_DOCS_VERSION}/terraform-docs-v${TERRAFORM_DOCS_VERSION}-linux-amd64.tar.gz"
tar -xzf "$work/terraform-docs.tar.gz" -C "$bin" terraform-docs

chmod +x "$bin/tflint" "$bin/trivy" "$bin/terraform-docs"
