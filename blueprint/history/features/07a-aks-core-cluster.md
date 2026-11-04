# Feature: AKS core cluster

**From build-plan:** feature 7a
**Build attempt:** 1
**Status:** verified
**Branch:** feature/aks-core-cluster

## Goal

Fill the empty `modules/aks` with an AKS cluster that follows the library's rules:
it deploys into an existing resource group and a vnet subnet, is private by default,
uses Entra ID for access with local accounts off, and fails at plan time on inputs
Azure would reject. Workload identity, ACR pull, Container Insights and the Key Vault
secrets CSI driver are available, and each stays off unless the caller turns it on.

## In scope

- `azurerm_kubernetes_cluster` with one default (system) node pool in the caller's
  subnet (`subnet_id`, typically `module.vnet.subnet_ids["aks"]`).
- **API access:** private cluster by default, with AKS managing the private DNS zone
  (`System`). A caller can turn private off. A public API then requires a non-empty
  `aks_api_authorized_ip_ranges`, so the API is never open to the internet.
- **Identity:** system-assigned by default. Passing user-assigned identity IDs
  switches to `UserAssigned`. A custom private DNS zone ID requires user-assigned,
  because Azure requires it.
- **Access control:** Kubernetes RBAC on, Entra ID integration with Azure RBAC, and
  `local_account_disabled = true`. Optional Entra admin group IDs and tenant ID.
- **Networking:** Azure CNI Overlay (`network_plugin = "azure"`,
  `network_plugin_mode = "overlay"`) with the Cilium data plane and Cilium network
  policy. Optional pod CIDR, service CIDR, DNS service IP and outbound type.
- **Upgrades:** automatic upgrade channel `patch` and node OS channel `NodeImage` by
  default, both changeable within Azure's allowed values.
- **Optional integrations, each off by default:**
  - workload identity, which also turns on the OIDC issuer
  - ACR pull: an `AcrPull` role assignment for the kubelet identity on a given registry
  - Container Insights: `oms_agent` with managed-identity auth, given a Log Analytics
    workspace ID
  - Key Vault secrets CSI driver, with secret rotation and an optional interval
- Outputs, a README with generated docs, offline tests, a CHANGELOG entry, and an
  overview composition row for vnet → aks.

## Out of scope

- Extra user node pools. They are feature 7b.
- Creating the vnet, subnet, Log Analytics workspace, registry, key vault, private DNS
  zone or user-assigned identities. Callers pass their IDs.
- Role assignments other than ACR pull, including Network Contributor for the cluster
  identity on the subnet and Key Vault roles for the CSI identity. Callers grant these.
- Host encryption, Windows node pools, the service-principal identity model, kubenet,
  flat Azure CNI, Azure Policy, image cleaner, maintenance windows, cost analysis and
  long-term support.
- A kubeconfig output. With local accounts off, callers use `az aks get-credentials`
  and `kubelogin`.
- Live `plan`/`apply` against Azure. That happens in the separate live-infra repo.

## Build loop

The user normally writes module files by hand. For this feature the user explicitly
asked Claude to write the whole module from scratch, checked against azurerm 5.12.0
through the Terraform MCP server. Otherwise, for each step, Claude reviews the user's diff
against the step's **Done when**, points out bugs, non-idiomatic code, security issues
and breaking changes with a one-line reason, and shows a snippet only for a specific
fix. Claude edits module files only when the user explicitly asks for that edit.
Claude may edit the blueprint docs, `CHANGELOG.md` and the overview.

`workflow.stepReview` is `feature`, so passing steps continue without a pause, and
`checkpointCommits` is `disabled`. `/complete` makes the one feature commit.
Narrow check while iterating:
`terraform -chdir=modules/aks init -backend=false && terraform -chdir=modules/aks validate && terraform -chdir=modules/aks test`.
Run `sh scripts/verify.sh` once at the end.

## Build steps

