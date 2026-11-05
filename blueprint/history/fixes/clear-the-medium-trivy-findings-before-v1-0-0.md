# Fix: Clear the MEDIUM Trivy findings before v1.0.0

**Type:** Fix
**Status:** verified
**Branch:** fix/clear-the-medium-trivy-findings-before-v1-0-0

## The problem

The user wants to tag every module at `v1.0.0`. Two modules would fail
`release-check.sh`, because its `trivy-scan.sh MEDIUM <module>` gate fails on them
(checked 2026-11-04 on `6c73b32`):

| Module | Finding | Resource |
|---|---|---|
| `storage-account` | AZU-0061: infrastructure encryption not enabled | `azurerm_storage_account.sa` |
| `storage-account` | AZU-0057: no logging enabled for any service | `azurerm_storage_account.sa` |
| `virtual-machine` | AZU-0068: NIC not associated with a network security group | `azurerm_network_interface.nic` |

The other five modules (`aks`, `key-vault`, `resource-group`, `service-principal`,
`vnet`) already pass the MEDIUM scan.

Probes on scratch copies with azurerm 5.12.0 and Trivy 0.76.1:

| Change | `validate` | MEDIUM scan |
|---|---|---|
| `infrastructure_encryption_enabled = true` on the account | passes | AZU-0061 gone |
| `queue_properties { logging { ... } }` on the account | fails: "Unsupported block type" (removed in azurerm 5.x) | (n/a) |
| `azurerm_storage_account_queue_properties` with `logging` | passes | AZU-0057 still reported: Trivy doesn't recognise it |
| `azurerm_network_interface_security_group_association`, optional or required | passes | AZU-0068 still reported: Trivy only checks a NIC argument azurerm removed |

So AZU-0061 can be fixed in code. AZU-0057 and AZU-0068 can't be cleared in code on
azurerm 5.12, and the user accepted both on 2026-11-04 with the reasons below.

## The fix

**storage-account: fix AZU-0061.**
- Set `infrastructure_encryption_enabled = true` on `azurerm_storage_account.sa`.
  Hard-code it, the way the module already hard-codes `https_traffic_only_enabled`
  and `min_tls_version`. Don't add a variable.
- azurerm allows it for `StorageV2`, and for Premium `BlockBlobStorage` and
  `FileStorage`. Those are exactly the kinds the module accepts.
- Add a test assert that the account plans with it on, in the defaults run.
- README: name it as a default. CHANGELOG: add it to the `storage-account` `Added`
  entry. Changing this setting recreates an account, but no `storage-account/v*` tag
  exists yet, so no caller is affected.

**Accept AZU-0057 and AZU-0068 in `.trivyignore`.** Each entry gets a comment with
the user's reason, as the file's header requires:
- AZU-0057: "Trivy checks queue_properties logging, which azurerm 5.x removed;
  callers send storage logs to Azure Monitor with a diagnostic setting on the
  account."
- AZU-0068: "NSGs are applied at the subnet by the vnet module (associate_nsg
  defaults to true); Trivy only detects a NIC argument azurerm 5.x removed."

The scope these entries cover:
- `.trivyignore` applies to every module. Today only `storage-account` creates
  storage accounts, and only `virtual-machine` creates NICs.
- The entries also hide these two rules from the weekly HIGH scan, but both are
  MEDIUM, so nothing changes there.

**Docs.**
- The `storage-account` README says logging is the caller's diagnostic setting.
- The `virtual-machine` README says the NIC relies on the subnet's NSG from `vnet`.
- Regenerate terraform-docs for both modules.

Must not break: any other default or input of either module, the HIGH and CRITICAL
rule (fix, never ignore), or any test.

## Build steps

- [x] 1. **Infrastructure encryption on, the two acceptances, and docs.**
  - `modules/storage-account/main.tf`.
  - The storage test assert.
  - Both READMEs, regenerated.
  - `CHANGELOG.md`.
  - `.trivyignore`.

  **Done when:**
  - `sh scripts/trivy-scan.sh MEDIUM` prints `No findings.` for all seven modules.
  - `terraform -chdir=modules/storage-account test` passes, with the new assert.
  - `sh scripts/verify.sh` prints `All checks passed.`

## Verify

- `sh scripts/trivy-scan.sh MEDIUM`: `No findings.`, so every module would pass the
  release check's Trivy gate.
- `sh scripts/trivy-scan.sh MEDIUM storage-account` and
  `sh scripts/trivy-scan.sh MEDIUM virtual-machine`: `No findings.`
- `sh scripts/verify.sh`: `All checks passed.`
- After merging, the user tags all seven modules at `v1.0.0`. Each tag's release run
  is the real check.

## Notes for the AI

- Module code under `modules/` is the user's to write by default. Ask at
  `/implement` who writes it.
