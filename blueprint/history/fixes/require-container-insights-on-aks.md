# Fix: Require Container Insights on aks

**Type:** Fix
**Status:** verified
**Branch:** fix/require-container-insights-on-aks
**Fixes:** F-46

## The problem

`sh scripts/trivy-scan.sh MEDIUM aks` fails with AZU-0040 (MEDIUM): "Cluster does not
have logging enabled via OMS Agent". `modules/aks/main.tf:98` adds the `oms_agent`
block only when `aks_log_analytics_workspace_id` is set, and that input defaults to
`null`, so Container Insights is off by default. The release check runs that same
MEDIUM scan, so `aks/v1.0.0` can't be tagged until this is fixed or accepted.

The user chose to fix it by requiring monitoring, not by accepting the finding
(2026-11-04).

Probes on a scratch copy with Trivy 0.76.1:

| Change | MEDIUM scan |
|---|---|
| Module as shipped | fails: AZU-0040 |
| Only removing the input's default | still fails: Trivy can't see that the `dynamic` block will exist |
| Required, non-nullable input and a plain `oms_agent` block | passes; only the existing LOW AZU-0066 and AZU-0067 remain |

## The fix

- `aks_log_analytics_workspace_id` becomes required: no default, `nullable = false`.
  Keep the existing format validation, without the `coalesce` null guard it no longer
  needs. The description says Container Insights is always on and the caller provides
  the workspace.
- Replace the `dynamic "oms_agent"` block in `main.tf` with a plain `oms_agent` block,
  with `msi_auth_for_monitoring_enabled = true` as today.
- No `.trivyignore` entry. F-46 is fixed, not accepted.

Must not break:

- The other optional integrations stay optional: workload identity, the Key Vault
  secrets CSI driver, ACR pull and user pools.
- The cluster's other defaults.
- All 7a and 7b tests other than the ones this change has to update.

This changes the module's interface, but `aks` has never been released (no `aks/v*`
tag), so no caller breaks. The CHANGELOG change goes in the existing unreleased
`Added` entry, not under `Breaking`.

## Build steps

- [x] 1. **Require the workspace and always enable Container Insights.**
  - `modules/aks/variables.tf`: the input change above.
  - `modules/aks/main.tf`: the plain `oms_agent` block.
  - `modules/aks/tests/aks.tftest.hcl`:
    - Add a workspace ID to the file-level `variables` block.
    - `defaults_are_secure`: assert that `oms_agent` is present, on that workspace,
      with managed identity auth, in place of the `length(... oms_agent) == 0` clause.
      Update its error message.
    - Keep `integrations_on` and the bad-ID rejection (`rejects_bad_..._workspace_id`
      at line 459).
    - Add a run passing `aks_log_analytics_workspace_id = null` that expects the
      failure, if `terraform test` can express it. A non-nullable null is a variable
      error rather than a validation failure, so check that `expect_failures` catches
      it; if it can't, leave the run out and say why in the step note.
  - `modules/aks/README.md`:
    - Move the workspace line out of "Optional integrations, each off by default".
    - Add a "Container Insights on" bullet to Defaults that names the Log Analytics
      cost.
    - Regenerate the terraform-docs table, where the input becomes required.
  - `CHANGELOG.md`: in the `aks` Added entry, list Container Insights as always on,
    with `aks_log_analytics_workspace_id` required, not as optional.

  **Done when:**
  - `terraform -chdir=modules/aks test` passes.
  - `sh scripts/trivy-scan.sh MEDIUM aks` prints `No findings.`
  - `sh scripts/verify.sh` prints `All checks passed.`

  **Step note:** the null run was left out. `terraform test` stops a run with
  `aks_log_analytics_workspace_id = null` with "Required variable not set ... may not
  be set to null" before any validation runs. `expect_failures` can't catch that, and
  the failed run skips every later run. Terraform still rejects a null at plan; it just
  can't be expressed as a passing test.

## Verify

- `terraform -chdir=modules/aks init -backend=false && terraform -chdir=modules/aks test`:
  all runs pass, and `defaults_are_secure` shows `oms_agent` present.