- [x] 1. **Cluster core.** Add `versions.tf`, then the core inputs, cluster and outputs:
  - private by default with `private_dns_zone_id = "System"`
  - system-assigned identity
  - Entra ID RBAC with local accounts off
  - Azure CNI Overlay with Cilium
  - upgrade channels
  - the system node pool, with autoscaling and a derived `temporary_name_for_rotation`
  - validations for name, DNS prefix, SKU tier, node pool name and size limits, CIDRs
    and upgrade channels
  - tests

  **Done when:** `validate` passes. A default plan test asserts a private cluster,
  local accounts off, Azure RBAC on, overlay plus Cilium, and the system pool in
  `subnet_id`. Each validation has an `expect_failures` test.
- [x] 2. **Public API option and user-assigned identity.**
  - `aks_private_cluster_enabled = false` with `aks_api_authorized_ip_ranges`, the
    `api_server_access_profile` block
  - user-assigned identity IDs
  - a custom private DNS zone ID
  - preconditions on the cluster:
    - a public cluster needs at least one range
    - a private cluster can't have ranges
    - a custom DNS zone ID needs user-assigned identity
    - `service_cidr` and `dns_service_ip` must be set together
  - `aks_identity_principal_id` returns `null` with user-assigned identity

  **Done when:** plan tests cover a public cluster with ranges, and one test per
  rejected combination.
- [x] 3. **Workload identity, Container Insights and Key Vault CSI.** Add the three
  toggles and their blocks. Add `aks_oidc_issuer_url`, which is `null` unless workload
  identity is on. Validate the workspace ID and the rotation interval format.
  **Done when:** plan tests show each block present only when its input is set, and
  each malformed ID or interval is rejected.
- [x] 4. **ACR pull.** Add `aks_acr_pull` (`{ registry_id }`, nullable, ID format validated), and an
  `azurerm_role_assignment` (`AcrPull`, kubelet identity object ID) that exists only
  when it's set.
  **Done when:** a plan test shows none by default and a malformed ID is rejected.
  Revised during build: Terraform's mock provider can't fill the computed
  `kubelet_identity` block, so a plan with `aks_acr_pull` set can't run offline. The
  assignment's scope and principal are proven only by `validate` and a live run.
- [x] 5. **Docs.**
  - `README.md` with usage and the generated terraform-docs section
  - the CHANGELOG `[Unreleased]` entry
  - the composition contract row in the overview: vnet `subnet_ids["<name>"]` → aks
    `subnet_id`, and aks `aks_kubelet_identity_object_id` → role assignments
  - the README notes the roles callers must grant

  **Done when:** `sh scripts/verify.sh` prints `All checks passed.` with
  `modules/aks` included, which covers fmt, validate, tflint, Trivy HIGH/CRITICAL,
  terraform-docs and tests.

- [x] 6. **Review repairs (F-37 to F-42).** The first independent review requested
  changes:
  - F-37 (P1): `aks_acr_id` drove `count`, so a registry created in the same run
    failed plan. It becomes `aks_acr_pull = { registry_id }`, and `count` depends only
    on whether the object is set.
  - F-38: preconditions for `dns_service_ip` inside `service_cidr`, and for the
    `node-image` upgrade channel needing the `NodeImage` node OS channel.
  - F-39: authorized ranges reject `/0`.
  - F-40: the rotation pool name switches to a `rot` suffix when `tmp` would repeat
    the pool name.
  - F-41: `vm_size` accepts constrained-vCPU sizes such as `Standard_E4-2ds_v5`.
  - F-42: tests for a 55-character DNS prefix, `max_count = 1001` and
    `min_count = 1.5`.

  **Done when:** each repair has a test (45 pass), and a scratch root that creates a
  registry in the same plan no longer fails with `Invalid count argument`. It then
  stops at the known mock limit on `kubelet_identity`, which is known after apply on
  real azurerm. Verify passes.

## Files / areas