- Record the two acceptances in `blueprint/context/findings.md` too, as new entries
  with status `accepted`, the user's reason, and the date. Only the user can accept
  a finding; they did so in this chat. The entries archive with this fix.
- Live-only: whether Azure turns on infrastructure encryption for every account
  kind and region the module allows.
- Out of scope:
  - AZU-0066 and AZU-0067 (LOW, `aks`).
  - Adding a diagnostic setting or an NSG association to the modules.
  - The CHANGELOG version heading for the release.


<!-- blueprint:completion {"schemaVersion":2,"specBytes":4936,"specSha256":"fbbbef4d2add29ec5cb3b171303fc0275e06cba5d5c53c99ef5a7ff953a10eef","branch":"refs/heads/fix/clear-the-medium-trivy-findings-before-v1-0-0","head":"eac9cbd7ec61bdf99271f34eec68be0b0172f289","baseRef":"refs/heads/main","baseCommit":"6c73b329801e35370537414e628ab153e7d6e567","sourceTree":"3da6bc904d6a77aa29b772d029eb79fd32717169","landing":"local-merge","absentOptional":[]} -->

## Findings

### clear-the-medium-trivy-findings-before-v1-0-0/F-54 [P3] accepted - storage-account has no storage logging (Trivy AZU-0057, MEDIUM)

**File:** modules/storage-account/main.tf:6
**Found:** 2026-11-04 by the v1.0.0 release readiness scan (`sh scripts/trivy-scan.sh MEDIUM storage-account`)
**Why it matters:** The release check runs the MEDIUM scan, so this blocked tagging `storage-account/v1.0.0`. On azurerm 5.12.0 it can't be cleared in code: the `queue_properties` logging block Trivy looks for fails `validate` ("Unsupported block type"), and the replacement `azurerm_storage_account_queue_properties` resource still leaves AZU-0057 reported (scratch probes).
**Suggested fix:** Accept it, or revisit if Trivy learns the azurerm 5.x resources.
**Resolution:** Accepted 2026-11-04 by the user in chat, reason: "Trivy checks queue_properties logging, which azurerm 5.x removed; callers send storage logs to Azure Monitor with a diagnostic setting on the account." Recorded in `.trivyignore` with that reason; the storage-account README tells callers to add the diagnostic setting.
Re-examined 2026-11-04 by /audit independent (fresh subagent, target eac9cbd): status unchanged. azurerm 5.12.0 docs list no `queue_properties` block on `azurerm_storage_account`; a scratch copy with `azurerm_storage_account_queue_properties` + `logging` passes `validate` and Trivy 0.76.1 still reports AZU-0057. Without `.trivyignore`, AZU-0057 on `azurerm_storage_account.sa` is the only MEDIUM+ result the entry hides across all seven modules; the `.trivyignore` comment matches this reason.

### clear-the-medium-trivy-findings-before-v1-0-0/F-55 [P3] accepted - virtual-machine NIC has no network security group (Trivy AZU-0068, MEDIUM)

**File:** modules/virtual-machine/main.tf:51
**Found:** 2026-11-04 by the v1.0.0 release readiness scan (`sh scripts/trivy-scan.sh MEDIUM virtual-machine`)
**Why it matters:** The release check runs the MEDIUM scan, so this blocked tagging `virtual-machine/v1.0.0`. An optional or required `azurerm_network_interface_security_group_association` passes `validate` but still leaves AZU-0068 reported (scratch probes), so it can't be cleared in code on azurerm 5.12.0.
**Suggested fix:** Accept it, relying on the subnet NSG the vnet module attaches by default.
**Resolution:** Accepted 2026-11-04 by the user in chat, reason: "NSGs are applied at the subnet by the vnet module (associate_nsg defaults to true); Trivy only detects a NIC argument azurerm 5.x removed." Recorded in `.trivyignore` with that reason; the virtual-machine README states the NIC relies on the subnet NSG.
Re-examined 2026-11-04 by /audit independent (fresh subagent, target eac9cbd): status unchanged. A scratch copy with `azurerm_network_interface_security_group_association` on the NIC still reports AZU-0068 on Trivy 0.76.1. `modules/vnet/variables.tf:56` has `associate_nsg = optional(bool, true)`, matching the reason. Without `.trivyignore`, AZU-0068 on `azurerm_network_interface.nic` is the only other MEDIUM+ result hidden; no HIGH or CRITICAL rule is ignored. Note: the subnet NSG only applies when callers use the vnet module's subnet (`subnet_id` accepts any subnet), which the README states.

## Independent review

# Independent Review

