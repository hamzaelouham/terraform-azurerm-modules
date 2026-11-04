# Feature: AKS user node pools

**From build-plan:** feature 7b
**Build attempt:** 1
**Status:** verified
**Branch:** feature/aks-user-node-pools

## Goal

Let callers of `modules/aks` add Linux user node pools for their workloads,
regular or Spot. Each pool autoscales, can sit in its own subnet of the cluster's
vnet, and fails at plan time on inputs Azure would reject. Callers can also reserve
the system pool for system pods once their workloads have user pools to run on.

## In scope

- `azurerm_kubernetes_cluster_node_pool` for each entry of a new
  `aks_user_node_pools` map, keyed by pool name, in `mode = "User"` and
  `os_type = "Linux"`, with the autoscaler always on.
- **Per pool:**
  - VM size and autoscale `min_count`/`max_count` (0 allowed for user pools)
  - zones, OS disk type, Linux OS SKU
  - node labels and taints
  - optional subnet, which defaults to the cluster's `subnet_id`
- **Spot pools:** an optional `spot` object per pool sets `priority = "Spot"`,
  the eviction policy and the max price. The module adds the label and taint
  AKS puts on Spot nodes (`kubernetes.azure.com/scalesetpriority=spot`, taint
  effect `NoSchedule`), so plans don't drift.
- **System pool:** a new `only_critical_addons_enabled` attribute on
  `aks_system_node_pool`, default `false`. `true` taints the system pool with
  `CriticalAddonsOnly`, so only system pods run there.
- A derived `temporary_name_for_rotation` per pool, as on the system pool.
- An `aks_user_node_pool_ids` output, tests, README, CHANGELOG.

## Out of scope

- Windows node pools. The 7a cluster uses the Cilium data plane, which Azure
  supports only on Linux, so the user chose to keep Cilium and drop Windows.
- Fixed-size pools without the autoscaler, GPU/MIG settings, FIPS, host
  encryption, node public IPs, kubelet or Linux OS tuning, pod subnets, max pods,
  capacity reservation, proximity placement, dedicated hosts and per-pool
  Kubernetes versions. Pools follow the cluster's version through its upgrade
  channel.
- Changing anything in 7a beyond the new system-pool attribute.
- Live `plan`/`apply` against Azure.

## Build loop

The user asked Claude to write this feature's module code, as in 7a. Claude checks
every argument against the azurerm 5.12.0 docs and `terraform validate` on
v5.12.0, and the user reviews the result. `workflow.stepReview` is `feature` and
`checkpointCommits` is `disabled`, so the steps run through to one review packet.
`/complete` makes the feature commit.

Narrow check while iterating:
`terraform -chdir=modules/aks init -backend=false && terraform -chdir=modules/aks validate && terraform -chdir=modules/aks test`.
Run `sh scripts/verify.sh` once at the end.

## Build steps

- [x] 1. **Regular user pools.**
  - Add `aks_user_node_pools` (default `{}`) and its validations.
  - Add the `azurerm_kubernetes_cluster_node_pool` resource with `for_each`.
  - Preconditions:
    - a pool's subnet must be in the same vnet as `subnet_id` (moved to the cluster in step 5)
    - no pool may reuse the system pool's name
    - no derived rotation name may equal any pool name, the system pool's rotation
      name or another user pool's rotation name (two names sharing their first 9
      characters would otherwise share one)
  - Add the `aks_user_node_pool_ids` output.

  **Done when:** plan tests show one pool per map entry with the right cluster ID,
  subnet, autoscale counts, labels, taints and `mode = "User"`. No pools are
  created by default. Each validation and precondition has an `expect_failures`
  test.
- [x] 2. **Spot pools.** Add the per-pool `spot` object: `eviction_policy` (default
  `"Delete"`) and `max_price` (default `-1`). Spot pools merge in the Spot label and
  taint, and get no `upgrade_settings`, because Azure doesn't allow surge on Spot.
  **Done when:** a plan test shows a Spot pool with `priority = "Spot"`, the
  defaults, and the merged label and taint added to the caller's own. A regular pool
  shows `Regular` with neither. Bad eviction policies and prices are rejected.
- [x] 3. **System pool reservation.** Add `only_critical_addons_enabled` (optional,
  `false`) to `aks_system_node_pool` and pass it to the default node pool.
  **Done when:** plan tests show `false` by default and `true` when set. The 7a
  tests still pass.
- [x] 4. **Docs.** README usage and notes for user pools, Spot and the system-pool
  opt-in; regenerated terraform-docs; CHANGELOG `[Unreleased]` entry.
  **Done when:** `sh scripts/verify.sh` prints `All checks passed.`