- `modules/aks/versions.tf`, `variables.tf`, `main.tf`, `outputs.tf`, `README.md`,
  `tests/aks.tftest.hcl`. The user writes all of these.
- `CHANGELOG.md` and `blueprint/context/project-overview.md` (composition table).
- No CI changes: `scripts/verify.sh` already picks up any `modules/*/` folder with
  `.tf` files, on all four platforms.

## Data / contracts

Provider: azurerm `">= 5.12, < 6.0"` (the user asked for 5.12.0; the floor is the version
the arguments were checked against), Terraform `">= 1.17"`. Argument names were checked
against the azurerm 5.12.0 docs and `terraform validate` on v5.12.0, which also showed that
5.x requires a `node_provisioning_profile` block; the module sets `mode = "Manual"`.

| Input | Type and default | Rule |
|---|---|---|
| `resource_group_name`, `location` | string, required | Passed straight through |
| `subnet_id` | string, required | Node subnet ID; validated as a subnet resource ID |
| `tenant_id` | string, `null` | Entra tenant; null uses the subscription's tenant |
| `aks_name` | string, required | 1-63 characters: letters, digits, `-`, `_`; starts and ends with a letter or digit |
| `aks_dns_prefix` | string, `null` | Null uses `aks_name`. The effective value is 1-54 characters: letters, digits, `-`; starts and ends with a letter or digit (precondition, because the default comes from the name) |
| `aks_kubernetes_version` | string, `null` | Null means AKS's current default at creation |
| `aks_sku_tier` | string, `"Free"` | `Free`, `Standard` or `Premium` |
| `aks_private_cluster_enabled` | bool, `true`, not nullable | |
| `aks_private_dns_zone_id` | string, `"System"` | `System`, `None` or a private DNS zone ID; a zone ID needs `aks_identity_ids` |
| `aks_api_authorized_ip_ranges` | set(string), `[]`, not nullable | Valid IPv4 CIDRs, never a `/0`; non-empty if and only if the cluster is public |
| `aks_identity_ids` | list(string), `[]`, not nullable | Empty means `SystemAssigned`, otherwise `UserAssigned`; at most one ID, because AKS supports only one |
| `aks_admin_group_object_ids` | list(string), `[]`, not nullable | Entra group object IDs given cluster admin |
| `aks_system_node_pool` | object, required | `name` (optional, `"system"`; 1-12 lowercase letters and digits, starting with a letter), `vm_size` (required), `min_count` (optional, 2), `max_count` (optional, 5), `zones` (optional, `null`), `os_disk_type` (optional, `"Managed"`: `Managed` or `Ephemeral`). 1 ≤ min ≤ max ≤ 1000 |
| `aks_network` | object, `{}`, not nullable | `pod_cidr`, `service_cidr`, `dns_service_ip` (optional, `null`, which means Azure defaults), `outbound_type` (optional, `"loadBalancer"`: `loadBalancer`, `userDefinedRouting`, `managedNATGateway` or `userAssignedNATGateway`) |
| `aks_automatic_upgrade_channel` | string, `"patch"` | `patch`, `rapid`, `node-image`, `stable` or `none` |
| `aks_node_os_upgrade_channel` | string, `"NodeImage"` | `Unmanaged`, `SecurityPatch`, `NodeImage` or `None` |
| `aks_workload_identity_enabled` | bool, `false`, not nullable | On sets `oidc_issuer_enabled` and `workload_identity_enabled` |
| `aks_log_analytics_workspace_id` | string, `null` | Set turns on `oms_agent` with `msi_auth_for_monitoring_enabled = true` |
| `aks_key_vault_secrets_provider` | object, `null` | `{ secret_rotation_interval = optional(string, "2m") }`; set turns on the driver with rotation |
| `aks_acr_pull` | object, `null` | `{ registry_id = string }`; set creates the `AcrPull` assignment. An object rather than a bare ID, so the on/off decision is known at plan even when the registry is created in the same run |
| `aks_tags` | map(string), `{}`, not nullable | On the cluster |

