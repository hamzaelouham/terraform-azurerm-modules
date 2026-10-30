# Feature: Storage account core

**From build-plan:** feature 6a
**Build attempt:** 1
**Branch:** feature/storage-account-core
**Status:** verified

## Goal

Turn `modules/storage-account` into a reusable module that creates one storage
account with secure defaults, optional network rules, opt-in blob data
protection, and blob containers and file shares from maps. Callers compose it
like the other modules (`module.rg.name`, `module.rg.location`,
`module.vnet.subnet_ids`).

## In scope

- Storage account: name, tier, kind, replication, access tier, tags.
- Fixed secure settings (no variable): `https_traffic_only_enabled = true`,
  `min_tls_version = "TLS1_2"`.
- Secure defaults with a variable: public blob/container access off
  (`sa_allow_nested_items_to_be_public = false`).
- Azure defaults kept, per your answers: shared key auth on
  (`sa_shared_access_key_enabled = true`), public network access on, and no
  network rules unless `sa_network_rules` is set (same as key-vault).
- Blob data protection off by default; `sa_blob_properties` opts in to
  versioning and blob/container soft delete.
- `sa_containers` map (name -> access type) and `sa_file_shares` map
  (name -> quota GB, access tier).
- Plan-time validation of everything Azure would reject at apply (below).
- Outputs, module README, CHANGELOG entry, mocked `terraform test` suite.

## Out of scope

- Private endpoint and private DNS (feature 6b).
- Access key / connection string outputs, customer-managed keys, managed
  identity, queues, tables, static website, SFTP, NFS, Data Lake (HNS),
  lifecycle management rules, large file shares (quota over 5120 GB).
- `examples/` stacks (local only, never referenced from tracked files).

## Build loop

- `workflow.stepReview = "feature"`: implement all steps, then stop once for a
  whole-feature review. `workflow.checkpointCommits = "disabled"`: no commits
  during the build; `/complete` creates the single feature commit.
- Work on branch `feature/storage-account-core`, created from `main`.
- The untracked draft in `modules/storage-account/` (docs example with
  `azurerm_resource_group.example`, hard-coded tier, IP and tags) is the starting
  point and gets replaced, not kept.
- After each step: `terraform fmt -check -recursive`, then `init -backend=false`,
  `validate` and `test` in `modules/storage-account`. If `init` stalls on the
  azurerm download, reuse an already-downloaded provider with `-plugin-dir`.

## Build steps

- [x] **1. Account with secure defaults.** Replace the draft: `azurerm_storage_account.sa`
  using `var.resource_group_name` and `var.location`; variables `sa_name`,
  `sa_account_tier`, `sa_account_kind`, `sa_replication_type`, `sa_access_tier`,
  `sa_shared_access_key_enabled`, `sa_public_network_access_enabled`,
  `sa_allow_nested_items_to_be_public`, `sa_tags`; `versions.tf` drops azapi
  (unused here). Outputs `sa_id`, `sa_name`, `sa_primary_blob_endpoint`,
  `sa_primary_file_endpoint`. Check in the 5.12 schema whether
  `public_network_access_enabled` is deprecated in favour of
  `public_network_access`, and use the non-deprecated one.
  **Done when:** `validate` passes, a test plan with only required inputs shows
  one account with TLS1_2, HTTPS only, nested public access off and shared key
  on, and tests reject a bad `sa_name` and Premium + GRS.
- [x] **2. Network rules and blob data protection.** Dynamic `network_rules` from
  `sa_network_rules` (null = no block) and dynamic `blob_properties` from
  `sa_blob_properties` (null = no block).
  **Done when:** tests show no `network_rules` block by default, Deny + subnet +
  IP when set, and reject a private-range IP, a `/32` CIDR, and an out-of-range
  retention.
- [x] **3. Containers and file shares.** `azurerm_storage_container.container`
  and `azurerm_storage_share.share` with `for_each` over the maps and
  `storage_account_id = azurerm_storage_account.sa.id`; outputs
  `container_ids`, `file_share_ids`; cross-variable preconditions on the account.
  **Done when:** tests show containers/shares planned with the right names,
  access types and quotas, and reject: a bad container/share name, a public
  container while `sa_allow_nested_items_to_be_public = false`, containers on
  `FileStorage`, shares on `BlockBlobStorage`.