**Status:** passed
**Target commit:** eac9cbd7ec61bdf99271f34eec68be0b0172f289
**Base commit:** 6c73b329801e35370537414e628ab153e7d6e567
**Base ref:** main
**Spec hash:** fbbbef4d2add29ec5cb3b171303fc0275e06cba5d5c53c99ef5a7ff953a10eef
**Prepared by:** claude
**Builder model:** claude-opus-5-5
**Requested reviewer:** claude
**Requested model:** claude-opus-5-5
**Requested execution:** automatic
**Requested at:** 2026-11-04T23:49:59Z
**Workflow:** regular
**Check required:** no
**Reviewer adapter:** claude
**Reviewer model:** claude-opus-5-5
**Reviewer context:** fresh subagent
**Actual execution:** automatic
**Reviewed at:** 2026-11-04T23:57:30Z
**Scope:** current
**Lenses:** quality, security, performance, tests
**Verdict:** passed
**Check result:** not-required

## Handoff

Review the active spec and the complete `6c73b329801e35370537414e628ab153e7d6e567..eac9cbd7ec61bdf99271f34eec68be0b0172f289` delta in a fresh
session or isolated subagent without the builder conversation. Run all Audit lenses from scratch.
Run Check when required above. Do not edit product code, accept findings, or
reuse the existing findings as the review scope.

## Commands

- `git rev-parse HEAD` / `git merge-base main HEAD` / `sha256sum blueprint/context/current-feature.md` / `git status --porcelain`: pass (match target, base, spec hash; only review.md and findings.md differ)
- `terraform init -backend=false && terraform validate && terraform test` on a scratch copy of `modules/storage-account` at the target: pass (42 passed)
- `terraform test` on a scratch copy with `infrastructure_encryption_enabled = true` removed: fails `defaults_are_secure` as expected (assert is effective)
- `sh scripts/trivy-scan.sh MEDIUM`: pass (No findings, all seven modules)
- `sh scripts/trivy-scan.sh HIGH`: pass (No findings)
- `trivy config --severity MEDIUM,HIGH,CRITICAL` per module with an empty ignore file: only AZU-0057 (storage-account) and AZU-0068 (virtual-machine), both MEDIUM
- Trivy probe, scratch storage-account + `azurerm_storage_account_queue_properties` with `logging` (`validate` passes): AZU-0057 still reported
- Trivy probe, scratch virtual-machine + `azurerm_network_interface_security_group_association`: AZU-0068 still reported
- `sh scripts/verify.sh` (fmt, init, validate, tflint, trivy, terraform-docs, test for every module): pass (All checks passed)

## Evidence

- `modules/storage-account/main.tf:16` hard-codes `infrastructure_encryption_enabled = true`. The azurerm 5.12.0 docs allow `true` when `account_kind` is `StorageV2`, or Premium with `BlockBlobStorage`/`FileStorage`; `variables.tf:32-41` accepts only those three kinds, and the `main.tf:58-61` precondition requires Premium for the latter two, so every accepted combination is valid.
- The setting is ForceNew; no `storage-account/v*` tag exists yet, as the spec and CHANGELOG state.
- azurerm 5.12.0 `azurerm_storage_account` docs have no `queue_properties` block, confirming spec claim (b) for AZU-0057.
- `.trivyignore` adds only AZU-0057 and AZU-0068, each with a dated, specific reason that matches F-54/F-55 and the spec. The ignore file is global, but scanning without it shows these IDs hide nothing in the other five modules, and no HIGH/CRITICAL rule is ignored.
- `modules/vnet/variables.tf:56` `associate_nsg = optional(bool, true)` matches the AZU-0068 reason and the virtual-machine README note.
- README defaults/notes and the CHANGELOG `storage-account` entry match the code; terraform-docs check passes in verify.
- Performance lens: no runtime or loop changes; nothing to report.
- F-54/F-55 user acceptance happened in the builder chat and cannot be verified here; the recorded reasons are present, specific and consistent. Both entries are uncommitted ledger edits at review time.

## Findings

- F-56 [P3] open: the `defaults_are_secure` error message does not mention infrastructure encryption
- F-54, F-55 (P3, accepted by the user): re-examined, status unchanged; re-examination notes added

## Remaining risk

- Live-only: whether Azure accepts infrastructure encryption for every kind/region combination the module allows was not tested against a real subscription (tests use mocked providers).
- `.trivyignore` entries are global and have no expiry; a future module that creates storage accounts or NICs would have AZU-0057/AZU-0068 suppressed silently. Revisit when a new module adds those resources or when Trivy learns the azurerm 5.x resources.
- The subnet NSG behind AZU-0068 applies only when callers use the vnet module's subnet with `associate_nsg` left on; the virtual-machine module accepts any `subnet_id`.

## Try it now

1. Run `sh scripts/trivy-scan.sh MEDIUM`. Expect `No findings.` for every module.
2. Run `grep -B3 AZU- .trivyignore`. Expect each ID with its reason comment.