| Output | Value |
|---|---|
| `aks_id`, `aks_name` | Cluster ID and name |
| `aks_fqdn` | `private_fqdn` when private, `fqdn` when public |
| `aks_node_resource_group` | The resource group AKS created for the nodes |
| `aks_kubelet_identity_object_id` | Kubelet identity object ID, for role assignments |
| `aks_identity_principal_id` | System-assigned principal ID; `null` with user-assigned |
| `aks_oidc_issuer_url` | `null` unless workload identity is on |

No secrets pass through this module. Nothing is `sensitive`, and no kubeconfig is
output.

## Testing

`terraform test` with `mock_provider "azurerm"`, offline, in
`modules/aks/tests/aks.tftest.hcl`. Use plan by default. Use apply only where a
computed value is asserted: the ACR assignment's principal, and outputs that read
the identity or kubelet blocks. Those need `mock_resource` defaults with parseable
IDs and the kubelet identity block.

- Every validation and precondition has an `expect_failures` test:
  - name and DNS prefix format and length
  - SKU and channel values
  - node pool name, and min/max counts
  - CIDR syntax
  - public without ranges, and private with ranges
  - custom DNS zone without user-assigned identity
  - service CIDR without DNS IP
  - malformed workspace, ACR and subnet IDs
  - rotation interval format
- Default plan assertions:
  - a private cluster with `private_dns_zone_id = "System"`
  - local accounts off, Azure RBAC on
  - overlay, Cilium data plane and policy
  - no `oms_agent`, no CSI block, no role assignment, workload identity off
- Not tested: whether Azure accepts the configuration. That needs a live plan or
  apply in the live-infra repo.

## Notes for the AI

- Review only for `modules/aks`, with a one-line reason per point; never write
  module code unless asked. The user is learning, so explain why, briefly.
- Choices made here, which the user can change:
  - Cilium for the data plane and network policy
  - `Free` SKU tier
  - system pool autoscaling from 2 to 5 nodes
  - upgrade channels `patch` and `NodeImage`
  - outbound type `loadBalancer`
  - `vm_size` is required, with no default
  - no CriticalAddonsOnly taint on the system pool, because until 7b adds user pools
    workloads have to run there
- `temporary_name_for_rotation` must follow node pool name rules. Derive it from the
  pool name, for example the first 9 characters plus `tmp`, and test the derived
  value.
- Trivy runs at HIGH and above in Verify, and those must be fixed, not ignored.
  Trivy's MEDIUM AKS logging check will fire while Container Insights is off by
  default. Before tagging `aks/v1.0.0`, the MEDIUM scan has to pass or the user
  accepts it.
- Unverified until a live run:
  - whether a system-assigned identity in a caller's vnet needs Network Contributor
    on the subnet granted first
  - whether the private cluster's `System` DNS zone resolves from the caller's
    network

  The README states both as caller responsibilities.


<!-- blueprint:completion {"schemaVersion":2,"specBytes":14479,"specSha256":"45cf27003ce3574f2bd6572a470eb69ad2ee73e2c5d66258bbc44e7cb31e86c9","branch":"refs/heads/feature/aks-core-cluster","head":"10a234b43d71c920a767229c3943f56eeed80b4f","baseRef":"refs/heads/main","baseCommit":"63a3ecb0120c482eb0bd1858473c3ea91157a2e9","sourceTree":"2d8468c5de743858db7f0dbf5c24fe69eee95080","landing":"local-merge","absentOptional":[]} -->

## Findings

### 7a/F-37 [P1] closed - aks_acr_id from a registry in the same run fails plan with "Invalid count argument"

