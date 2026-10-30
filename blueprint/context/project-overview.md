# terraform-azurerm-modules - Project Overview

<!-- blueprint:source-hash 4c081c2df806511918112cb3235d75c68c35d116dee7254d7794caf5c55a006d -->

> A shared library of reusable Terraform modules for Azure, consumed by team stacks.

## Problem

Teams deploying to Azure keep rewriting the same Terraform for resource groups,
networks, key vaults, identities and VMs, each with different naming, tagging and
security defaults. This library gives them tested building blocks with secure
defaults to compose instead.

## Users

- **Team engineers** writing Terraform root stacks for Azure; they consume the
  modules by source reference and pass their own provider configuration.

> TODO: which teams consume it, and whether external users are expected.

## Usage model

- Internal team use; consumers are trusted engineers.
- `examples/` stacks are local only and never pushed; tracked files must not reference them.

## Features

In build order. Headline: `virtual-machine`, the module that composes the others.

1. [x] **resource-group** - resource group with tags and `prevent_destroy`.
2. [x] **vnet** - virtual network, subnets (service endpoints, NSG association), one NSG with rules.
3. [x] **key-vault** - RBAC key vault, purge protection, optional access policies and network ACLs.
4. [x] **service-principal** - Entra ID app and service principal, OIDC federated credentials, optional rotating secret.
5. [x] **virtual-machine** - Linux or Windows VM with NIC, optional public IP, static/dynamic private IP, data disks (incl. Ultra/PremiumV2), managed identity, OS disk tags, offline tests.
6. [ ] **storage-account** - next; `modules/storage-account` exists but is empty.

## Data model

No application data: modules create Azure resources, and state lives in each
consumer's backend. Secrets (VM admin password, SP client secret) pass only
through `sensitive` variables and outputs and are never committed.

The contracts that matter are how modules compose. These are locked: later
modules (storage-account included) must follow them.

### Composition contract

| From | Output | Into | Input |
|---|---|---|---|
| resource-group | `name` | vnet, key-vault, virtual-machine | `resource_group_name` |
| resource-group | `location` | vnet, key-vault, virtual-machine | `location` |
| vnet | `subnet_ids["<name>"]` | virtual-machine | `subnet_id` |
| service-principal | `object_id` | role assignments, key-vault `kv_access_policies` | principal / object ID |
| virtual-machine | `identity_principal_id` (null when no system identity) | role assignments | `principal_id` |

### Module interface rules

- Files: `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`; optional `README.md`, `tests/`.
- Shared inputs keep plain names (`resource_group_name`, `location`, `subnet_id`, `tenant_id`); module-specific inputs take a prefix (`rg_`, `vnet_`, `nsg_`, `kv_`, `sp_`, `vm_`).
- Inputs Azure would reject fail at plan time (validation or precondition), not at apply.
- Outputs return `null`, never `""`, when a feature is off.

## Tech stack

- **Terraform `>= 1.3`** - language floor for consumers (developed on 1.17).
- **azurerm 5.x** - all Azure resources (resource-group also allows 4.x).
- **azapi 2.x** - only where azurerm can't (VM OS disk tags).
- **azuread 3.x + time** - service-principal.
- **`terraform test` with mocked providers** - offline module tests.
- **GitHub** - `hamzaelouham/terraform-azurerm-modules`.
- **CI on four platforms** (GitHub Actions, GitLab CI, Jenkins, Azure Pipelines) - intended; all four files are empty.

## Monetization

Not applicable: internal team module library.

## UI/UX

No UI. The interface is each module's inputs and outputs: prefixed, described,
validated variables and secure defaults (no public IP, SSH keys only on Linux,
purge protection on).

## Deployment

Nothing deploys from this repo; team stacks consume the modules. Changes are
recorded in `CHANGELOG.md` (Keep a Changelog, `## [Unreleased]`).

> TODO: how consumers pin versions (git tags with `?ref=`, a private registry, or another scheme).

## Open questions

> Resolve these in the plans, then re-run /overview.

- **Consumers and version pinning** - the two `TODO (confirm)` items in `project-plan.md` (sections 2 and 8).
- **CI has no build-plan item.** The plan says one pipeline should run on four platforms, but all four files are empty and nothing on the build plan delivers them.
- **`modules/aks` isn't in either plan.** The folder exists but is empty; add it to the build plan or remove the folder.
- **Testing gap.** `AGENTS.md` declares a test gate, but only virtual-machine has tests; the other four shipped modules have none.
- **Provider pin mismatch.** resource-group allows azurerm `>= 4.0`, while the other modules and the coding standards say 5.x.
- **"Shipped" isn't committed.** Only resource-group is in git; vnet, key-vault, service-principal and virtual-machine exist only in the working tree.
