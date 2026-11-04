# Findings

> **Generated file.** The findings ledger: review findings raised by `/audit`
> against the work in progress, each with a durable ID, severity (P0-P3), and
> status. `/implement` marks repaired findings `fixed`, a later `/audit` pass
> moves them to `closed`, and `/complete` refuses to land while any P0 or P1
> finding is `open` or `fixed`, then archives resolved findings with the work
> and resets this file.

### F-08 [P2] unverified - Premium StorageV2 accepts inputs Azure may reject

**File:** modules/storage-account/main.tf:53
**Found:** 2026-10-30 by /audit independent (scope: current; lens: quality)
**Why it matters:** `sa_account_tier = "Premium"` with the default `StorageV2` plans cleanly with `sa_file_shares` (probe run) and has no check against `ZRS`. Premium general-purpose accounts are expected to serve page blobs on LRS only, which would make both apply-time failures. Missing validation: Azure documentation or a live plan, neither available in this offline review.
**Suggested fix:** Confirm against Azure, then either add preconditions or drop Premium `StorageV2` from the accepted combinations.
**Resolution:** Still unverified after the independent review of 74f5080. Premium `StorageV2` with a share still plans under the mock. A search of the azurerm 5.12.0 binary for account-kind rejection strings found only `blob_properties` and `share_properties`, which neither confirms nor clears it. Azure documentation or a live plan is still needed. Terraform MCP docs (azurerm 5.12.0), 2026-10-30: `azurerm_storage_account` says `share_properties` works only on Standard `Storage`/`StorageV2` or Premium `FileStorage`, which supports the file-share half without proving it for `azurerm_storage_share`. Nothing documents ZRS on Premium `StorageV2`. Still unverified; needs a live plan.

### F-09 [P3] unverified - Endpoint outputs may return an empty string on single-service accounts

**File:** modules/storage-account/outputs.tf:11
**Found:** 2026-10-30 by /audit independent (scope: current; lens: quality)
**Why it matters:** The locked interface rule says outputs return `null`, never `""`, when a feature is off. `sa_primary_blob_endpoint` on `FileStorage` and `sa_primary_file_endpoint` on `BlockBlobStorage` pass through whatever the provider sets. Missing validation: a real apply, because the mocked provider cannot show this value.
**Suggested fix:** Check a real account. If empty, wrap the outputs in a null-on-empty conditional.
**Resolution:**

### F-10 [P2] open - Tests let security toggles and validation rules regress unnoticed

**File:** modules/storage-account/tests/storage.tftest.hcl:26
**Found:** 2026-10-30 by /audit independent (scope: current; lens: tests)
**Why it matters:** The coding standards require a passing test for validations, preconditions and locals that pick values. In a scratch copy, 30 single-line mutants were run against the suite: 6 failed it, 2 of the 24 survivors don't change behavior, and 22 are real gaps. Survivors that matter most: hard-coding `shared_access_key_enabled = true` (a caller's Entra-only opt-out is silently ignored), hard-coding `allow_nested_items_to_be_public = false`, ignoring `account_tier`, `account_kind`, `account_replication_type`, `bypass` or `default_action`, removing `192.168.0.0/16` from the private-range check, allowing `/31`, allowing fractional retention or quota, raising each upper bound by one, fixing the local access tier to `Hot`, and giving Premium non-FileStorage accounts an access tier. The module's behavior is correct today: boundary probes rejected `192.168.0.1`, `/31` and fractional values, so this is missing protection, not a defect.
**Suggested fix:** Add assertions for `sa_shared_access_key_enabled = false`, `sa_allow_nested_items_to_be_public = true`, a non-default tier, kind and replication, `sa_access_tier = "Cool"`, a null access tier on BlockBlobStorage and Premium StorageV2, and custom `bypass` and `default_action`. Add rejecting runs for `192.168.0.1`, `/31`, fractional and over-limit retention and quota, and a 25-character `sa_name`. Add accepting runs for Premium ZRS and an explicit `Premium` share on FileStorage, a rejecting run for an `access_type = "blob"` container without the flag, and assert `sa_id`, `sa_name` and the endpoint outputs in the `command = apply` run.
**Resolution:**