- `sh scripts/trivy-scan.sh MEDIUM aks`: `No findings.` AZU-0040 is gone.
- `sh scripts/trivy-scan.sh LOW aks`: only AZU-0066 and AZU-0067, unchanged from
  today and outside this fix.
- `sh scripts/verify.sh`: `All checks passed.`
- Live, in the separate test repo: a plan without the workspace input fails with
  Terraform's missing-variable error, and one with it shows the `oms_agent` block.

## Notes for the AI

- Module code under `modules/` is the user's to write by default, and Claude reviews.
  Claude writes it only when the user asks, as they did for 7a and 7b. Ask at
  `/implement` if it's still unclear.
- Out of scope:
  - AZU-0066 (Azure Policy add-on) and AZU-0067 (disk encryption set). Both are LOW,
    and the release gate is MEDIUM.
  - Other aks findings: F-43 to F-45, F-47 and F-51.
  - The build-plan 7a line still calls Container Insights optional. The plan belongs
    to the user. Mention it at `/complete` instead of editing it.
- Live-only: AKS accepting `msi_auth_for_monitoring_enabled` with the caller's
  workspace, and the cost of the data sent there.


<!-- blueprint:completion {"schemaVersion":2,"specBytes":5156,"specSha256":"528df642e04d219b6493b3e78203cb467b3d43f94b7b996e6c0f5b87d9ab3ae5","branch":"refs/heads/fix/require-container-insights-on-aks","head":"57ed0bec17e78b3d24ac94219608dfc4664b30e0","baseRef":"refs/heads/main","baseCommit":"d446bca0c2606100fa7d0dd5be7cd322aa3cd420","sourceTree":"504b236d535bdfde996e72acfcf7242178f2a1ce","landing":"local-merge","absentOptional":[]} -->

## Findings

### require-container-insights-on-aks/F-46 [P3] closed - Trivy MEDIUM AZU-0040 fires on the module defaults

**File:** modules/aks/main.tf:13
**Found:** 2026-11-04 by /audit independent (scope: current; lens: security)
**Why it matters:** `sh scripts/trivy-scan.sh MEDIUM aks` fails with AZU-0040 (no `oms_agent`) because Container Insights is off by default. The spec and the owner's release rule require the MEDIUM scan to pass, or the user to accept it, before tagging `aks/v1.0.0`. Verify (HIGH and above) passes, so this does not block the feature.
**Suggested fix:** Before tagging, either make the user's acceptance explicit (record the reason here as `accepted`), or require a workspace ID by default. Do not add a Trivy ignore without that decision.
**Resolution:** Fixed 2026-11-04 by /implement (fix "Require Container Insights on aks"), the user's choice over accepting it: `aks_log_analytics_workspace_id` is required and non-nullable, and `oms_agent` is a plain block, so Container Insights is always on. `trivy config --severity MEDIUM,HIGH,CRITICAL modules/aks` exits 0; only AZU-0066 and AZU-0067 (LOW) remain. `defaults_are_secure` asserts the block.
Re-examined 2026-11-04 by /audit independent (scope: current; all lenses), target 57ed0be: closed. `sh scripts/trivy-scan.sh MEDIUM aks` prints `No findings.` with no `.trivyignore` change; the base commit's module still fails AZU-0040, and a scratch copy of the target with only the `dynamic "oms_agent"` block restored fails it again, so the plain block is what clears it. LOW shows only AZU-0066 and AZU-0067. A null workspace is rejected at plan ("required variable may not be set to null", confirmed by probe), and a workspace ID unknown at plan (built from a resource in the same apply) still plans under the mock provider. All 68 tests and `sh scripts/verify.sh` pass. No new defect from the repair; minor follow-ups are F-52 and F-53.

## Independent review

# Independent Review