**File:** modules/aks/main.tf:122
**Found:** 2026-11-04 by /audit independent (scope: current; lens: quality)
**Why it matters:** `count = var.aks_acr_id == null ? 0 : 1` depends on the ID's value, so it is unknown when the registry is created in the same apply. A scratch root that creates `azurerm_container_registry.acr` and passes `aks_acr_id = azurerm_container_registry.acr.id`, which is the README usage example (`modules/aks/README.md:30`), fails plan with `Invalid count argument` at this line. Callers must use `-target` or a two-phase apply. The workspace ID has no such problem, because a `dynamic` block tolerates an unknown `for_each` (probe planned cleanly).
**Suggested fix:** Make the on/off decision independent of the ID value, as `storage-account` does with `sa_private_endpoint`: for example a nullable `aks_acr_pull = { registry_id = string }` object with `count = var.aks_acr_pull == null ? 0 : 1`, or a separate bool. Add a test whose ACR ID comes from a resource planned in the same run. The module is unreleased, so the interface change has no existing callers.
**Resolution:** Fixed 2026-11-04 by /implement (step 6): input is now `aks_acr_pull = { registry_id }` and `count` depends only on whether it's set. A scratch root creating `azurerm_container_registry` in the same plan failed with `Invalid count argument` on 1cb9fce and no longer does; it then stops at the mock provider's empty `kubelet_identity` (`Invalid index`), which real azurerm reports as known after apply. `rejects_bad_acr_registry_id` covers validation. Closed 2026-11-04 by /audit independent (re-review of 10a234b): `count` at main.tf:137 reads only `var.aks_acr_pull == null`; a fresh scratch root with a same-run `azurerm_container_registry` now stops at main.tf:141 `Invalid index` (mock limit), not `Invalid count argument`. The provider schema marks `kubelet_identity.object_id` optional+computed, so a real plan carries it as unknown. No new defect.

### 7a/F-38 [P2] closed - Two cross-field combinations Azure rejects still pass plan

**File:** modules/aks/main.tf:73
**Found:** 2026-11-04 by /audit independent (scope: current; lens: quality)
**Why it matters:** The spec's goal is to fail at plan time on inputs Azure would reject, and the coding standards ask for a precondition on cross-variable checks. The azurerm 5.12.0 docs say `node_os_upgrade_channel` must be `NodeImage` when `automatic_upgrade_channel` is `node-image`, yet `aks_automatic_upgrade_channel = "node-image"` with `aks_node_os_upgrade_channel = "SecurityPatch"` plans cleanly (probe). Likewise `aks_network = { service_cidr = "172.16.0.0/16", dns_service_ip = "10.9.9.9" }` plans, though AKS requires the DNS service IP inside the service CIDR.
**Suggested fix:** Add two preconditions on the cluster: `var.aks_automatic_upgrade_channel != "node-image" || var.aks_node_os_upgrade_channel == "NodeImage"`, and, when both are set, `cidrhost("${dns_service_ip}/${split("/", service_cidr)[1]}", 0) == cidrhost(service_cidr, 0)`. Add an `expect_failures` test for each.
**Resolution:** Fixed 2026-11-04 by /implement (step 6): two preconditions, `dns_service_ip` inside `service_cidr` and `node-image` requiring `NodeImage`; tests `rejects_dns_service_ip_outside_service_cidr` and `rejects_node_image_channel_without_node_image_os_channel`. Closed 2026-11-04 by /audit independent (re-review of 10a234b): preconditions at main.tf:117-131 are correct for IPv4 (both sides normalised through `cidrhost(..., 0)`, `try` guards a missing prefix); both tests pass.

### 7a/F-39 [P2] closed - A public API accepts 0.0.0.0/0, so it can still be open to the internet

