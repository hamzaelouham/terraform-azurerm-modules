# Fix: Limit upgrade agent edits to required changes

**Type:** Fix
**Status:** verified
**Branch:** fix/limit-upgrade-agent-edits-to-required-changes

## The problem

The AI upgrade agent (build-plan item 8, GitHub only) runs one session per module
listed in `azurerm-affected.json`. `write_affected` in `scripts/check-registry.py`
adds a module when any release-note line names one of its resources, when it no
longer validates, or on a major version.

So most sessions start because a release note *mentions* a resource. The task
prompt then tells the agent to "work out what, if anything, it needs because of that
version, and make those changes". "Needs" is never defined:

- `ai-agent/prompts/upgrade.md` says only that an optional addition "that nothing here
  needs" should be left out.
- `ai-agent/instructions/system.md` says "Change only what this azurerm version
  requires" without saying what counts as required.

Because of this, a new optional argument, a provider bug fix or a changed default
can lead the agent to edit module code. That adds review noise to the draft PR, and
may change behavior that callers rely on.

## The fix

Define "required" in the two prompt files the agent reads. The module code may
change only when one of these is true:

1. The module no longer validates, or Verify has a new failure caused by azurerm
   that is not already in `verify-baseline.txt`.
2. A release note says an argument, block, attribute or resource the module uses
   is **removed, renamed or deprecated**. A deprecation counts only when the
   note names the replacement, or the module fails or warns because of it.
3. It is a new major version, and the steps in `prompts/major.md` apply.

Anything else gets no edit. That includes new optional arguments or resources,
provider bug fixes, changed provider defaults, and documentation or style changes.
The agent records these in its PR section instead:

- under **Changes**, as "None needed" with the reason;
- under **Worth testing live**, when a changed default could affect deployed
  resources.

When the agent is unsure, it makes no change and explains why. A README changes
only when an input or output changes, which keeps `BEGIN_TF_DOCS` accurate.

Files:

- `ai-agent/prompts/upgrade.md`: replace "Work out what, if anything, it needs …
  and make those changes" and step 3 with the three allowed reasons and the
  default of no change.
- `ai-agent/instructions/system.md`: point "Change only what this azurerm version
  requires" to those reasons. Add "No change is the default."

Must not break:

- The `{reviewed}`, `{latest}`, `{module}`, `{resources}`, `{validates}` and
  `{changes}` placeholders, and the PR section headings.
- `test_prompts_are_filled_in` checks that a non-major task prompt does not contain
  the words "major version". Phrase reason 3 so the base prompt avoids that text,
  for example by referring to `major.md` only through the appended major prompt.
- No change to `write_affected`, the tools, the patch gate, the workflows or the
  module code. Keyword filtering of release notes in code is out of scope.
- Not a module change, so no `CHANGELOG.md` entry. Item 8 has none either.

## Build steps

- [x] 1. **Tighten both prompts.**
  Edit `upgrade.md` and `system.md` as described above.
  Done when both files state the three allowed reasons and the no-change default,
  the placeholders are unchanged, and the agent tests pass.

## Verify

- `pip install --require-hashes -r ai-agent/requirements-dev.txt && pytest ai-agent/tests`
  passes, including `test_prompts_are_filled_in`.
- Read the rendered prompts for a non-major and a major case with
  `main.build_messages`. The non-major prompt lists reasons 1 and 2 and the default.
  The major prompt also carries the `major.md` steps.
- Real-model behavior can only be seen in the next bot PR (`bot/azurerm-<version>`).
  A module with only optional release-note changes should show "None needed" and no
  diff.


<!-- blueprint:completion {"schemaVersion":2,"specBytes":3972,"specSha256":"d91f003e2d1b371e94aee9055cd1715d07ff085f42160a782e37840e49c7b29d","branch":"refs/heads/fix/limit-upgrade-agent-edits-to-required-changes","head":"1491ed0298bf7204d342482a5ca1f918cbc69ae2","baseRef":"refs/heads/main","baseCommit":"1491ed0298bf7204d342482a5ca1f918cbc69ae2","sourceTree":"d7e2aed549a5da1187f50dc2690930d3c6d25182","landing":"local-merge","absentOptional":[]} -->