- [x] **4. Docs.** `modules/storage-account/README.md` (usage snippet, secure
  defaults, the shared-key and network notes) and a `CHANGELOG.md` `Added`
  entry under `[Unreleased]`.
  **Done when:** full test suite green, `fmt -check` clean, README has no link
  into `examples/`.
- [x] **5. Review repairs (F-01, F-03, F-04).** F-01: IP rules are rejected
  when they overlap a private range in either direction (e.g. `172.0.0.0/8`,
  `0.0.0.0/0`). F-03: account precondition that shares on `FileStorage` use
  access_tier `Premium` (or null) with quota_gb of at least 100, and other
  accounts don't use `Premium`. F-04: rejecting tests for `bypass`,
  `default_action`, container `access_type` and share `access_tier`. F-02
  (access tier ignored for BlockBlobStorage) is left as is by your decision.
  **Done when:** rejecting tests for each pass and the full suite is green.
- [x] **6. Independent review repairs (F-05, F-06, F-07).** F-05: account
  precondition that `FileStorage` accounts can't set `sa_blob_properties`. F-06:
  tests for an unknown `bypass` value, IP rules beside private ranges being
  accepted, `sa_tags`, and the `container_ids` and `file_share_ids` outputs.
  F-07: this spec's contract matches the code for access tier and share rules.
  F-08 and F-09 stay unverified; they need Azure docs or a live plan.
  **Done when:** the new tests pass and the full suite is green.
- [x] **7. Terraform floor raised to 1.17 (your request).** Every module sets
  `required_version = ">= 1.17"`; coding standards and `CHANGELOG.md` (`Breaking`)
  say so; the two comments justifying preconditions by Terraform < 1.9 are removed.
  Preconditions stay where they are. `project-plan.md` and the overview still say
  `>= 1.3` until you update the plan and re-run `/overview`.
  **Done when:** all six `versions.tf` files read `>= 1.17` and `fmt` is clean.

## Files / areas

- `modules/storage-account/main.tf`, `variables.tf`, `outputs.tf`, `versions.tf` (replace the draft)
- `modules/storage-account/tests/storage.tftest.hcl` (new)
- `modules/storage-account/README.md` (new)
- `CHANGELOG.md`

## Data / contracts

Inputs (shared names unprefixed, the rest `sa_`):

| Input | Type / default | Validation |
|---|---|---|
| `resource_group_name` | string | - |
| `location` | string | none; passed to the provider |
| `sa_name` | string | 3-24 lowercase letters and digits (globally unique; Azure checks uniqueness) |
| `sa_account_tier` | `"Standard"` | Standard, Premium |
| `sa_account_kind` | `"StorageV2"` | StorageV2, BlockBlobStorage, FileStorage |
| `sa_replication_type` | `"LRS"` | LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS |
| `sa_access_tier` | `"Hot"` | Hot, Cool, Cold |
| `sa_shared_access_key_enabled` | `true`, nullable = false | - |
| `sa_public_network_access_enabled` | `true`, nullable = false | - |
| `sa_allow_nested_items_to_be_public` | `false`, nullable = false | - |
| `sa_network_rules` | object, default null | `default_action` Allow/Deny (default Deny); `bypass` subset of AzureServices, Logging, Metrics, None (default `["AzureServices"]`); `ip_rules` public IPv4 or CIDR with prefix /30 or wider, none in 10/8, 172.16/12, 192.168/16; `virtual_network_subnet_ids` list |
| `sa_blob_properties` | object, default null | `versioning_enabled` (bool, false); `delete_retention_days`, `container_delete_retention_days` (null or whole number 1-365) |
| `sa_containers` | map(object({ access_type = optional(string, "private") })), `{}` | key: 3-63 of lowercase letters, digits, `-`; starts and ends with a letter or digit; no `--`. access_type private, blob, container |
| `sa_file_shares` | map(object({ quota_gb = number, access_tier = optional(string) })), `{}` | key: same rule as containers; quota_gb whole number 1-5120; access_tier null or TransactionOptimized, Hot, Cool, Premium |
| `sa_tags` | map(string), `{}` | - |

