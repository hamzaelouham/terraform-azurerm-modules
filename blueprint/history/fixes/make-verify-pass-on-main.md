# Fix: Make Verify pass on main

**Type:** Fix
**Status:** verified
**Branch:** fix/make-verify-pass-on-main

## The problem

`sh scripts/verify.sh` fails on `main` with 7 checks, seen in GitHub Actions run
41477863394 at `97aba81`:

| Check | Cause |
|---|---|
| `key-vault`: trivy | AZU-0013 (CRITICAL): `kv_network_acls` defaults to `null`, so no `network_acls` block exists |
| `storage-account`: trivy | AZU-0012 (CRITICAL): `sa_network_rules` defaults to `null`, so no `network_rules` block exists |
| `key-vault`, `storage-account`: tflint | `azurerm_resources_missing_prevent_destroy`; already turned off, uncommitted in `.tflint.hcl` |
| `virtual-machine`: tflint | The `vm_size` default `Standard_B2s` is flagged for retirement |
| `storage-account`, `virtual-machine`: terraform-docs | The READMEs have no generated docs section |

This blocks the AI azurerm upgrade agent, whose repair loop would otherwise try
to fix these failures in every PR.

## The fix

- Deny network access by default in both modules. `default = {}` applies the
  existing `optional(string, "Deny")`. Passing `null` stays the explicit opt-out,
  so the existing `null` handling and validation don't change.
- Move the `vm_size` default to `Standard_B2s_v2`.
- Add the generated docs section to the two READMEs that exist. Modules without
  a README stay as they are, because READMEs are optional.

Must not break:

- No `.trivyignore` entry: CRITICAL and HIGH findings get fixed, not ignored.
- `resource-group` keeps its own `prevent_destroy`.
- Existing storage and VM tests keep passing, apart from the one assert below.

This is a breaking change for callers who rely on open network access, and it
goes in the CHANGELOG. The new VM size default also resizes any existing VM that
relies on the old default, so it goes in the CHANGELOG too.

## Build steps

- [x] 1. **Deny by default.** In `modules/key-vault/variables.tf` and
  `modules/storage-account/variables.tf`, set `default = {}` on `kv_network_acls`
  and `sa_network_rules`, and reword both descriptions, which still say null is
  the default behaviour. In `modules/storage-account/tests/storage.tftest.hcl:46`,
  assert `network_rules[0].default_action == "Deny"` by default, and add one run
  showing that `sa_network_rules = null` creates no block. Correct
  `modules/storage-account/README.md:37`. Add a Breaking entry under
  `[Unreleased]` in `CHANGELOG.md`.
  **Done when:** `sh scripts/trivy-scan.sh HIGH key-vault` and
  `sh scripts/trivy-scan.sh HIGH storage-account` report no findings, and the
  storage tests pass.
- [x] 2. **Current VM size.** In `modules/virtual-machine/variables.tf`, change the
  default at line 51 to `Standard_B2s_v2`, and update the description at line 49
  and the error message at line 55.
  **Done when:** tflint exits 0 on `modules/virtual-machine`, and its tests pass.
- [x] 3. **Generated docs.** After steps 1 and 2, because the docs describe the
  final inputs, run for `storage-account` and `virtual-machine`:
  `terraform-docs markdown table --lockfile=false --output-file README.md --output-mode inject modules/<name>`.
  **Done when:** `sh scripts/verify.sh` prints `All checks passed.`

## Verify

- `sh scripts/verify.sh` prints `All checks passed.` locally, then GitHub Actions
  passes on the PR or on `main`.
- Not provable offline, for the live test repo: a runner outside the network can
  still plan and apply with Deny as the default (F-14), and `Standard_B2s_v2` is
  available in the regions callers use.

## Notes for the AI

- Files under `modules/` are normally hand-written by the user. Edit them only if
  the user runs `/implement` on this spec or otherwise asks. If the user writes
  them, review the result instead.
- `key-vault` has no test suite (F-16). This fix doesn't add one, so trivy and
  `validate` are its evidence.
- `090411a` (the optional README change in `verify.sh`) landed on `main` without a
  spec or archive. Record that in this fix's archive rather than rewriting history.


<!-- blueprint:completion {"schemaVersion":2,"specBytes":4011,"specSha256":"6890caf3709d7115959a27587bdedc816e6f02cd8569c6eab439b773325cda83","branch":"refs/heads/fix/make-verify-pass-on-main","head":"d461d452168dc2353d475400c2aba92b0aad1dca","baseRef":"refs/heads/main","baseCommit":"97aba81cd05335f4ac25faf7868bf180801d1487","sourceTree":"6815706593d709b38beacfb1469101cb69448841","landing":"local-merge","absentOptional":[]} -->

## Findings

No findings were resolved by this fix. Open and unverified entries stay in `blueprint/context/findings.md`.

## Independent review

# Independent Review