### F-11 [P3] open - Coding standards lag the raised floor and the new module

**File:** blueprint/context/coding-standards.md:39
**Found:** 2026-10-30 by /audit independent (scope: current; lens: quality)
**Why it matters:** Step 7 rewrote the version rule but left line 39, "Validations don't short-circuit `||`". A probe on Terraform 1.17.1 shows `var.x == null || var.x.a == "ok"` plans cleanly with `x` null, so the rule is now false and keeps prescribing `coalesce` and `try` guards. Line 30 omits the `sa_` prefix and line 114 still says only `modules/virtual-machine` has tests. Separately, the `sa_file_shares` description (`modules/storage-account/variables.tf:169`) omits the allowed `access_tier` values, what null means, and the FileStorage share rules, which the standard's description rule and its `sa_containers` sibling cover.
**Suggested fix:** Update those three lines and the `sa_file_shares` description. Existing guards still work, so removing them is optional cleanup and no current requirement would be lost.
**Resolution:**

### F-12 [P3] unverified - IP rules accept non-public addresses despite the "public IPv4" contract

**File:** modules/storage-account/variables.tf:115
**Found:** 2026-10-30 by /audit independent (scope: current; lens: security)
**Why it matters:** The error message and spec say `ip_rules` must be public IPv4, but the check excludes only RFC 1918 ranges. Probes accepted `0.0.0.0`, `127.0.0.1`, `169.254.1.1`, `100.64.0.1`, `224.0.0.1`, `255.255.255.255` and the leading-zero `011.1.2.3`. If Azure rejects any of these, the locked plan-time rule is broken. Accepting them grants no access beyond what the caller asked for, so this is a validation accuracy question and not an exposure. Missing validation: Azure documentation or a live plan, neither available in this offline review.
**Suggested fix:** Confirm against Azure. Then either add the rejected ranges and forbid leading zeros in the regex, or reword the message to "non-private".
**Resolution:** Terraform MCP docs (azurerm 5.12.0), 2026-10-30: `ip_rules` documents only IPv4, no /31 or /32, and no RFC 1918 ranges, all of which the module enforces. The other addresses aren't documented either way. Still unverified; needs a live plan.

### F-13 [P2] open - Tests don't pin which account the private endpoint connects to

**File:** modules/storage-account/tests/storage.tftest.hcl:406
**Found:** 2026-10-30 by /audit independent (scope: current; lens: tests)
**Why it matters:** The coding standards require a passing test for validations and values the module derives, and this feature exists to change a network boundary. In a scratch copy, 21 single-line mutants of the endpoint code were run against the suite. 14 failed it and 7 survived. The most important survivor points `private_connection_resource_id` at a different storage account, and the suite stays green. Five others are real gaps: `resource_group_name` and `location` on the endpoint, `sa_private_endpoint_ip` returning the endpoint's name (line 452 only checks non-null), unescaped dots in the zone regex, and narrowing the zone suffix to `core.windows.net`, which removes the sovereign-cloud support the spec asks for. The seventh, dropping the regex's `$`, is not counted as a gap because the provider's ID parser should still reject what it would admit at plan. The module's behavior is correct today, so this is missing protection, not a defect.
**Suggested fix:** In the `command = apply` run at line 438, assert `private_connection_resource_id == output.sa_id` and that `sa_private_endpoint_ip` equals the resource's `private_ip_address`. In the plan run at line 406, assert `resource_group_name` and `location`. Add one accepting run for a `privatelink.blob.core.usgovcloudapi.net` zone and one rejecting run for a zone name with non-literal dots, such as `privatelinkXblobXcore`.
**Resolution:**

### F-14 [P2] unverified - The private-only note may strand off-network Terraform runners