- [x] 5. **Review repairs (F-48 to F-50).** The first review passed with three P3
  findings:
  - F-48: lowercase the subnet IDs before splitting on `/subnets/`.
  - F-49: the same-vnet check moves from each node pool to a precondition on the
    cluster that names every pool outside the vnet. When subnet IDs are only known at
    apply, the check now runs before the cluster is created, so nothing is
    half-created.
  - F-50: the `aks_tags` description includes user pools.

  **Done when:** `rejects_user_pool_subnet_in_another_vnet` expects the failure on
  the cluster, 68 tests pass, and Verify passes. F-48's premise didn't hold: the
  provider itself rejects a subnet ID spelled `/Subnets/`.

## Files / areas

- `modules/aks/variables.tf`, `main.tf`, `outputs.tf`, `tests/aks.tftest.hcl`,
  `README.md`
- `CHANGELOG.md`
- No CI changes: Verify already covers `modules/aks` on all four platforms.

## Data / contracts

azurerm `">= 5.12, < 6.0"`, as in 7a. Arguments were checked against the azurerm
5.12.0 `azurerm_kubernetes_cluster_node_pool` docs.

`aks_user_node_pools`: `map(object)`, default `{}`, not nullable. The map key is the
pool name: 1-12 lowercase letters and digits, starting with a letter, and not the
system pool's name.

| Attribute | Type and default | Rule |
|---|---|---|
| `vm_size` | string, required | `Standard_` plus letters, digits, `_` and `-`, as in 7a |
| `min_count`, `max_count` | number, required | Whole numbers, 0 ≤ min ≤ max ≤ 1000 |
| `zones` | list(string), `null` | Only `"1"`, `"2"` and `"3"` |
| `os_disk_type` | string, `"Managed"` | `Managed` or `Ephemeral` |
| `os_sku` | string, `null` | `AzureLinux`, `AzureLinux3`, `Ubuntu`, `Ubuntu2204` or `Ubuntu2404`; null means Azure's default (`Ubuntu`) |
| `subnet_id` | string, `null` | A subnet ID in the same vnet as `subnet_id`; null uses `subnet_id` |
| `node_labels` | map(string), `{}` | Passed through; Spot pools also get the Spot label |
| `node_taints` | list(string), `[]` | Each `key=value:Effect` or `key:Effect`, where the effect is `NoSchedule`, `PreferNoSchedule` or `NoExecute`; Spot pools also get the Spot taint |
| `spot` | object, `null` | `{ eviction_policy = optional(string, "Delete"), max_price = optional(number, -1) }`. The policy is `Delete` or `Deallocate`; the price is `-1` or above 0 with up to 5 decimals |

`aks_system_node_pool` gains `only_critical_addons_enabled = optional(bool, false)`.
Changing it later cycles the system pool through its temporary rotation pool.

| Output | Value |
|---|---|
| `aks_user_node_pool_ids` | Map of pool name to node pool ID; `{}` when there are none |

User pools take `aks_tags`, as the system pool does.

## Testing

`terraform test` with `mock_provider "azurerm"`, offline, adding to
`modules/aks/tests/aks.tftest.hcl` with `command = plan`.

- **Default:** no user pools, and the system pool isn't tainted.
- **Regular pool:** cluster ID, default subnet, counts, labels, taints, User mode,
  Linux, Regular priority, and the derived rotation name.
- **Pool with its own subnet** in the same vnet.
- **Spot pool:** priority, eviction policy and max price defaults, and the Spot
  label and taint merged with the caller's own.
- **System pool reservation:** `only_critical_addons_enabled = true` reaches the
  default node pool.
- **Rejections**, each an `expect_failures` test:
  - pool name format, and a pool named like the system pool
  - VM size, counts (min above max, negative, fractional, over 1000), zones, OS disk
    type, OS SKU (for example `Windows2022`) and taint format
  - a subnet ID that isn't a subnet, and a subnet in another vnet
  - a Spot eviction policy, and prices `0` or `-2`
  - a rotation-name collision
- **Not tested:** whether Azure accepts a given VM size or Spot capacity in a region.

## Notes for the AI

- The user asked Claude to write the code this time. Keep the review-only rule for
  any module change the user hasn't asked for.
- Spot label and taint values come from the azurerm docs' pointer to Azure's Spot
  pool page. They are `kubernetes.azure.com/scalesetpriority=spot` and
  `kubernetes.azure.com/scalesetpriority=spot:NoSchedule`. If a live run shows
  different values, fix them here.
- Don't set `orchestrator_version` or `node_count`. Pools follow the cluster's
  upgrade channel and the autoscaler sets the count, so setting either would cause
  drift.
- Same-vnet check: compare everything before `/subnets/`, case-insensitively.
- Open findings F-43 to F-47 from 7a stay out of scope unless the user asks.


