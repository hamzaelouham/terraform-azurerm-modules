# terraform-azurerm-modules - Project Overview

<!-- blueprint:source-hash 8315bb715d18b5ddb44ad941a99a7bd62585b82549784192b2cd5071a8b6ae71 -->

> A public library of reusable, versioned Terraform modules for Azure.

## Problem

Teams deploying to Azure keep rewriting the same Terraform for resource groups,
networks, key vaults, identities and VMs, each with different naming, tagging and
security defaults. This library gives them tested building blocks with secure
defaults to compose instead.

## Users

- **Engineers** writing Terraform root stacks for Azure; they consume the modules
  by source reference and pass their own provider configuration.

## Usage model

- Public library.
- Module CI never runs `apply` and has no Azure credentials.
- `examples/` stacks are local only and never pushed; tracked files must not reference them.

## Features

In build order. Headline: `virtual-machine`, the module that composes the others.
Next: `aks`.

1. [x] **resource-group** - resource group with tags and `prevent_destroy`.
2. [x] **vnet** - virtual network, subnets (service endpoints, NSG association), one NSG with rules.
3. [x] **key-vault** - RBAC key vault, purge protection, optional access policies and network ACLs.
4. [x] **service-principal** - Entra ID app and service principal, OIDC federated credentials, optional rotating secret.
5. [x] **virtual-machine** - Linux or Windows VM with NIC, optional public IP, static/dynamic private IP, data disks (incl. Ultra/PremiumV2), managed identity, OS disk tags, offline tests.
6. [x] **storage-account** - storage account with secure defaults, plus:
   - [x] 6a. **Storage account core** - optional network rules and blob data protection, blob containers, file shares.
   - [x] 6b. **Storage account private endpoint** - optional blob private endpoint into a vnet subnet.
7. [ ] **aks** - fill the empty `modules/aks`:
   - [ ] 7a. **AKS core cluster** - private by default, system node pool, Azure CNI Overlay, Entra ID RBAC with local accounts off; optional workload identity, ACR pull, Container Insights, Key Vault secrets CSI.
   - [ ] 7b. **AKS user node pools** - optional extra user node pools.
8. [ ] **AI azurerm upgrade agent** - when the monthly check finds a new azurerm version, propose module changes in a draft PR for human review.

## Data model

No application data: modules create Azure resources, and state lives in each
consumer's backend. Secrets (VM admin password, SP client secret) pass only
through `sensitive` variables and outputs and are never committed.

The contracts that matter are how modules compose. These are locked: later
modules must follow them.

### Composition contract

| From | Output | Into | Input |
|---|---|---|---|
| resource-group | `name` | vnet, key-vault, virtual-machine, storage-account, aks | `resource_group_name` |
| resource-group | `location` | vnet, key-vault, virtual-machine, storage-account, aks | `location` |
| vnet | `subnet_ids["<name>"]` | virtual-machine | `subnet_id` |
| vnet | `subnet_ids["<name>"]` | storage-account | `sa_network_rules.virtual_network_subnet_ids`, `sa_private_endpoint.subnet_id` |
| service-principal | `object_id` | role assignments, key-vault `kv_access_policies` | principal / object ID |
| virtual-machine | `identity_principal_id` (null when no system identity) | role assignments | `principal_id` |
| storage-account | `sa_id` | role assignments | scope |
| vnet | `subnet_ids["<name>"]` | aks | `subnet_id` |
| aks | `aks_kubelet_identity_object_id`, `aks_identity_principal_id` (null with user-assigned) | role assignments | `principal_id` |

### Module interface rules

- Files: `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`; optional `README.md`, `tests/`.
- Shared inputs keep plain names (`resource_group_name`, `location`, `subnet_id`, `tenant_id`); module-specific inputs take a prefix (`rg_`, `vnet_`, `nsg_`, `kv_`, `sp_`, `vm_`, `sa_`).
- Inputs Azure would reject fail at plan time (validation or precondition), not at apply.
- Outputs return `null`, never `""`, when a feature is off.

## Tech stack

- **Terraform** - `>= 1.17` in modules; 1.17.0 pinned in CI.
- **azurerm 5.x** - all Azure resources (resource-group also allows 4.x).
- **azapi 2.x** - only where azurerm can't (VM OS disk tags).
- **azuread 3.x + time** - service-principal.
- **`terraform test` with mocked providers** - offline module tests.
- **GitHub** - `hamzaelouham/terraform-azurerm-modules`.
- **CI tools** - tflint 0.65.0, tflint-ruleset-azurerm 0.33.0, trivy 0.76.1, terraform-docs 0.24.0.
- **CI on four platforms** (GitHub Actions, GitLab CI, Jenkins, Azure Pipelines) - one pipeline, `sh scripts/verify.sh`: `terraform fmt`, init + validate, tflint, trivy (HIGH, CRITICAL), terraform-docs, then `terraform test` where a module has tests. Written, not yet run on any of them.
- **azurerm update check** - monthly `scripts/check-registry.py` on all four platforms, compared with `.azurerm-reviewed-version`.
- **AI upgrade agent (GitHub only)** - custom Python agent in `ai-agent/`, built on LangGraph and LangChain, using any OpenAI-compatible model through an `OPENAI_API_KEY` repo secret, with step and token limits.

## Monetization

Not applicable: a public module library.

## UI/UX

No UI. The interface is each module's inputs and outputs: prefixed, described,
validated variables that fail at plan time rather than at apply, and secure
defaults (no public IP, SSH keys only on Linux, purge protection on).

## Deployment

Each module is versioned independently with git tags and consumed by a separate
live-infra repo through `?ref=<module>/vX.Y.Z`. Nothing deploys from this repo.
Changes are recorded in `CHANGELOG.md` (Keep a Changelog, `## [Unreleased]`).
The AI upgrade agent only opens draft PRs: a person reviews and merges them, and
still creates every release tag.

## Open questions

> Resolve these in the plans, then re-run /overview.

- **`service-principal` isn't in the module list you supplied.** It's shipped and stays listed here; confirm it stays in the library.
- **Release pipeline is unplanned.** Modules are released by git tag, but neither plan says how tags are created or what runs on them.
- **CI has no build-plan item.** The project plan names the pipeline, but nothing on the build plan tracks it.
- **Testing gap.** `AGENTS.md` declares a test gate, but only virtual-machine and storage-account have tests; the other four modules have none.
- **Provider pin mismatch.** resource-group allows azurerm `>= 4.0`, while the other modules and the coding standards say 5.x.
- **Build-plan wording.** Item 6 still reads "fill the empty `modules/storage-account`", though it's complete.