**File:** modules/storage-account/README.md:60
**Found:** 2026-10-30 by /audit independent (scope: current; lens: quality)
**Why it matters:** The README tells callers to set `sa_public_network_access_enabled = false` for private-only access, and says nothing about where Terraform must run. azurerm 5.12.0 has a `features.storage.data_plane_available` provider setting and a storage accounts data plane client. If `azurerm_storage_account` reads the data plane by default, a runner outside the vnet could fail on plan or apply after following this note. Missing validation: a live apply with public access disabled from a runner outside the vnet, or provider source or documentation. This offline review has none of them, and the binary search did not show the default or when the client is used.
**Suggested fix:** Confirm with one live apply. If it fails, add one README line saying the runner needs network access to the endpoint, or that callers set `data_plane_available = false` in their provider, whichever the test proves works.
**Resolution:** Terraform MCP docs (azurerm 5.12.0), 2026-10-30: the Features Block guide says `data_plane_available` decides whether `azurerm_storage_account` uses data plane APIs, defaults to `true`, and that `false` bypasses availability checks for accounts not using `queue_properties` or `static_website`. This module uses neither, so the risk is more likely and the likely fix is that provider setting. The same risk applies to `default_action = "Deny"`, which makes the README claim at `modules/storage-account/README.md:42` incomplete. Still unverified; needs a live apply. Independent review of d461d45, 2026-11-02: this fix moves the risk onto the default path, because `sa_network_rules` now defaults to `{}`, so an account with no network inputs gets `default_action = "Deny"`, not only one that opted in. The mocked provider can't show the data plane call, and neither the README nor the CHANGELOG entry mentions runner reachability. The spec already defers this to the live test repo. If the live apply fails, the README note and the CHANGELOG Breaking entry both need the outcome.

### F-15 [P2] open - NSG rule ports and names pass plan though Azure documents narrower values

**File:** modules/vnet/variables.tf:94
**Found:** 2026-10-30 by /audit (scope: modules; lens: quality)
**Why it matters:** A probe with `destination_port_range = "abc"`, `source_address_prefix = "not-a-cidr"` and rule name `bad name!` plans cleanly under the mocked provider. The azurerm 5.12.0 docs allow only an integer, a range of 0-65535 or `*` for ports, and a CIDR, IP range, `*` or tag for prefixes. This breaks the locked rule that inputs Azure would reject fail at plan time, leaving subnets and the NSG created when a rule fails at apply. The rejection itself comes from the docs, since no live apply ran.
**Suggested fix:** Validate both port fields against `*` or `0-65535` and ranges, and rule keys with the subnet name regex. Leave `source_address_prefix` unchecked or loose, because service tags make a strict check brittle.
**Resolution:**

### F-16 [P2] open - Four modules with validation logic have no tests

**File:** modules/vnet/main.tf:28
**Found:** 2026-10-30 by /audit (scope: modules; lens: tests)
**Why it matters:** The standards name validations and preconditions as what to test, but `vnet`, `key-vault`, `service-principal` and `resource-group` have no `tests/` folder. The riskiest is the `vnet` CIDR containment precondition and NSG priority uniqueness, followed by the `service-principal` secret rotation date and the `key-vault` RBAC and access policy precondition. In `virtual-machine`, the no-SSH-key, both-image-inputs, identity mismatch and 80-character disk name rules also have no rejecting run.
**Suggested fix:** Add mocked `tests/` suites, starting with `vnet`. `service-principal` needs the azuread and time providers, which aren't in the local provider mirror.
**Resolution:** Independent review of d461d45, 2026-11-02: `key-vault` is still without a suite, as the spec records. Its new default is guarded by trivy: in a scratch copy, setting `kv_network_acls` back to null or the `default_action` default to `Allow` both fail trivy at HIGH. Nothing in the repo guards the `null` opt-out. A scratch mocked test passed for the default (Deny, AzureServices) and for null (no block), so the behavior is correct today.

### F-17 [P3] open - SSH key validation and message advertise ECDSA, which Azure doesn't support