**Status:** passed
**Target commit:** 57ed0bec17e78b3d24ac94219608dfc4664b30e0
**Base commit:** d446bca0c2606100fa7d0dd5be7cd322aa3cd420
**Base ref:** main
**Spec hash:** 528df642e04d219b6493b3e78203cb467b3d43f94b7b996e6c0f5b87d9ab3ae5
**Prepared by:** claude
**Builder model:** claude-opus-5-5
**Requested reviewer:** claude
**Requested model:** claude-opus-5-5
**Requested execution:** automatic
**Requested at:** 2026-11-04T21:09:14Z
**Workflow:** regular
**Check required:** no
**Reviewer adapter:** claude
**Reviewer model:** claude-opus-5-5
**Reviewer context:** fresh subagent
**Actual execution:** automatic
**Reviewed at:** 2026-11-04T21:40:00Z
**Scope:** current
**Lenses:** quality, security, performance, tests
**Verdict:** passed
**Check result:** not-required

## Handoff

Review the active spec and the complete `d446bca0c2606100fa7d0dd5be7cd322aa3cd420..57ed0bec17e78b3d24ac94219608dfc4664b30e0` delta in a fresh
session or isolated subagent without the builder conversation. Run all Audit lenses from scratch.
Run Check when required above. Do not edit product code, accept findings, or
reuse the existing findings as the review scope.

## Commands

- `sha256sum blueprint/context/current-feature.md`, `git rev-parse HEAD`, `git merge-base main HEAD`: pass (match Spec hash, Target commit and Base commit; only review.md and findings.md differ)
- `terraform -chdir=modules/aks init -backend=false && terraform -chdir=modules/aks validate`: pass
- `terraform -chdir=modules/aks test`: pass (68 passed, 0 failed)
- `sh scripts/trivy-scan.sh MEDIUM aks`: pass (`No findings.`)
- `sh scripts/trivy-scan.sh LOW aks`: fail as expected (only AZU-0066 and AZU-0067, LOW, out of scope)
- `sh scripts/verify.sh` (pinned tflint and terraform-docs on PATH): pass (`All checks passed.`)
- Scratch probes under the session scratchpad `review-f46/`: base-commit Trivy MEDIUM scan, dynamic-block variant scan, unknown-at-plan workspace root test, null-workspace `expect_failures` run: all ran as described in Evidence

## Evidence

- Delta `d446bca..57ed0be`: `modules/aks/{main.tf,variables.tf,README.md,tests/aks.tftest.hcl}`, `CHANGELOG.md`, and the spec. No `.trivyignore` change.
- Trivy passes because of the change: the base module fails AZU-0040 at MEDIUM; the target with only the `dynamic "oms_agent"` block restored (input still required) fails it again; the target as committed passes.
- Required, non-nullable input: a run setting it to `null` stops with "required variable may not be set to null" and `expect_failures = [var.aks_log_analytics_workspace_id]` reports "Missing expected failure", so the spec's step note holds.
- A workspace ID unknown at plan (built from `terraform_data.id` in a calling root) plans with the mock provider; the validation defers on unknown.
- azurerm 5.12.0 accepts the plain `oms_agent` block with `msi_auth_for_monitoring_enabled = true` (`validate` passes; `defaults_are_secure` and `integrations_on` assert both attributes).
- README Defaults bullet, example, terraform-docs table (input now required, `n/a`) and the CHANGELOG unreleased Added entry match the code; terraform-docs check in verify passes.
- Other optional integrations (workload identity, Key Vault CSI, ACR pull, user pools) are still asserted off by default.

## Findings

- F-46 [P3] closed: the repair holds (see its Resolution).
- F-52 [P3] open: `integrations_on` repeats the workspace input and the Container Insights assert now covered by `defaults_are_secure`.
- F-53 [P3] open: `blueprint/project-plan.md:35`, `blueprint/build-plan.md:30` and `blueprint/context/project-overview.md:39` still call Container Insights optional.

## Remaining risk

- Live-only, not provable offline: AKS accepting `msi_auth_for_monitoring_enabled = true` with the caller's workspace and actually collecting data (Terraform-created clusters may also need a data collection rule and association for MSI-auth Container Insights), and the Log Analytics ingestion cost. Settle in the separate live test repo.
- The live plan checks in the spec's Verify section (missing input fails, with input shows `oms_agent`) were not run here; the offline probes cover the same behavior with mocks.