**File:** modules/aks/variables.tf:100
**Found:** 2026-11-04 by /audit independent (scope: current; lens: security)
**Why it matters:** The spec and README say a public API needs authorized ranges "so the API is never open to the internet", but the validation only checks CIDR syntax. `aks_private_cluster_enabled = false` with `aks_api_authorized_ip_ranges = ["0.0.0.0/0"]` plans cleanly (probe), which satisfies the precondition while removing the protection. `storage-account` already rejects `0.0.0.0/0` in its IP rules (`ip_rule_everything_fails`), so this is also inconsistent with the library.
**Suggested fix:** Reject `/0` (or any prefix shorter than a chosen minimum such as `/8`) in the variable validation, name the rule in the error message, and add a rejecting test. No current requirement is lost.
**Resolution:** Fixed 2026-11-04 by /implement (step 6): authorized ranges must have a prefix length above 0; test `rejects_open_authorized_range`. Closed 2026-11-04 by /audit independent (re-review of 10a234b): `0.0.0.0/0` is rejected at variables.tf:100 and the test passes. Splitting the internet into two `/1` ranges still plans (probe); that is a deliberate bypass, not the accidental opening this finding covered.

### 7a/F-40 [P3] closed - The derived rotation pool name can equal the system pool name

**File:** modules/aks/main.tf:7
**Found:** 2026-11-04 by /audit independent (scope: current; lens: quality)
**Why it matters:** `"${substr(name, 0, 9)}tmp"` returns the pool name itself for any valid 12-character name ending in `tmp`, for example `abcdefghitmp` (probe). A resize or other rotation would then try to create a temporary pool with the name of the existing one and fail at apply.
**Suggested fix:** Add a check that the pool name doesn't end in `tmp` at 12 characters, or derive a different suffix when the name already ends in `tmp`, and test that case.
**Resolution:** Fixed 2026-11-04 by /implement (step 6): the suffix is `rot` when `<first 9>tmp` equals the pool name; test `rotation_name_differs_from_a_pool_name_ending_in_tmp` (`abcdefghitmp` -> `abcdefghirot`). Closed 2026-11-04 by /audit independent (re-review of 10a234b): only a 12-character name ending in `tmp` can equal `<first 9>tmp`, and that case now gets `rot`, which can't equal it.

### 7a/F-41 [P3] closed - vm_size validation rejects constrained-vCPU sizes

**File:** modules/aks/variables.tf:157
**Found:** 2026-11-04 by /audit independent (scope: current; lens: quality)
**Why it matters:** `^Standard_[A-Za-z0-9_]+$` rejects sizes with a hyphen, such as `Standard_E4-2ds_v5` (probe), which are real Azure VM sizes. The `virtual-machine` module only checks the `Standard_`/`Basic_` prefix. Missing validation: whether AKS node pools accept constrained-vCPU sizes, which needs Azure docs or a live plan.
**Suggested fix:** If AKS accepts them, allow `-` in the pattern, or check only the `Standard_` prefix like `virtual-machine`.
**Resolution:** Fixed 2026-11-04 by /implement (step 6): `vm_size` allows `-`, so constrained-vCPU sizes such as `Standard_E4-2ds_v5` pass; test `constrained_vcpu_vm_size`. Azure's acceptance of a given size for AKS is still only provable live. Closed 2026-11-04 by /audit independent (re-review of 10a234b): pattern at variables.tf:157 accepts `-`; test passes.

### 7a/F-42 [P3] closed - Some validation edges in the spec's Testing list have no test

**File:** modules/aks/tests/aks.tftest.hcl:267
**Found:** 2026-11-04 by /audit independent (scope: current; lens: tests)
**Why it matters:** The spec lists "name and DNS prefix format and length" and "min/max counts", but no run rejects an explicit `aks_dns_prefix` over 54 characters, `max_count` above 1000, or a fractional count. Scratch probes show the module rejects all three today, so this is missing regression protection, not a defect. The five preconditions also share one `expect_failures` target, so a rejecting run passes if any precondition fails; each run keeps the others satisfied, so this is acceptable as written.
**Suggested fix:** Add rejecting runs for a 55-character `aks_dns_prefix`, `max_count = 1001` and `min_count = 1.5`.
**Resolution:** Fixed 2026-11-04 by /implement (step 6): tests `rejects_long_explicit_dns_prefix`, `rejects_max_count_above_1000`, `rejects_fractional_min_count`. Closed 2026-11-04 by /audit independent (re-review of 10a234b): all three runs exist and pass (45 passed).