**File:** modules/virtual-machine/variables.tf:97
**Found:** 2026-10-30 by /audit (scope: modules; lens: quality)
**Why it matters:** The validation accepts `ecdsa-sha2-*` and its error message recommends it. The azurerm docs allow only `ssh-rsa` and `ssh-ed25519`, and a probe shows the provider rejects an ECDSA key at plan. The failure is still at plan time, so this is a misleading contract and not an apply-time break.
**Suggested fix:** Drop `ecdsa-sha2-nistp(256|384|521)` from the regex and the message. No current requirement is lost, because such a key can't deploy.
**Resolution:**

### F-18 [P3] open - resource-group drifts from the location and provider pin standards

**File:** modules/resource-group/main.tf:3
**Found:** 2026-10-30 by /audit (scope: modules; lens: quality)
**Why it matters:** The standards say to pass `location` straight to the provider without normalizing or re-validating it, and to pin azurerm to `>= 5.0, < 6.0`. This module normalizes and validates `location` (`variables.tf:16`) and allows azurerm `>= 4.0` (`versions.tf:7`). The overview's open questions already list the pin mismatch.
**Suggested fix:** Needs your decision, because it changes shipped behavior: remove the normalization and validation and raise the pin, or record this module as an exception in the standards. Removing them loses the `"West Europe"` normalization of the `location` output.
**Resolution:**

### F-19 [P3] unverified - Subnet and federated credential limits may fail only at apply

**File:** modules/vnet/variables.tf:66
**Found:** 2026-10-30 by /audit (scope: modules; lens: quality)
**Why it matters:** Probes plan cleanly for a `/30` subnet, overlapping subnets and a `GatewaySubnet` with the default `associate_nsg = true`. Azure is expected to reject all three. `service-principal` also accepts several `audiences`, where Entra is expected to allow one. Missing validation: the provider docs don't state these limits, so this needs Azure documentation or a live plan.
**Suggested fix:** Confirm against Azure, then add a prefix-length check, an overlap precondition and a rejection for `GatewaySubnet` with an NSG, and limit `audiences` to one.
**Resolution:**

### F-20 [P3] unverified - Storage docs say network_rules need a rule and Deny, but the module allows neither

**File:** modules/storage-account/variables.tf:97
**Found:** 2026-10-30 by /audit (scope: modules; lens: quality)
**Why it matters:** An azurerm 5.12.0 note says that with `network_rules`, one of `ip_rules` or `virtual_network_subnet_ids` must be set and `default_action` must be `Deny`. The same page lists `Allow` as valid for `default_action`, so the note may be stale. The module accepts `default_action = "Allow"` and `sa_network_rules = {}`. Missing validation: a live plan.
**Suggested fix:** Confirm with a live plan. If Azure rejects them, add the checks; otherwise leave the module as is and mark this `invalid`.
**Resolution:** Independent review of d461d45, 2026-11-02: `sa_network_rules = {}` is now the default, so the combination this note questions (no `ip_rules` and no `virtual_network_subnet_ids`) is what every default deployment sends, and the question now decides whether the module's defaults apply at all. Mocked tests can't answer it. Still unverified; add this case to the same live test as F-14.

### F-21 [P2] unverified - The default VM size change may not resize existing VMs, and may reject Gen 1 images

**File:** CHANGELOG.md:18
**Found:** 2026-11-02 by /audit independent (scope: current; lens: quality)
**Why it matters:** The Breaking entry says existing VMs using the default "are resized". As the reviewer recalls Azure's documentation, `Standard_B2s` has a local temp disk, `Standard_B2s_v2` has none, Azure doesn't allow resizing between those two kinds of size, and the Bsv2 series runs Generation 2 images only. If so, an upgrading caller gets an apply-time failure rather than a resize, and a new VM on a Gen 1 `vm_source_image` or `vm_source_image_id` fails with the new default. Even a successful resize restarts the VM, which the entry doesn't say. Missing validation: Azure documentation or a live resize; this offline review had neither, and the spec's live checks cover only regional availability of the new size.
**Suggested fix:** Add a live resize from `Standard_B2s` to the live test repo. Then correct the CHANGELOG entry to what happens (restart, or recreate the VM and keep the old size by setting `vm_size` until then). No module code change is implied unless the test shows otherwise.
**Resolution:**

