# Project Plan

> Seeded by `/adopt` from the existing code and a short interview. Sections 3 and
> 5 describe what already exists. Correct anything marked `TODO (confirm)`, then
> run `/overview`.

## 1. Problem - What problem are we solving?

Teams deploying to Azure keep rewriting the same Terraform for resource groups,
networks, key vaults, identities and VMs, each time with slightly different
naming, tagging and security defaults. This repo is a public library of
reusable, versioned azurerm modules so stacks can compose tested building blocks
with secure defaults instead of copying resources around.

## 2. Users - Who is this for?

Engineers who write Terraform stacks for Azure and consume these modules from
their own root configurations.

## 3. Features - What does the MVP need?

Shipped (present in the repo):

- `resource-group` - resource group with tags and `prevent_destroy`
- `vnet` - virtual network, subnets (service endpoints, NSG association), one NSG with rules
- `key-vault` - key vault with RBAC by default, purge protection, optional access policies and network ACLs
- `service-principal` - Entra ID app and service principal, OIDC federated credentials, optional rotating secret
- `virtual-machine` - Linux or Windows VM with NIC, optional public IP, static or dynamic private IP, data disks (incl. Ultra/PremiumV2), managed identity, OS disk tagging
- `storage-account` - storage account with secure defaults, optional network rules and blob data protection, blob containers, file shares, optional blob private endpoint

Next:

- `aks` module (the folder exists, empty)

## 4. Data - What are we storing?

No application data. Modules create Azure resources; state lives in each
consumer's own Terraform backend. Secrets (VM passwords, SP client secrets)
flow through sensitive variables and outputs and must never be committed.

## 5. Tech - What stack are we using?

- Terraform `>= 1.17` in modules; 1.17.0 pinned in CI
- Providers: azurerm 5.x (resource-group allows 4.x), azapi 2.x (VM OS disk tags), azuread 3.x and time (service-principal)
- `terraform test` with mocked providers for offline module tests
- Hosted on GitHub: `hamzaelouham/terraform-azurerm-modules`
- CI tools: tflint 0.65.0, tflint-ruleset-azurerm 0.33.0, trivy 0.76.1, terraform-docs 0.24.0
- CI: `terraform fmt`, init + validate, tflint, trivy (HIGH, CRITICAL), terraform-docs, then `terraform test` where a module has tests; the same pipeline (`sh scripts/verify.sh`) on four platforms (GitHub Actions, GitLab CI, Jenkins, Azure Pipelines); written, not yet run on any of them

## 6. Monetize - How will this make money?

Not applicable: a public module library.

## 7. UI/UX - How should this look and feel?

No UI. The "interface" is each module's inputs and outputs: prefixed, described,
validated variables that fail at plan time rather than at apply, and secure
defaults (no public IP, SSH keys only on Linux, purge protection on).

## 8. Deployment - Where and how will this ship?

Each module is versioned independently with git tags and consumed by a separate
live-infra repo through `?ref=<module>/vX.Y.Z`; nothing is deployed from this repo
itself. Changes are recorded in `CHANGELOG.md` (Keep a Changelog).

## 9. Usage model and constraints (optional)

- Public library.
- Module CI never runs `apply` and has no Azure credentials.
- Example stacks under `examples/` are kept local only and are not pushed.