Cross-variable preconditions (on `azurerm_storage_account.sa`, so nothing is created when they fail):

- Premium tier allows only LRS or ZRS replication.
- `BlockBlobStorage` and `FileStorage` require Premium tier.
- `FileStorage` accounts can't have `sa_containers` or `sa_blob_properties`; `BlockBlobStorage` accounts can't have `sa_file_shares`.
- File shares on `FileStorage` use access_tier `Premium` (or null) with quota_gb of at least 100; other accounts can't use `Premium`.
- A container with access_type `blob` or `container` needs `sa_allow_nested_items_to_be_public = true`.

`sa_access_tier` is a local, not a precondition: it applies only to Standard
`StorageV2` accounts and is silently not set on any other tier or kind (F-02, left
as is by your decision).

Outputs: `sa_id`, `sa_name`, `sa_primary_blob_endpoint`, `sa_primary_file_endpoint`,
`container_ids` (map name -> ID), `file_share_ids` (map name -> ID), each with a
description. No secrets are output.

Resource names: `azurerm_storage_account.sa`, `azurerm_storage_container.container`,
`azurerm_storage_share.share`.

## Testing

Test command: `terraform -chdir=modules/storage-account test`, offline with
`mock_provider "azurerm" {}` and `command = plan`. Expected runs:

- defaults plan (secure settings asserted, no network_rules or blob_properties block)
- network rules set; blob properties set
- containers and shares planned with names, access types, quotas
- `expect_failures` on: bad `sa_name`, bad container key, bad share key, quota 0
  and 6000, private-range IP rule, `/32` CIDR, retention 0 and 400, Premium + GRS,
  FileStorage on Standard, containers and blob properties on FileStorage, shares
  on BlockBlobStorage, public container without the allow flag, unknown bypass value
- accepted: IP rules beside private ranges; `sa_tags` on the account
- one `command = apply` run with mock IDs for the `container_ids` and
  `file_share_ids` outputs

Mocked tests show the module's logic, not that Azure accepts the result. No
live plan or apply is part of this feature.

## Notes for the AI

- Follow `blueprint/context/coding-standards.md`: `>= 1.17` language; `coalesce` guards in
  validations of nullable values; `nullable = false` on collections and bools.
- Containers and shares take `storage_account_id` (not `storage_account_name`)
  in azurerm 5.x, so they are managed through ARM: `sa_network_rules` Deny and
  `sa_shared_access_key_enabled = false` don't block Terraform from creating
  them. Say this in the README.
- Mirror the key-vault module for the network-rules shape and wording, except
  storage `bypass` is a list.
- Don't add access-key outputs or a private endpoint; those are out of scope.
- `build-plan.md` now has 6a/6b under feature 6, so the overview fingerprint is
  stale until `/overview` is re-run; this doesn't block the build.


<!-- blueprint:completion {"schemaVersion":2,"specBytes":10992,"specSha256":"b2f2a4ca37adc309b420834f314f3ee331573ed66182cdb43e373010f7909a30","branch":"refs/heads/feature/storage-account-core","head":"74f5080bfae31f5236378d53e4fea2ec13645fcb","baseRef":"refs/heads/main","baseCommit":"9028190b8943846e50bcc504dcc7c9114c74f599","sourceTree":"8b38ba35bf344ce8cee01b906cfc38c72e942e5e","landing":"local-merge","absentOptional":[]} -->

## Findings

### 6a/F-05 [P1] closed - sa_blob_properties on FileStorage passes plan and fails at apply

**File:** modules/storage-account/main.tf:53
**Found:** 2026-10-30 by /audit independent (scope: current; lens: all)
**Why it matters:** `sa_account_tier = "Premium"`, `sa_account_kind = "FileStorage"` and any non-null `sa_blob_properties` plan cleanly (probe run), but the azurerm 5.12.0 binary contains the error "`blob_properties` aren't supported for account kind %q in sku tier %q". This breaks the locked rule that inputs Azure would reject fail at plan time, and the module already treats FileStorage as having no blob service for containers.
**Suggested fix:** Add a precondition on `azurerm_storage_account.sa`: `var.sa_account_kind != "FileStorage" || var.sa_blob_properties == null`, with an `expect_failures` test. Extend the spec's precondition list.
**Resolution:** Precondition added in `main.tf`, `blob_properties_on_filestorage_fail` added, description and spec updated. Closed by the independent review of 74f5080: the precondition is at `main.tf:69-72`, the run plans a Premium FileStorage account with only this rule able to fail, and neutralizing the rule in a scratch copy makes that run fail with "Missing expected failure". BlockBlobStorage with `sa_blob_properties` still plans. No new defect from the repair.

