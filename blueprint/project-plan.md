# Project Plan

> Seeded by `/adopt` from the existing code and a short interview. Sections 3 and
> 5 describe what already exists. Correct anything marked `TODO (confirm)`, then
> run `/overview`.

## 1. Problem - What problem are we solving?

Teams deploying to Azure keep rewriting the same Terraform for resource groups,
networks, key vaults, identities and VMs, each time with slightly different
naming, tagging and security defaults. This repo is a shared library of
reusable azurerm modules so team stacks can compose tested building blocks with
secure defaults instead of copying resources around.

## 2. Users - Who is this for?

Engineers on a team who write Terraform stacks for Azure and consume these
modules from their own root configurations.

> TODO (confirm): which team(s) consume it, and whether external users are expected.

## 3. Features - What does the MVP need?

Shipped (present in the repo):

- `resource-group` - resource group with tags and `prevent_destroy`
- `vnet` - virtual network, subnets (service endpoints, NSG association), one NSG with rules
- `key-vault` - key vault with RBAC by default, purge protection, optional access policies and network ACLs
- `service-principal` - Entra ID app and service principal, OIDC federated credentials, optional rotating secret
- `virtual-machine` - Linux or Windows VM with NIC, optional public IP, static or dynamic private IP, data disks (incl. Ultra/PremiumV2), managed identity, OS disk tagging

Next:

- `storage-account` module (the folder exists, empty)

## 4. Data - What are we storing?

No application data. Modules create Azure resources; state lives in each
consumer's own Terraform backend. Secrets (VM passwords, SP client secrets)
flow through sensitive variables and outputs and must never be committed.

## 5. Tech - What stack are we using?

- Terraform `>= 1.3` (developed with 1.17)
- Providers: azurerm 5.x (resource-group allows 4.x), azapi 2.x (VM OS disk tags), azuread 3.x and time (service-principal)
- `terraform test` with mocked providers for offline module tests
- Hosted on GitHub: `hamzaelouham/terraform-azurerm-modules`
- CI: the same pipeline is intended on four platforms (GitHub Actions, GitLab CI, Jenkins, Azure Pipelines); all four files are currently empty

## 6. Monetize - How will this make money?

Not applicable: an internal team module library.

## 7. UI/UX - How should this look and feel?

No UI. The "interface" is each module's inputs and outputs: prefixed, described,
validated variables that fail at plan time rather than at apply, and secure
defaults (no public IP, SSH keys only on Linux, purge protection on).

## 8. Deployment - Where and how will this ship?

Modules are consumed by source reference from team stacks; nothing is deployed
from this repo itself. Changes are recorded in `CHANGELOG.md` (Keep a Changelog).

> TODO (confirm): how consumers pin versions (git tags with `?ref=`, a private registry, or another scheme).

## 9. Usage model and constraints (optional)

- Internal team use; consumers are trusted engineers.
- Example stacks under `examples/` are kept local only and are not pushed.
