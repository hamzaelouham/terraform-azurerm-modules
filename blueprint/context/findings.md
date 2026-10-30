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
**Resolution:** Still unverified after the independent review of 74f5080. Premium `StorageV2` with a share still plans under the mock. A search of the azurerm 5.12.0 binary for account-kind rejection strings found only `blob_properties` and `share_properties`, which neither confirms nor clears it. Azure documentation or a live plan is still needed.

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
**Resolution:**

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
**Resolution:**