<!-- blueprint:completion {"schemaVersion":2,"specBytes":9073,"specSha256":"6833692c20cb5e9efb9760cc0440b99f62657561e25e32877c463030344de9a6","branch":"refs/heads/feature/aks-user-node-pools","head":"4a3d1054e1c114ba2274e513d14428926987a625","baseRef":"refs/heads/main","baseCommit":"2ff810410ec0b127060ff183029dfc80715c615d","sourceTree":"1faa23a38beafe558afe73f05449c6eb37782788","landing":"local-merge","absentOptional":[]} -->

## Findings

### 7b/F-48 [P3] invalid - The same-vnet check rejects a valid subnet ID written with "/Subnets/"

**File:** modules/aks/main.tf:174
**Found:** 2026-11-04 by /audit independent (scope: current; lens: quality)
**Why it matters:** `split("/subnets/", ...)` runs before `lower()`, both here and in `local.cluster_vnet_id` (main.tf:18). The `subnet_id` validations accept any case (`(?i)`), and the spec says to compare the vnet part case-insensitively, yet a pool subnet in the cluster's vnet spelled `.../virtualNetworks/vnet-test/Subnets/b` fails the precondition (reproduced with a scratch mock test). Azure normally returns lowercase `subnets`, so this is rare.
**Suggested fix:** Lower before splitting: `split("/subnets/", lower(...))[0]` in both places. Optionally add a plan run with a mixed-case `Subnets` segment.
**Resolution:** Fixed 2026-11-04 by /implement (7b step 5): IDs are lowercased before splitting on `/subnets/`. A test with a `/Subnets/` pool subnet then failed inside the azurerm provider ("the segment at position 8 didn't match ... the literal value \"subnets\""), so that spelling is not a valid subnet ID and plan already fails on it; the original premise may be invalid. The test was dropped; mixed-case vnet names stay covered by `user_pool_in_its_own_subnet`.
Re-examined 2026-11-04 by /audit independent (fresh subagent, target 4a3d105): invalid. A scratch plan against the target with a pool `subnet_id` ending `.../virtualNetworks/vnet-test/Subnets/b` fails inside azurerm 5.12.0 on `vnet_subnet_id` ("the segment at position 8 didn't match ... the literal value \"subnets\""), so the ID the finding called valid is rejected by the provider at plan regardless of the module's check; no caller could reach the described false rejection. The vnet part was already compared case-insensitively before the repair. The current `split("/subnets/", lower(...))` code (main.tf:18, 22) is harmless and introduced no new defect.

### 7b/F-49 [P3] closed - The same-vnet precondition runs only after the cluster exists when subnet IDs are unknown at plan