### 6a/F-06 [P3] closed - Tests leave repaired and derived logic without coverage

**File:** modules/storage-account/tests/storage.tftest.hcl:250
**Found:** 2026-10-30 by /audit independent (scope: current; lens: tests)
**Why it matters:** `bypass_none_with_other_fails` exercises only the None clause, so an unknown bypass value is untested. No run accepts an address beside a private range, so the overlap check could start over-rejecting unnoticed. `sa_tags`, `container_ids` and `file_share_ids` have no assertions. Probes of the bypass and adjacent-address cases behaved correctly, so this is a coverage gap, not a defect.
**Suggested fix:** Add a rejecting run for `bypass = ["Foo"]`, an accepting run for `172.32.0.1` and `11.0.0.0/8`, a `sa_tags` assertion, and a `command = apply` run with mock IDs for the two map outputs.
**Resolution:** Added `unknown_bypass_fails`, `ip_rules_beside_private_ranges_are_accepted`, `tags_reach_the_account` and `outputs_map_names_to_ids`. Closed by the independent review of 74f5080: all four runs exist and pass, and scratch mutants of the bypass validation, `tags` and `container_ids` each fail the matching run. Other coverage gaps are a separate finding, F-10.

### 6a/F-07 [P3] closed - Spec contract table disagrees with the shipped access-tier behavior

**File:** blueprint/context/current-feature.md:129
**Found:** 2026-10-30 by /audit independent (scope: current; lens: quality)
**Why it matters:** The contract says `sa_access_tier` applies to `StorageV2` and `BlockBlobStorage`. The code applies it only to Standard `StorageV2` (`main.tf:3`), as step 5 records for F-02. The contract's precondition list also omits the share rule added for F-03. `/complete` would archive the contradiction as the feature's record.
**Suggested fix:** Update the two contract bullets to match the code. This changes the spec hash, so it needs a new request and a fresh review; include it with the F-05 repair.
**Resolution:** Spec contract now matches the code for access tier, share rules and the F-05 precondition. Closed by the independent review of 74f5080: spec lines 142-148 agree with `main.tf:3` and `main.tf:61-79`.

## Independent review

# Independent Review

**Status:** passed
**Target commit:** 74f5080bfae31f5236378d53e4fea2ec13645fcb
**Base commit:** 9028190b8943846e50bcc504dcc7c9114c74f599
**Base ref:** main
**Spec hash:** b2f2a4ca37adc309b420834f314f3ee331573ed66182cdb43e373010f7909a30
**Prepared by:** claude
**Builder model:** claude-opus-5-5
**Requested reviewer:** claude
**Requested model:** runtime default (exact model not known until reviewer starts)
**Requested execution:** automatic
**Requested at:** 2026-10-30T08:06:12Z
**Workflow:** regular
**Check required:** no
**Reviewer adapter:** claude
**Reviewer model:** claude-opus-5-5
**Reviewer context:** fresh subagent
**Actual execution:** automatic
**Reviewed at:** 2026-10-30T08:12:29Z
**Scope:** current
**Lenses:** quality, security, performance, tests
**Verdict:** passed
**Check result:** not-required

## Handoff

Review the active spec and the complete `9028190b8943846e50bcc504dcc7c9114c74f599..74f5080bfae31f5236378d53e4fea2ec13645fcb` delta in a fresh
session or isolated subagent without the builder conversation. Run all Audit lenses from scratch.
Run Check when required above. Do not edit product code, accept findings, or
reuse the existing findings as the review scope.

## Commands

All Terraform commands ran on Terraform 1.17.1 in scratch copies extracted with `git archive` from the target, never in the checkout. `init` used `-backend=false -plugin-dir=examples/linux-vm/.terraform/providers`, which holds azurerm 5.12.0 and azapi 2.13.0.

