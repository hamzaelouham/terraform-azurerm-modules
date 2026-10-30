# Feature: Storage account private endpoint

**From build-plan:** feature 6b
**Build attempt:** 1
**Branch:** feature/storage-account-private-endpoint
**Status:** verified

## Goal

Let callers of `modules/storage-account` opt in to one private endpoint for the
blob service, placed in a vnet subnet (`module.vnet.subnet_ids["<name>"]`), and
optionally registered in an existing private DNS zone that the caller owns.

## In scope

- `sa_private_endpoint` input: null (default) creates nothing.
- One `azurerm_private_endpoint.pe` for the `blob` subresource, automatically
  approved, tagged with `sa_tags`, with names derived from `sa_name`.
- Optional registration in a caller-owned `privatelink.blob.*` zone through
  `private_dns_zone_id`, per your decision.
- Outputs `sa_private_endpoint_id` and `sa_private_endpoint_ip`, both null when
  the endpoint is off.
- Plan-time rejection of a blob endpoint on `FileStorage` and of a DNS zone ID
  that isn't a `privatelink.blob.*` zone.
- README, CHANGELOG entry, mocked tests.

## Out of scope

- Creating private DNS zones, vnet links or A records. The caller owns these.
- Endpoints for any other subresource (`file`, `dfs`, `queue`, `table`, `web`),
  or more than one endpoint per account.
- Static private IPs (`ip_configuration`) and custom NIC names.
- Changing `sa_public_network_access_enabled` or `sa_network_rules` when an
  endpoint is set. Those stay the caller's choice, and the README says so.
- Changes to the `vnet` module. `private_endpoint_network_policies` is left at the
  provider default.
- Findings F-08 to F-12 from feature 6a stay in the ledger, unrepaired here.
- Refreshing `project-plan.md` or the overview.

## Build loop

- `workflow.stepReview = "feature"`: implement all steps, then stop once for a
  whole-feature review. `workflow.checkpointCommits = "disabled"`: no commits
  during the build; `/complete` creates the single feature commit.
- Work on branch `feature/storage-account-private-endpoint`, created from `main`.
- This changes a network boundary, so `qualityGates.regular.independentReview`
  (`when-sensitive`) selects independent review. That needs one review checkpoint,
  with your approval, before `/complete`.
- After each step: `terraform fmt -check -recursive`, then `init -backend=false`,
  `validate` and `test` in `modules/storage-account`. If `init` fails on a stale
  `.terraform` symlink or stalls on the azurerm download, run them on a copy of
  the module with `-plugin-dir` pointing at an already-downloaded provider, and
  don't change the checkout's `.terraform`.

## Build steps

- [x] **1. Endpoint resource and outputs.** Add `sa_private_endpoint` to
  `variables.tf`, `azurerm_private_endpoint.pe` to `main.tf` with
  `count = var.sa_private_endpoint == null ? 0 : 1`, and the two outputs read with
  `one()`. Add tests.
  **Done when:** tests show no endpoint and null outputs by default; with
  `sa_private_endpoint` set, one endpoint with the given subnet, the names below,
  subresource `blob`, `is_manual_connection = false` and `sa_tags`; and non-null
  outputs in a `command = apply` run with a mocked ID.
- [x] **2. DNS registration.** Add a dynamic `private_dns_zone_group` from
  `private_dns_zone_id`, and the variable validation for the zone name.
  **Done when:** tests show no zone group when the ID is null, one group with the
  given zone when set, and rejected `privatelink.file.core.windows.net` and lowercase
  `privatednszones` IDs.
- [x] **3. FileStorage precondition.** Add a precondition on
  `azurerm_storage_account.sa` that `sa_private_endpoint` is null on `FileStorage`.
  **Done when:** a run with Premium, `FileStorage` and an endpoint fails on
  `azurerm_storage_account.sa`, and a run with Premium, `BlockBlobStorage` and an
  endpoint plans.
- [x] **4. Docs.** Update `modules/storage-account/README.md` and add to the
  existing `storage-account` `Added` entry in `CHANGELOG.md`, or add a new line
  there.
  **Done when:** the README covers the usage snippet, the DNS note and the
  public-access note below; the full test suite is green; `fmt -check` is clean; and
  the README has no link into `examples/`.

## Files / areas

- `modules/storage-account/main.tf`, `variables.tf`, `outputs.tf`
- `modules/storage-account/tests/storage.tftest.hcl`
- `modules/storage-account/README.md`
- `CHANGELOG.md`

## Data / contracts

Input:

| Input | Type / default | Validation |
|---|---|---|
| `sa_private_endpoint` | `object({ subnet_id = string, private_dns_zone_id = optional(string) })`, default null | `private_dns_zone_id` is null or matches `/privateDnsZones/privatelink\.blob\.[^/]+$`. The match is case-sensitive because azurerm's ID parser requires the exact `privateDnsZones` segment (found in build). The suffix stays open for sovereign clouds. `subnet_id` isn't format-checked, same as the `virtual-machine` module's `subnet_id` |