**File:** modules/aks/main.tf:173
**Found:** 2026-11-04 by /audit independent (scope: current; lens: quality)
**Why it matters:** The coding standards put cross-variable checks on the first resource that would otherwise fail, "so nothing is half-created". The vnet check sits on `azurerm_kubernetes_cluster_node_pool.user`, which depends on the cluster. When the subnet IDs come from a vnet created in the same apply (the README's `module.vnet.subnet_ids[...]` example), the check is deferred to apply and fails only after the cluster has been created. The name and rotation checks use map keys, which are always known, so they still fail at plan.
**Suggested fix:** Move the vnet comparison into a precondition on `azurerm_kubernetes_cluster.aks` that checks every pool (for example `alltrue([for name, pool in var.aks_user_node_pools : ...])`, naming the offending pools in the message). Nothing current is lost.
**Resolution:** Fixed 2026-11-04 by /implement (7b step 5): the same-vnet check is now a precondition on `azurerm_kubernetes_cluster.aks` over all pools (`local.pools_outside_cluster_vnet`, named in the error), and the per-pool precondition is removed. `rejects_user_pool_subnet_in_another_vnet` now expects the failure on the cluster.
Re-examined 2026-11-04 by /audit independent (fresh subagent, target 4a3d105): closed. main.tf:144-147 holds the check on `azurerm_kubernetes_cluster.aks`. A scratch root module passing an `azurerm_subnet` ID (unknown at plan, mocked into another vnet) as a pool subnet planned cleanly, then failed at apply on the cluster precondition naming the pool, before the cluster or any pool was created. No new defect found in the repair.

### 7b/F-50 [P3] closed - aks_tags still says it tags only the cluster and its system pool

**File:** modules/aks/variables.tf:391
**Found:** 2026-11-04 by /audit independent (scope: current; lens: quality)
**Why it matters:** User pools now take `aks_tags` (main.tf:170, as the spec requires), but the description and the generated README row still say "Tags for the cluster and its system node pool."
**Suggested fix:** Say "the cluster and its node pools" and regenerate the README with terraform-docs.
**Resolution:** Fixed 2026-11-04 by /implement (7b step 5): description now reads "Tags for the cluster, its system node pool and every user node pool."; README table regenerated.
Re-examined 2026-11-04 by /audit independent (fresh subagent, target 4a3d105): closed. variables.tf:391 and README.md:155 both carry the new text; the terraform-docs check in Verify passes.

## Independent review

# Independent Review

**Status:** passed
**Target commit:** 4a3d1054e1c114ba2274e513d14428926987a625
**Base commit:** 2ff810410ec0b127060ff183029dfc80715c615d
**Base ref:** main
**Spec hash:** 6833692c20cb5e9efb9760cc0440b99f62657561e25e32877c463030344de9a6
**Prepared by:** claude
**Builder model:** claude-opus-5-5
**Requested reviewer:** claude
**Requested model:** claude-opus-5-5
**Requested execution:** automatic
**Requested at:** 2026-11-04T18:37:23Z
**Workflow:** regular
**Check required:** no
**Reviewer adapter:** claude
**Reviewer model:** claude-opus-5-5
**Reviewer context:** fresh subagent
**Actual execution:** automatic
**Reviewed at:** 2026-11-04T18:42:33Z
**Scope:** current
**Lenses:** quality, security, performance, tests
**Verdict:** passed
**Check result:** not-required

## Handoff

Review the active spec and the complete `2ff810410ec0b127060ff183029dfc80715c615d..4a3d1054e1c114ba2274e513d14428926987a625` delta in a fresh
session or isolated subagent without the builder conversation. Run all Audit lenses from scratch.
Run Check when required above. Do not edit product code, accept findings, or
reuse the existing findings as the review scope.

## Commands

- `terraform -chdir=modules/aks init -backend=false && terraform -chdir=modules/aks validate`: pass
- `terraform -chdir=modules/aks test`: pass (68 passed, 0 failed)
- `sh scripts/verify.sh` (pinned tflint 0.65.0 and terraform-docs 0.24.0 on PATH): pass ("All checks passed.")
- `sh scripts/trivy-scan.sh LOW aks`: fail on AZU-0040 (MEDIUM, tracked as F-46), AZU-0066 and AZU-0067 (LOW); identical to the base commit, no HIGH or CRITICAL
- `terraform providers schema -json` (azurerm 5.12.0): pass, node pool attributes inspected
- Scratch `terraform test` runs against a copy of the target: pass (rotation clauses 1 and 4 fire; provider rejects `/Subnets/`; unknown out-of-vnet subnet fails on the cluster at apply; all five os_sku values and a 5-decimal Spot price plan)
- Scratch mutation (clauses 1 and 4 of the rotation precondition removed): shipped suite still 68 passed

## Evidence

- HEAD, merge base of `main`, spec hash and working tree matched the request; only review.md and findings.md differ
- Reviewed main.tf, variables.tf, outputs.tf, tests/aks.tftest.hcl, README.md, CHANGELOG.md and the plan/overview text changes in the delta
- Spot taint is declared because azurerm 5.12.0 `node_taints` is not computed; `only_critical_addons_enabled` appears in the provider's default-pool cycling property strings, matching the "cycles the pool" docs
- No CI files changed; Trivy results unchanged from base

## Findings

- F-51 [P3] open: rotation-name precondition clauses 1 and 4 untested (modules/aks/main.tf:188)
- F-48 invalid, F-49 closed, F-50 closed

## Remaining risk

- No live Azure plan or apply (out of scope): AKS acceptance of the declared `kubernetes.azure.com/scalesetpriority` Spot label and taint, Spot capacity, VM sizes and user-pool `max_count = 0` are unproven
- Possible `upgrade_settings` read-back drift on regular user pools that omit the block is unverifiable offline
- Trivy MEDIUM AZU-0040 (F-46) must be fixed or accepted before release
- Dashboard activity was not written: this reviewer was limited to findings.md and review.md

## Try it now

1. Run the offline tests: `terraform -chdir=modules/aks init -backend=false && terraform -chdir=modules/aks test`.
   Expect `68 passed, 0 failed`. No Azure credentials are used.
2. In a scratch root module, call `modules/aks` with
   `aks_user_node_pools = { spot = { vm_size = "Standard_D4s_v5", min_count = 0, max_count = 3, spot = {} } }`
   and run `terraform test` with `mock_provider "azurerm" {}` and a `command = plan` run.
   Expect the pool planned with `priority = "Spot"`, `eviction_policy = "Delete"`,
   `spot_max_price = -1`, and the `kubernetes.azure.com/scalesetpriority=spot` label and
   `...=spot:NoSchedule` taint.
3. Change the pool key to `system` (the system pool's name). Expect the plan to fail on the
   precondition that a user pool can't reuse the system pool's name.
4. In the live-infra repo, run a real `plan` and `apply` with a Spot pool. Expect no drift
   on the Spot label and taint in a second `plan`.