### F-22 [P3] open - The tflint comment says prevent_destroy stays the caller's choice, but callers can't set it

**File:** .tflint.hcl:12
**Found:** 2026-11-02 by /audit independent (scope: current; lens: quality)
**Why it matters:** A probe with a `lifecycle` block in a `module` call fails with "Reserved block type name in module block", so a caller can't add `prevent_destroy` to a module's resources. Disabling the rule is reasonable, and the first half of the comment is right, but the second half tells readers a protection exists that doesn't. Stateful `key-vault` and `storage-account` resources have no destroy guard available to callers.
**Suggested fix:** Reword the comment to say that a shared module can't make `prevent_destroy` configurable and callers can't add it, so these modules go without it. Comment only; no current requirement is lost.
**Resolution:**

### F-23 [P3] open - kv_public_network_access_enabled still describes rules as an extra restriction

**File:** modules/key-vault/variables.tf:90
**Found:** 2026-11-02 by /audit independent (scope: current; lens: quality)
**Why it matters:** The description says "Restrict further with kv_network_acls", written when no rules applied by default. With this fix, the default of `true` and the new default rules deny all networks except trusted Azure services, so the public flag on its own no longer grants access. `key-vault` has no README, so this description is the main place a caller reads it. The standards require descriptions to state how defaults behave.
**Suggested fix:** Reword to say public access stays subject to `kv_network_acls`, which denies by default, matching `sa_public_network_access_enabled`. Description only.
**Resolution:**

### F-29 [P3] open - An unreferenced root image.png shows an outdated flow

**File:** docs/image.png
**Found:** 2026-11-04 by /audit independent (scope: current; lens: quality)
**Why it matters:** The 551 KB diagram at the repo root, titled "planned flow", isn't linked from any file and isn't in the spec's Files list. It shows a single agent session finishing with `write_pr_body`, but the code runs one session per affected module that finishes with `write_pr_section`. Readers of the public repo would get the old design.
**Suggested fix:** Update it to the per-module flow, move it under a docs path with a descriptive name, and link it from where the agent is documented. Or drop it from the feature. No current requirement is lost.
**Resolution:** Re-examined 2026-11-04 by /audit independent (fresh subagent): still present at `8a3a41a`, still unreferenced (`git grep image.png` finds nothing), and still shows one session ending in `write_pr_body`. Stays open.
Re-examined 2026-11-04 by /audit independent (fresh subagent, target e0ed31d): unchanged since `69668de`, still unreferenced, still titled "planned flow" with one session ending in `write_pr_body`. Stays open.
Re-examined 2026-11-04 by /audit independent (fresh subagent, target 335a884): `335a884` only moved it to `docs/image.png` (bytes identical to `69668de`). `git grep image.png` still finds no reference, and it still shows "planned flow", a single session and `write_pr_body`. The move covers half of the suggested fix; the content and the link are still missing. Stays open.

### F-33 [P3] open - A tool call whose arguments aren't valid JSON still fails the whole run

**File:** ai-agent/graph.py:29
**Found:** 2026-11-04 by /audit independent (scope: current; lens: quality, tests)
**Why it matters:** `langchain-openai` puts a tool call with unparseable JSON arguments in `reply.invalid_tool_calls`, not `reply.tool_calls`. When that is the reply's only call, `agent` raises "The model stopped without calling write_pr_section", which is misleading, and the month's run ends with no PR. A scratch run with a scripted reply holding only an invalid `read_file` call exited 1 after one model call. When a reply mixes valid and invalid calls, the `tools` node answers only the valid ones, while `langchain-openai` (`_convert_message_to_dict`, `base.py:490-495`) sends the invalid ones back as `tool_calls`, so the next request has call IDs without a tool message, which OpenAI's API rejects (not reproduced: no real endpoint in this review). This predates the F-30 repair (`ToolNode` didn't answer invalid calls either), so it's the same failure class F-30 fixed, through a different path. Cost: one wasted monthly run, retried next month.
**Suggested fix:** In `agent`, treat `reply.invalid_tool_calls` as calls, and in `tools` answer each with `Refused: the arguments aren't valid JSON: <error>` so the model can retry. Add a test with an invalid call followed by `write_pr_section`.
**Resolution:** Re-examined 2026-11-04 by /audit independent (fresh subagent, target 335a884): `graph.py:29` still checks only `reply.tool_calls`, and the `tools` node still answers only those. Unchanged. Stays open.