Precondition on `azurerm_storage_account.sa`, so nothing is created when it fails:
`FileStorage` accounts can't have `sa_private_endpoint` (they have no blob service).

Resource `azurerm_private_endpoint.pe`:

| Attribute | Value |
|---|---|
| `name` | `<sa_name>-pe` |
| `resource_group_name`, `location` | `var.resource_group_name`, `var.location` |
| `subnet_id` | `var.sa_private_endpoint.subnet_id` |
| `tags` | `var.sa_tags` |
| `private_service_connection.name` | `<sa_name>-psc` |
| `private_service_connection.private_connection_resource_id` | `azurerm_storage_account.sa.id` |
| `private_service_connection.subresource_names` | `["blob"]` |
| `private_service_connection.is_manual_connection` | `false` |
| `private_dns_zone_group` | Only when `private_dns_zone_id` is set: name `<sa_name>-dns`, `private_dns_zone_ids = [id]` |

Outputs, each with a description and null when the endpoint is off:

- `sa_private_endpoint_id`: `one(azurerm_private_endpoint.pe[*].id)`
- `sa_private_endpoint_ip`:
  `one(azurerm_private_endpoint.pe[*].private_service_connection[0].private_ip_address)`,
  for callers that manage their own DNS record.

Composition: `subnet_id` comes from `module.vnet.subnet_ids["<name>"]`, as for
`virtual-machine`. The DNS zone ID comes from the caller's own zone resource.

## Testing

Test command: `terraform -chdir=modules/storage-account test`, offline with the
existing mocked provider. Add a `mock_resource "azurerm_private_endpoint"` default
ID to the existing `mock_provider` block. Expected runs:

- default: no endpoint; both outputs null in the `command = apply` run
- endpoint set: subnet, names, subresource, automatic approval, tags; no zone group
- endpoint with DNS zone: one zone group with the given ID
- `command = apply` with an endpoint: `sa_private_endpoint_id` equals the mocked ID
  and `sa_private_endpoint_ip` is non-null
- accepted: endpoint on `BlockBlobStorage`
- `expect_failures`: `privatelink.file.*` and lowercase `privatednszones` zone IDs on
  `var.sa_private_endpoint`; endpoint on `FileStorage` on
  `azurerm_storage_account.sa`

Mocked tests show the module's logic, not that Azure accepts the result. No live
plan or apply is part of this feature, so working name resolution and the
connection's approval remain unproven until someone runs one.

## Notes for the AI

- Follow the local `sa_network_rules` pattern: an object defaulting to null, read
  with `try()` guards in the validation.
- The input is an object rather than a bare nullable `subnet_id` so `count` stays
  known at plan time. `module.vnet.subnet_ids[...]` is unknown on a first apply, and
  `count` can't depend on an unknown value. Keep the `== null` check on the object.
- README notes to include:
  - DNS: without `private_dns_zone_id`, `<account>.blob.core.windows.net` still
    resolves to the public IP until the caller adds a record, using
    `sa_private_endpoint_ip`. The zone must be linked to the vnet, which is also
    the caller's job.
  - Public access: the endpoint doesn't close public access. For private-only, also
    set `sa_public_network_access_enabled = false`.
  - The endpoint covers blob only, so file shares aren't reached through it.
- Don't add comments that restate the code. No em dashes.
- If the mock can't produce a non-null `private_ip_address`, keep the null-when-off
  assertion and say the non-null case is unproven; don't add machinery to force it.


<!-- blueprint:completion {"schemaVersion":2,"specBytes":8319,"specSha256":"69529ee57fb7363d5ff6e62f9906538676105ee157339f0be82d5661dc2fc93b","branch":"refs/heads/feature/storage-account-private-endpoint","head":"83f4442fd56aa0fa6ee39d56ee8e196dcf76c39f","baseRef":"refs/heads/main","baseCommit":"3ebf3622447605e85aa2209bafba0be435e0a0e6","sourceTree":"153e867b782d6fc83314ddfef48d04848e7988a7","landing":"local-merge","absentOptional":[]} -->

## Findings

None resolved in this work item. F-13 and F-14 were raised by its review and stay in the live ledger with F-08 to F-12.

## Independent review

# Independent Review

**Status:** passed
**Target commit:** 83f4442fd56aa0fa6ee39d56ee8e196dcf76c39f
**Base commit:** 3ebf3622447605e85aa2209bafba0be435e0a0e6
**Base ref:** main
**Spec hash:** 69529ee57fb7363d5ff6e62f9906538676105ee157339f0be82d5661dc2fc93b
**Prepared by:** claude
**Builder model:** claude-opus-5-5
**Requested reviewer:** claude
**Requested model:** runtime default (exact model not known until reviewer starts)
**Requested execution:** automatic
**Requested at:** 2026-10-30T08:30:09Z
**Workflow:** regular
**Check required:** no
**Reviewer adapter:** claude
**Reviewer model:** claude-opus-5-5
**Reviewer context:** fresh subagent
**Actual execution:** automatic
**Reviewed at:** 2026-10-30T08:35:00Z
**Scope:** current
**Lenses:** quality, security, performance, tests
**Verdict:** passed
**Check result:** not-required