## Independent review

# Independent Review

**Status:** passed
**Target commit:** 10a234b43d71c920a767229c3943f56eeed80b4f
**Base commit:** 63a3ecb0120c482eb0bd1858473c3ea91157a2e9
**Base ref:** main
**Spec hash:** 45cf27003ce3574f2bd6572a470eb69ad2ee73e2c5d66258bbc44e7cb31e86c9
**Prepared by:** claude
**Builder model:** claude-opus-5-5
**Requested reviewer:** claude
**Requested model:** claude-opus-5-5
**Requested execution:** automatic
**Requested at:** 2026-11-04T16:45:40Z
**Workflow:** regular
**Check required:** no

**Reviewer adapter:** claude
**Reviewer model:** claude-opus-5-5
**Reviewer context:** fresh subagent
**Actual execution:** automatic
**Reviewed at:** 2026-11-04T17:46:59Z
**Scope:** current
**Lenses:** quality, security, performance, tests
**Verdict:** passed
**Check result:** not-required

## Commands

- `terraform -chdir=modules/aks init -backend=false && terraform -chdir=modules/aks validate`: pass
- `terraform -chdir=modules/aks test`: pass (45 passed, 0 failed)
- `sh scripts/verify.sh` (pinned tflint and terraform-docs on PATH): pass (`All checks passed.`)
- `sh scripts/trivy-scan.sh MEDIUM aks`: fail (AZU-0040 MEDIUM only, recorded as F-46; 0 HIGH/CRITICAL)
- `terraform test` in scratch roots calling the module by path: probes ran as intended

## Evidence

- Preconditions confirmed: HEAD and merge base with `main` match the request, spec SHA-256 matches, spec is tracked, only `findings.md` and `review.md` differ.
- Reviewed the full 63a3ecb..10a234b delta: `modules/aks/*`, tests, README, CHANGELOG, overview, build and project plans.
- Arguments checked against the saved azurerm 5.12.0 docs and `providers schema -json`.
- Scratch root with a same-run `azurerm_container_registry` stops at the mock `kubelet_identity` limit (main.tf:141), not `Invalid count argument`.
- Scratch probes: `/8` service CIDR, `managedNATGateway`, two `/1` authorized ranges and `1.33.2` with the patch channel all plan.

## Findings

- Closed: F-37, F-38, F-39, F-40, F-41, F-42
- Added: F-43 (P3 open), F-44 (P3 unverified), F-45 (P3 unverified), F-46 (P3 open), F-47 (P3 open)
- No P0 or P1 finding is open or fixed

## Remaining risk

- No live Azure plan or apply: whether Azure accepts the configuration, the AcrPull assignment's principal, Network Contributor needs and private DNS resolution remain unproven offline.
- The AcrPull assignment cannot be planned offline with `aks_acr_pull` set (mock provider limit).
- Trivy MEDIUM fails on AZU-0040 (F-46); it must be fixed or accepted by the user before tagging `aks/v1.0.0`.
- Two `/1` authorized ranges still cover the whole IPv4 internet; only a deliberate caller can do this.
- Check was not required and was not run.

## Try it now

1. Run the offline tests: `terraform -chdir=modules/aks init -backend=false && terraform -chdir=modules/aks test`.
   Expect `45 passed, 0 failed`. No Azure credentials are used.
2. In a scratch root module, call `modules/aks` with `aks_private_cluster_enabled = false`
   and no `aks_api_authorized_ip_ranges`, then run `terraform test` with
   `mock_provider "azurerm" {}`. Expect the plan to fail with the message that a public
   cluster needs at least one authorized range.
3. In the live-infra repo, run a real `plan` with the README example. Expect a private
   cluster, local accounts disabled, and `network_plugin_mode = "overlay"` with Cilium.
