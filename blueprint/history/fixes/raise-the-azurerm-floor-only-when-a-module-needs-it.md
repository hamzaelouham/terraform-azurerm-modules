# Fix: Raise the azurerm floor only when a module needs it

**Type:** Fix
**Status:** verified
**Branch:** fix/raise-the-azurerm-floor-only-when-a-module-needs-it

## The problem

`blueprint/context/coding-standards.md` ("Versions and providers") ties two things
together:

> The azurerm floor is the version in `.azurerm-reviewed-version`, the one the
> modules were checked against. Raise it together with that file.

The upgrade agent must not change provider limits outside a major version
(`ai-agent/instructions/system.md`: "Don't change provider version limits unless the
task tells you to"). So the bot PR for a minor release bumps only
`.azurerm-reviewed-version`. Found on 2026-11-09: PR #10 (`chore: review azurerm
5.13.0`, now `47161ee` on `main`) set the file to `5.13.0`, while every azurerm
module still pins `">= 5.12, < 6.0"`. The code now breaks the standard.

Following the standard literally would raise the floor in every module after every
reviewed release, even when no module needs anything new, as with 5.13.0. That forces
every caller to upgrade azurerm. It's also a breaking change, so every module would
need a major version bump for no benefit.

The rule also leaves a gap the other way. When the agent fixes a rename or
deprecation by switching to an argument that only exists in the new release, the
floor must rise. But the prompt forbids changing limits outside a major version.

The `versions.tf` comment in all six azurerm modules says "5.12 is the version this
module's arguments were checked against". That's no longer true: they were checked
against 5.13.0.

## The fix

New rule:

- **`.azurerm-reviewed-version`** records the newest release the modules were checked
  against.
- **A module's azurerm floor** is the oldest release that has everything the module
  uses. Raise it only when a change needs a newer provider, and only in that module.
- **Raising a floor** breaks callers, so it needs a major version bump of that module.

Files:

- **`blueprint/context/coding-standards.md`:**
  - Replace the two-line floor rule with the new rule.
  - Reword the pin example to "a major range, with the floor the module needs", for
    example azurerm `">= 5.12, < 6.0"`.
- **`ai-agent/instructions/system.md`:** change "Don't change provider version limits
  unless the task tells you to" to also allow one case. If a change uses an argument,
  block or resource added after the reviewed version, raise that module's azurerm
  minimum to the new version, keep the upper limit, and call it out under
  **Version bump**.
- **`ai-agent/prompts/upgrade.md`:**
  - Add the same instruction to step 3 with the real versions:
    "raise the azurerm minimum in `versions.tf` to `>= {latest}`".
  - Keep the text free of the words "major version", which `test_prompts_are_filled_in`
    checks for. Placeholders stay as they are.
- **Six `versions.tf` files** (`aks`, `key-vault`, `resource-group`,
  `storage-account`, `virtual-machine`, `vnet`):
  - Change the comment to "5.12 is the oldest azurerm with everything this module
    uses."
  - The constraint itself doesn't change.

Must not break:

- No version constraint changes, so callers see nothing new.
- A comment-only change in `modules/` doesn't need a module tag or a `CHANGELOG.md`
  entry.
- `.azurerm-reviewed-version`, `check-registry.py`, the workflows, the patch check and
  `major.md` don't change.
- F-11 is a different stale line in the same file. It stays open, and its lines aren't
  touched.

## Build steps

- [x] 1. **Update the standard, the agent's instructions and the comments.**
  Done when:
  - the standard states the new rule;
  - both agent files allow raising a floor only when a change needs the new release;
  - the six comments are updated with the constraints unchanged;
  - `pytest ai-agent/tests` passes;
  - `sh scripts/verify.sh` passes.

## Verify

- `git diff` shows no change to any `version =` line under `modules/`.
- `pytest ai-agent/tests` passes, including `test_prompts_are_filled_in`.
- The rendered non-major prompt shows the floor instruction with real versions, for
  example `>= 5.13.0`.
- `sh scripts/verify.sh` passes.


<!-- blueprint:completion {"schemaVersion":2,"specBytes":4158,"specSha256":"a10799512de14ad0c88464db88bd99163897fa23e150941bcd633bbe551ca21f","branch":"refs/heads/fix/raise-the-azurerm-floor-only-when-a-module-needs-it","head":"47161ee9c2bbf452b0b77afa2a694c61523e5526","baseRef":"refs/heads/main","baseCommit":"47161ee9c2bbf452b0b77afa2a694c61523e5526","sourceTree":"36f9754fbed6360c21fb824c12311304dd8a85ad","landing":"local-merge","absentOptional":[]} -->