### F-36 [P3] unverified - Re-running an old failed publish job can still force-push onto a newer PR

**File:** scripts/publish-bot-pr.sh:54
**Found:** 2026-11-04 by /audit independent (scope: current; lens: quality, security)
**Why it matters:** The concurrency group in `check-registry.yml:13-15` stops overlapping runs, but "Re-run failed jobs" on an earlier run whose `gh pr create` failed re-runs only `publish` and reuses that run's old `check` outputs, including `pr_exists=false`. If a newer run (for example a dispatch after turning the PR setting on) has already opened the PR, the re-run force-pushes the older proposal onto it, then fails at `gh pr create`. The PR then shows the old diff under the newer description. The patch gate and the PR's own CI still apply, so this is a mismatch, not a privilege gain, and it needs a person to re-run a stale job after a newer run succeeded (GitHub allows re-runs for 30 days). Not reproduced against GitHub; it rests on GitHub reusing successful jobs' outputs on a partial re-run.
**Suggested fix:** If it matters, in `publish-bot-pr.sh` recount PRs with `gh pr list --head "$branch" --state all --json number --jq length` just before the push and stop when it isn't `0`. No current requirement is lost. Otherwise accept it: use "Re-run all jobs", not "Re-run failed jobs", on an old run.
**Resolution:**

### F-43 [P3] open - A service_cidr wider than /12 passes plan though Azure rejects it

**File:** modules/aks/variables.tf:199
**Found:** 2026-11-04 by /audit independent (scope: current; lens: quality)
**Why it matters:** The spec's goal is to fail at plan time on inputs Azure would reject. The azurerm 5.12.0 docs say the service address CIDR must be smaller than /12, but the validation only checks syntax: `aks_network = { service_cidr = "10.0.0.0/8", dns_service_ip = "10.0.0.10" }` plans cleanly (scratch probe), so it fails only at apply.
**Suggested fix:** Add `tonumber(split("/", service_cidr)[1]) >= 12` (guarded with `coalesce`) to the CIDR validation, name the limit in the error message, and add a rejecting test. No current requirement is lost.
**Resolution:**

### F-44 [P3] unverified - outbound_type managedNATGateway is offered though the cluster always uses a caller's subnet

**File:** modules/aks/variables.tf:212
**Found:** 2026-11-04 by /audit independent (scope: current; lens: quality)
**Why it matters:** The module always places nodes in a caller-supplied subnet (`subnet_id` is required). AKS documents the managed NAT gateway outbound type for AKS-managed vnets and `userAssignedNATGateway` for your own vnet, so `managedNATGateway` likely fails only at apply. It plans cleanly (scratch probe). Missing validation: Azure docs or a live plan confirming the rejection for a custom subnet.
**Suggested fix:** If confirmed, drop `managedNATGateway` from the allowed list and the description. No current requirement is lost.
**Resolution:**

### F-45 [P3] unverified - A full patch aks_kubernetes_version with the default patch channel may drift after an auto-upgrade