**Status:** passed
**Target commit:** d461d452168dc2353d475400c2aba92b0aad1dca
**Base commit:** 97aba81cd05335f4ac25faf7868bf180801d1487
**Base ref:** main
**Spec hash:** 6890caf3709d7115959a27587bdedc816e6f02cd8569c6eab439b773325cda83
**Prepared by:** claude
**Builder model:** claude-opus-5-5
**Requested reviewer:** claude
**Requested model:** claude-opus-5-5
**Requested execution:** automatic
**Requested at:** 2026-11-02T16:11:16Z
**Workflow:** regular
**Check required:** no
**Reviewer adapter:** claude
**Reviewer model:** claude-opus-5-5
**Reviewer context:** fresh subagent
**Actual execution:** automatic
**Reviewed at:** 2026-11-02T16:15:03Z
**Scope:** current
**Lenses:** quality, security, performance, tests
**Verdict:** passed
**Check result:** not-required

## Handoff

Review the active spec and the complete `97aba81cd05335f4ac25faf7868bf180801d1487..d461d452168dc2353d475400c2aba92b0aad1dca` delta in a fresh
session or isolated subagent without the builder conversation. Run all Audit lenses from scratch.
Run Check when required above. Do not edit product code, accept findings, or
reuse the existing findings as the review scope.

## Commands

- `sh scripts/verify.sh` (clean export of the target, pinned tflint and terraform-docs on PATH, Terraform and trivy from PATH): pass, prints `All checks passed.`; storage-account 42 tests, virtual-machine 14 tests
- `sh scripts/trivy-scan.sh HIGH key-vault`: pass, no findings
- `sh scripts/trivy-scan.sh HIGH storage-account`: pass, no findings
- `sh scripts/trivy-scan.sh MEDIUM`: fail, AZU-0057 and AZU-0061 in storage-account and AZU-0068 in virtual-machine, from `main.tf` files this delta doesn't change; not part of Verify
- `terraform providers schema -json` (azurerm 5.12.0, scratch copy): pass
- `terraform test` with mocked key-vault probes (scratch copy): pass for the default and for null on a new vault
- Scratch mutants of the new defaults under `terraform test`, trivy or tflint: 8 of 9 runs failed as they should; the survivor is below
- `terraform init` with a `lifecycle` block in a module call (scratch copy): rejected as expected
- Live `terraform plan` or `apply`: unavailable, no Azure credentials

## Evidence

- Request verified before review: HEAD, merge base from `main`, spec SHA-256, adapter and model all match; only `blueprint/context/review.md` differed from the target.
- Delta reviewed: `.tflint.hcl`, `CHANGELOG.md`, `blueprint/context/current-feature.md`, `modules/key-vault/variables.tf`, `modules/storage-account/` (`README.md`, `variables.tf`, `tests/storage.tftest.hcl`), `modules/virtual-machine/` (`README.md`, `variables.tf`), plus the `main.tf` consumers of the changed variables.
- Spec: all three steps are present, `.trivyignore` has no entries, `resource-group` keeps `prevent_destroy`, and the storage test change is limited to the one assert plus the one new run.
- Storage default regressions (`default = null`, `default_action` default `Allow`, null opt-out ignored) fail the tests; the first two also fail trivy. Key-vault default regressions fail trivy. Restoring `Standard_B2s` fails tflint and survives `terraform test`, which is acceptable because Verify runs tflint.
- Suspected and cleared: `sa_network_rules = null` leaving old rules in place on an existing resource. In azurerm 5.12.0 both `network_rules` and `network_acls` are blocks, not optional-computed attributes, and a mocked plan of null after an applied default removes the `key-vault` block. A live update remains unproved.
- Performance: the delta changes defaults, docs, tests and lint config only, with no new resources, loops or provider calls. Security: no secret values appear in the delta.

## Findings

- New: F-21 [P2] unverified, F-22 [P3] open, F-23 [P3] open
- Updated, status unchanged: F-14 [P2] unverified, F-16 [P2] open, F-20 [P3] unverified
- No P0 or P1 finding is `open` or `fixed`.

## Remaining risk

- Live `terraform plan` and `apply` were unavailable, so nothing here proves Azure accepts the new defaults.
- F-14: with Deny now the default, an off-network runner may fail to plan or apply a default `storage-account`. This is the largest open risk; the spec defers it to the live test repo, and it should be settled before release.
- F-20: the default `{}` sends rules with no IPs or subnets, which an azurerm note questions. Needs the same live test.
- F-21: the resize of existing VMs and the use of Gen 1 images with `Standard_B2s_v2` are unproved, and the CHANGELOG entry may be wrong.
- `Standard_B2s_v2` regional availability is unproved, as the spec records.
- GitHub Actions has not run on this target; the spec requires it after local Verify.
- `sh scripts/trivy-scan.sh MEDIUM` fails for `storage-account` and `virtual-machine`, and `scripts/release-check.sh` runs that gate, so tagging those modules will fail until these findings are fixed or accepted. They aren't caused by this delta.

## Try it now

From the repo root:

```sh
sh scripts/trivy-scan.sh HIGH storage-account
sh scripts/trivy-scan.sh HIGH key-vault
```

Each should end with `No findings.` Before this fix, the same scans failed with the CRITICAL findings AZU-0012 and AZU-0013.