## Handoff

Review the active spec and the complete `3ebf3622447605e85aa2209bafba0be435e0a0e6..83f4442fd56aa0fa6ee39d56ee8e196dcf76c39f` delta in a fresh
session or isolated subagent without the builder conversation. Run all Audit lenses from scratch.
Run Check when required above. Do not edit product code, accept findings, or
reuse the existing findings as the review scope.

## Commands

All Terraform commands ran on a scratch copy from `git archive 83f4442`, not in the checkout, so the checkout's `.terraform` folders stayed untouched.

- `terraform fmt -check -recursive` (root of the scratch copy, whole target tree): pass
- `terraform init -backend=false -plugin-dir=<repo>/examples/linux-vm/.terraform/providers` (scratch `modules/storage-account`, azurerm 5.12.0 from the mirror): pass
- `terraform validate` (scratch `modules/storage-account`): pass
- `terraform test` (scratch `modules/storage-account`, mocked provider): pass, 41 passed, 0 failed
- Scratch boundary probes of `sa_private_endpoint` with `terraform test`: 12 inputs, results under Evidence
- Scratch composition probe with subnet and zone IDs unknown at plan, with `terraform test`: pass for a valid zone; a wrong zone fails during apply as intended
- Scratch mutation run of the endpoint code with `terraform test`: 21 mutants, 14 failed the suite, 7 survived (F-13)
- `terraform init` and `terraform test` in the checkout: not run, per the review's environment note
- Live `terraform plan` or `terraform apply`: unavailable, no Azure subscription in this offline review
- Linter or security scanner: unavailable, the project declares none and `tflint`, `tfsec` and `checkov` are not installed

## Evidence

- Freshness confirmed before review: `HEAD` equals the target, `main` still gives the recorded merge base, the spec hash matches its tracked file, and only `blueprint/context/review.md` differs from the target.
- All 7 delta paths reviewed: `CHANGELOG.md`, `blueprint/context/current-feature.md`, and the module's `README.md`, `main.tf`, `outputs.tf`, `variables.tf` and `tests/storage.tftest.hcl`. All spec steps, the resource table and the expected test runs match the code.
- Inputs rejected at plan by the variable validation: wrong-case zone name, trailing slash, a zone name with non-literal dots. Rejected at plan by the provider's ID parsers: empty or malformed zone and subnet IDs, and a null `subnet_id`. Accepted: `privatelink.blob.core.usgovcloudapi.net`, and `privatelink.blob.evil`, which the spec's open suffix allows for a trusted caller.
- `count` stays known with unknown subnet and zone IDs, so the first apply of the README's composition plans and applies under the mock.
- Security: the endpoint adds no public exposure, makes no change to `sa_public_network_access_enabled` or `sa_network_rules`, and the README says public access stays open. No secrets in the delta.
- Performance: one optional resource, with no repeated or unbounded work.
- Mutants that failed the suite include the FileStorage precondition, the zone validation, subresource, manual approval, all three names, tags, subnet, zone group and `sa_private_endpoint_id`.
- Nothing was found that blocks this checkpoint. F-13 and F-14 are P2, and no P0 or P1 finding is `open` or `fixed`. F-08 to F-12 are out of this feature's scope under the spec and were not changed.

## Findings

- F-13 [P2] open: Tests don't pin which account the private endpoint connects to
- F-14 [P2] unverified: The private-only note may strand off-network Terraform runners

## Remaining risk

- No live plan or apply was available, so working name resolution, the connection's automatic approval and Azure's acceptance of the endpoint are unproven, as the spec already states.
- The real value of `sa_private_endpoint_ip` is unproven: the mock returns a generated value, and the test only checks non-null (F-13).
- Private-only access from a runner outside the vnet is unproven (F-14).
- A zone ID that is unknown at plan, such as the README's `azurerm_private_dns_zone.blob.id`, can only be validated during apply.
- Unavailable commands: live `terraform plan` and `terraform apply`, and any linter or security scanner. `terraform init` and `terraform test` ran only on a scratch copy, not in the checkout.
- Only `modules/storage-account` was tested, because it is the only module in the delta. Other modules were checked by `fmt` only.
- F-08, F-09 and F-12 remain unverified, and F-10 and F-11 remain open at P2 and P3 from feature 6a.

## Try it now

Needs network access to download the provider. It deletes only the ignored
`.terraform` cache, which may hold a stale provider symlink.

```bash
rm -rf modules/storage-account/.terraform
terraform -chdir=modules/storage-account init -backend=false
terraform -chdir=modules/storage-account test
```

Expected final line: `Success! 41 passed, 0 failed.`