- `terraform fmt -check -recursive`: pass
- `terraform -chdir=modules/storage-account init` and `validate`: pass
- `terraform -chdir=modules/storage-account test`: pass, 33 passed, 0 failed
- `terraform -chdir=modules/virtual-machine init` and `validate`: pass
- `terraform -chdir=modules/virtual-machine test`: pass, 14 passed, 0 failed
- `terraform -chdir=modules/key-vault init` and `validate`: pass
- `terraform -chdir=modules/resource-group init` and `validate`: pass
- `terraform -chdir=modules/vnet init` and `validate`: pass
- `terraform -chdir=modules/service-principal init` and `validate`: unavailable, the mirror lacks `hashicorp/time` and `hashicorp/azuread`
- `terraform providers schema -json` in `modules/storage-account`: pass
- Scratch mutation runs of `terraform test` on `modules/storage-account`: 30 mutants for coverage, 6 failed the suite, 24 survived; 4 further mutants of the repaired rules all failed the suite. Two other mutants were discarded, one an invalid expression and one that didn't change the overlap result
- Scratch boundary probes through `terraform test`, one input per run: 40 inputs, results in Evidence

## Evidence

- Request state before and after the review: `HEAD` and merge base match the request, the spec hash matches, and only `blueprint/context/review.md` and `blueprint/context/findings.md` differ from the target. The spec is tracked, so no snapshot applies.
- Reviewed the complete `9028190..74f5080` delta: 16 files, including the whole storage-account module, the floor change in the five other modules, `CHANGELOG.md`, `blueprint/build-plan.md`, the coding standards and the spec.
- Provider schema 5.12.0: `public_network_access_enabled` is deprecated and `public_network_access` is not, so the module uses the right attribute. `queue_properties` and `static_website` no longer exist on the account. Both child resources require `storage_account_id`.
- Provider binary contains the `blob_properties` rejection for account kind and sku tier, which supports F-05.
- Boundary probes: IP overlap edges behave correctly (`172.15.255.255`, `172.32.0.0`, `192.167.255.255`, `192.169.0.0`, `8.0.0.0/7` and `12.0.0.0/6` accepted; `172.16.0.0`, `172.31.255.255`, `192.168.0.1`, `192.0.0.0/8` and `11.0.0.0/7` rejected). `/31`, `256.1.1.1`, IPv6, malformed addresses, fractional retention and quota, and null tiers are rejected. Non-public addresses are accepted (F-12).
- Every module `versions.tf` reads `>= 1.17`. The removed Terraform 1.9 comment is gone and no module references that version. The only `>= 1.3` references left are the spec's own note and the two plan files the spec discloses.
- No tracked lock file, `*.tfvars` or `examples/` path at the target, no link into `examples/`, and no em dash, en dash or ellipsis added in the module, changelog or blueprint delta.
- Performance lens: no finding. The only iteration is over small caller-supplied maps and lists at plan time.

## Findings

- F-05 [P1] closed
- F-06 [P3] closed
- F-07 [P3] closed
- F-10 [P2] open
- F-11 [P3] open
- F-12 [P3] unverified
- F-08 [P2] unverified, F-09 [P3] unverified: carried forward, not blocking

## Remaining risk

- `terraform -chdir=modules/service-principal init`, `validate`: unavailable offline. Its only change in this delta is the `required_version` line.
- No live plan or apply was run, so Azure acceptance is unproven. This leaves F-08, F-09 and F-12 unverified.
- azurerm was checked only at 5.12.0, while the modules allow `>= 5.0`. Whether `public_network_access` exists on every earlier 5.x release is unverified.
- F-10 leaves security toggles and several validation rules without regression protection; their behavior is correct today.
- `blueprint/project-plan.md` and `blueprint/context/project-overview.md` still say Terraform `>= 1.3`, as the spec discloses, until the plan is updated and `/overview` is re-run.
- No Verify command or CI exists, so these results come only from this manual run.

## Try it now

Needs network access to download the provider. It deletes only the ignored
`.terraform` cache, which may hold a stale provider symlink.

```bash
rm -rf modules/storage-account/.terraform
terraform -chdir=modules/storage-account init -backend=false
terraform -chdir=modules/storage-account test
```

Expected final line: `Success! 33 passed, 0 failed.`