**File:** modules/aks/variables.tf:48
**Found:** 2026-11-04 by /audit independent (scope: current; lens: quality)
**Why it matters:** The description invites `"1.33.2"`, and the default `aks_automatic_upgrade_channel` is `patch`. After AKS upgrades the cluster to a newer patch, a later plan may try to set the version back to `1.33.2`, which AKS refuses as a downgrade. A minor alias such as `"1.33"` avoids this. Both plan offline (probe); the drift needs a live cluster to confirm.
**Suggested fix:** If confirmed, say in the description to use `major.minor` while an upgrade channel is on, or add a precondition rejecting a patch version unless the channel is `none`. No current requirement is lost beyond pinning an exact patch with auto-upgrade on.
**Resolution:**

### F-47 [P3] open - The "none" upgrade-channel mapping and a malformed identity ID have no test

**File:** modules/aks/tests/aks.tftest.hcl:433
**Found:** 2026-11-04 by /audit independent (scope: current; lens: tests)
**Why it matters:** main.tf:76 maps `aks_automatic_upgrade_channel = "none"` to `null`, which is derived logic the testing standard says needs a test, and no run sets `"none"`. The `aks_identity_ids` validation also checks the ID format, but only the two-identity case is tested, so a broken format regex would go unnoticed.
**Suggested fix:** Add a plan run with `"none"` asserting `automatic_upgrade_channel == null`, and a rejecting run with one malformed identity ID.
**Resolution:**

### F-51 [P3] open - Two of the four rotation-name collision checks have no test

**File:** modules/aks/main.tf:188
**Found:** 2026-11-04 by /audit independent (scope: current; lens: tests)
**Why it matters:** The user-pool rotation precondition has four clauses. Only clause 2 (a pool named like the system pool's rotation name, `rejects_pool_named_like_a_rotation_name`) and clause 3 (two pools sharing a rotation name, `rejects_pools_sharing_a_rotation_name`) are tested. Clause 1 (a pool's rotation name equals another pool's name, e.g. pools `apps` and `appstmp`) and clause 4 (a user pool's rotation name equals the system pool's, e.g. system `sysnodepool` and user `sysnodepoo`) are reachable and each is the only clause that catches its case, yet deleting both from a scratch copy of the target left all 68 shipped tests passing. The testing standard requires a test for precondition logic, so a regression here would let a cluster plan that Azure later fails on during a pool rotation.
**Suggested fix:** Add two `expect_failures` plan runs to `modules/aks/tests/aks.tftest.hcl`: pools `apps` and `appstmp` expecting `azurerm_kubernetes_cluster_node_pool.user["apps"]`, and system pool `sysnodepool` with user pool `sysnodepoo` expecting `azurerm_kubernetes_cluster_node_pool.user["sysnodepoo"]`. Both were confirmed to fail as expected against the current code.
**Resolution:**

### F-52 [P3] open - integrations_on repeats the workspace input and the Container Insights assert

**File:** modules/aks/tests/aks.tftest.hcl:241
**Found:** 2026-11-04 by /audit independent (scope: current; lens: tests)
**Why it matters:** The workspace ID is now in the file-level `variables` block, so `integrations_on` sets the same value again (line 241), and its `oms_agent` assert (lines 253-258) duplicates the one added to `defaults_are_secure`. The run no longer turns Container Insights on, so the copy suggests a toggle that no longer exists and is a second place to edit if the assertion changes.
**Suggested fix:** Delete the `aks_log_analytics_workspace_id` line and the `oms_agent` assert from `integrations_on`. No current requirement is lost: `defaults_are_secure` keeps the same check.
**Resolution:**

### F-53 [P3] open - The project plan and overview still call Container Insights optional

**File:** blueprint/project-plan.md:35
**Found:** 2026-11-04 by /audit independent (scope: current; lens: quality)
**Why it matters:** After this fix Container Insights is always on and the workspace is required, but `blueprint/project-plan.md:35`, `blueprint/build-plan.md:30` and the derived `blueprint/context/project-overview.md:39` all list it as optional. The spec notes only the build-plan line. Later specs and reviews read these files as the source of truth.
**Suggested fix:** The user updates the two plan lines (they own them), then `/overview` regenerates the overview. Mention all three at `/complete`. Not a code change.
**Resolution:**
