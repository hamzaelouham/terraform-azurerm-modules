# Fix: Raise the azurerm minimum to 5.12 in every module

**Type:** Fix
**Status:** verified
**Branch:** fix/raise-the-azurerm-minimum-to-5-12-in-every-module

## The problem

The user asked for every module under `modules/` to match azurerm 5.12.0.
`.azurerm-reviewed-version` says 5.12.0, and `aks` already requires it
(`">= 5.12, < 6.0"`). The other azurerm modules still accept older providers:

| Module | azurerm constraint today |
|---|---|
| `resource-group` | `">= 4.0, < 6.0"` |
| `vnet`, `key-vault`, `storage-account`, `virtual-machine` | `">= 5.0, < 6.0"` |
| `aks` | `">= 5.12, < 6.0"` (already right) |
| `service-principal` | no azurerm (azuread and time only) |

A caller on azurerm 5.0 to 5.11, or on 4.x for `resource-group`, is allowed to use
modules that were only ever checked against 5.12.0.

Checked on 2026-11-04: each of the six azurerm modules resolves azurerm v5.12.0 on
`init`, and `terraform validate` passes with no warnings, so no deprecated or removed
argument is in use. This fix changes constraints and docs only, not resource code.

## The fix

- Set azurerm to `">= 5.12, < 6.0"` in `versions.tf` for `resource-group`, `vnet`,
  `key-vault`, `storage-account` and `virtual-machine`. Add the same one-line comment
  `aks` has: "5.12 is the version this module's arguments were checked against."
- Leave `aks` as it is. Leave azapi (`virtual-machine`), azuread and time
  (`service-principal`) unchanged: the request covers azurerm only.
- `blueprint/context/coding-standards.md`, "Versions and providers": change the
  azurerm pin to `">= 5.12, < 6.0"`. Say the floor is the version in
  `.azurerm-reviewed-version`, and is raised together with it.
- `CHANGELOG.md` `[Unreleased]` `Breaking`: every azurerm module now requires
  azurerm 5.12 or later within 5.x; `resource-group` no longer allows 4.x. No
  `<module>/v*` tag exists yet, but the existing entries record pre-release breaking
  changes the same way.
- Regenerate the terraform-docs tables in the module READMEs that have them, so the
  Requirements rows show the new constraint. Update any hand-written "Requires
  azurerm 5.x" line in a README to "5.12 or later within 5.x".

Also carried in this fix, at the user's choice (2026-11-04): the approved F-53
wording edits to `blueprint/project-plan.md` §3 and `blueprint/build-plan.md` item 7a
(Container Insights always on), and the overview regenerated from them. They were
uncommitted on `main` when this branch started.

Must not break: any resource argument, input, output, test, or the azapi, azuread
and time pins. `fmt`, `validate`, tflint, Trivy and all tests stay green.

## Build steps

- [x] 1. **Raise the azurerm floor and update the docs.**
  - The five `versions.tf` files.
  - The coding standard.
  - The CHANGELOG `Breaking` entry.
  - The README requirement lines, plus regenerated terraform-docs.
  - The unreleased CHANGELOG `Added` entries that said "Requires azurerm 5.x".
    They now say 5.12 or later, to match.

  **Done when:**
  - `grep -h 'version = ' modules/*/versions.tf` shows `">= 5.12, < 6.0"` for every
    azurerm entry, with azapi, azuread and time unchanged.
  - `sh scripts/verify.sh` prints `All checks passed.`, including the terraform-docs
    checks and the aks (68), storage-account (42) and virtual-machine (14) tests.

## Verify

- `grep -n 'hashicorp/azurerm' -A1 modules/*/versions.tf`: every azurerm constraint
  is `">= 5.12, < 6.0"`.
- `sh scripts/verify.sh`: `All checks passed.`
- Optional: in a scratch root that pins `azurerm = "= 5.11.0"` and calls `vnet`,
  `terraform init` fails with a provider version conflict. With `5.12.0` it succeeds.

## Notes for the AI

- Module code under `modules/` is the user's to write by default. Ask at
  `/implement` who writes this change, unless the user says so first.
- F-18 (resource-group drifts from the location and pin standards) is only half
  covered. This fix removes its 4.x pin, but the `location` normalization and
  validation still need the user's decision. Note the pin half in F-18's
  Resolution, and leave F-18 open.
- User-owned plan text that this change makes stale (mention it, don't edit it):
  - `blueprint/project-plan.md` §5 says "azurerm 5.x (resource-group allows 4.x)".
  - The overview's "Provider pin mismatch" open question comes from that line.
- Out of scope:
  - Running `apply` or a live plan.
  - Reviewing each argument against the 5.12.0 docs beyond what `validate` and its
    warnings show.
  - Bumping azapi, azuread or time.


<!-- blueprint:completion {"schemaVersion":2,"specBytes":4516,"specSha256":"5650c3bf96fb02aef58b06b22b1c5ae76712f2f4a39e8203fb64c82f736ccf87","branch":"refs/heads/fix/raise-the-azurerm-minimum-to-5-12-in-every-module","head":"0456a3c4bed9d15becdab682b6eb24be6a297277","baseRef":"refs/heads/main","baseCommit":"0456a3c4bed9d15becdab682b6eb24be6a297277","sourceTree":"53a171acd13c5baf080da6f3aab805db2b1f05c4","landing":"local-merge","absentOptional":[]} -->

## Try it now

1. Run `grep -n 'hashicorp/azurerm' -A2 modules/*/versions.tf`. Expect
   `version = ">= 5.12, < 6.0"` under each of the six azurerm modules.
2. Run `sh scripts/verify.sh`. Expect `All checks passed.`
