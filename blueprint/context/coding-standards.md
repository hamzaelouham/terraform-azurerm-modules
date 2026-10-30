# Coding Standards

> Seeded by `/adopt` from the conventions the existing modules follow.

## Repository layout

- One module per folder: `modules/<name>/` with `main.tf`, `variables.tf`,
  `outputs.tf` and `versions.tf`. Add `README.md` and `tests/` where useful.
- Example root stacks live in `examples/<name>/` and are kept local only
  (ignored by git). Never reference them from tracked files.
- No `.terraform.lock.hcl` and no real `*.tfvars` in git; consumers pin providers.
- Record every user-visible change in `CHANGELOG.md` (Keep a Changelog, under
  `## [Unreleased]` with `Breaking`, `Added`, `Changed` sections).

## Versions and providers

- `required_version = ">= 1.17"` in every module. Do not use newer language
  features without raising it.
- Pin providers to a major range: azurerm `">= 5.0, < 6.0"`, azapi
  `">= 2.0, < 3.0"`, azuread 3.x. Use azapi only for what azurerm can't do.
- Modules never configure providers; callers do.

## Module boundaries

- Modules deploy into an existing resource group. Take `resource_group_name` and
  `location`; callers pass `module.rg.name` and `module.rg.location`.
- Pass `location` straight to the provider; don't normalize or re-validate it.
- Shared inputs keep plain names (`resource_group_name`, `location`,
  `subnet_id`, `tenant_id`). Module-specific inputs take the module prefix
  (`vm_`, `kv_`, `sp_`, `vnet_`, `nsg_`, `rg_`).

## Variables

- Every variable has a `description` that states units, defaults and how null
  behaves, with an example value where it helps.
- Validate at plan time whatever Azure would reject at apply: name formats and
  lengths, enums, reserved values, IP/CIDR syntax. Every validation has a clear
  `error_message` that names the variable.
- Validations don't short-circuit `||`, so guard nullable values with
  `coalesce(var.x, "-")` inside the check.
- Checks spanning several variables go in `lifecycle { precondition }` on the
  first resource that would otherwise fail, so nothing is half-created.
- Collections and booleans with defaults set `nullable = false`. Secrets set
  `sensitive = true`.
- Repeated things are maps keyed by name (`subnets`, `nsg_rules`,
  `vm_data_disks`, `kv_access_policies`), with `optional()` attributes and
  defaults, consumed with `for_each`.
- Secure defaults: no public IP, SSH keys only on Linux, purge protection and
  RBAC on for key vaults.

## Resources and naming

- Single-instance resources use short local names (`rg`, `vnet`, `nic`, `kv`).
- Child resources derive names from the parent: `<vm_name>-nic`, `<vm_name>-osdisk`.
- Optional resources use `count = var.x_enabled ? 1 : 0` and are read with
  `one(resource.x[*].attr)`.
- Every taggable resource takes the module's tags variable.

## Outputs

- Every output has a `description`. Return `null` (not `""`) when the feature is
  off. Mark secrets `sensitive = true`.

## Formatting

- `terraform fmt` style everywhere; CI and reviews expect `fmt -check` to pass.

## Testing

Testing is set up: the runner is `terraform test` (built into Terraform), and the
`test` command in `AGENTS.md` turns on the gate below.

When `AGENTS.md` declares a `Verify` command, treat it as the umbrella automated
gate. It combines only the checks this project actually has, in this order when
available: typecheck, tests, then build. The command does not enable an absent
test runner or replace focused evidence. It gives local work and optional CI one
exact command to run. `/ci` owns Verify and CI setup. `/tests` adds the real test
command to Verify when it already exists, but never creates CI only because
testing was configured.

**The opt-in switch is one signal: a `test` command in the Commands section of
`AGENTS.md`.** Declare one and **tests become a gate for logic-bearing steps**,
not an optional extra; leave it out and the loop verifies logic with the evidence
it already uses (`fmt`, `validate`, a plan). Adding the runner is itself a
deliberate step, never a silent mid-step install. This is the single definition
of the switch; the skills and `ai-interaction.md` only point back here.

- **What to test (the scope rule):** pure logic where a wrong answer is possible -
  variable validations, preconditions, derived names, and locals that pick
  defaults or toggle resources. These have assertable inputs and plans, and
  real edge cases (null, empty, malformed, reserved values).
- **What not to test:** whether Azure accepts the result. Mocked tests can't
  prove that; verify it with a real `plan`/`apply` against a subscription when
  one is available, and say so when it wasn't done.
- **The gate (when a runner is configured):** a build step that adds in-scope logic
  must ship a passing test in the same reviewable diff. The project's test command
  must be green before the step is approved, before any checkpoint commit, and
  before `/complete` merges. Steps with no logic (descriptions, docs, version pins)
  are exempt and ride on `fmt` plus `validate`.
- **When it's named:** the `/feature` spec's Testing section predicts the coverage,
  `/implement` writes the test with the step, and if a step surfaces logic the spec
  didn't foresee, add a focused test then.
- An empty suite should fail, not pass, so "no tests ran" never looks like "passed".
- Test files live in each module's `tests/` folder as `*.tftest.hcl`.
- Run them via the project's test command (see Commands in `AGENTS.md`), not a
  hardcoded tool name.

Stack binding: `terraform test` with `mock_provider` blocks, so tests run offline
with no Azure credentials. Use `command = plan` by default. Use `command = apply`
only when an assertion needs computed values, and give the mocks parseable Azure
resource IDs through `mock_resource` defaults. Check rejected inputs with
`expect_failures` on the variable or resource that should fail.

Current state: only `modules/virtual-machine` has tests. The gate applies to new
logic (validations, preconditions, locals that derive values) in any module.

## Code Quality

- No commented-out code
- No unused variables, locals or outputs
- Keep duplicated blocks small; derive shared values once in `locals`

## Comments

Write code that explains itself; comment only what the code cannot say.
Over-commenting is a common AI tell, so resist it.

- Comment the **why**, not the **what**. Delete any comment that restates the code.
- No banner/header blocks, section dividers, or step-by-step narration of obvious
  code. A file does not need a comment announcing each region.
- A comment earns its place only when it captures something the code can't: a
  non-obvious decision, a gotcha or workaround, why a value is what it is, or a
  link to a spec or issue.
- Prefer self-documenting names and small functions over explanatory comments.
- Keep doc comments minimal: a one-line purpose on an exported type or function is
  plenty; don't write JSDoc that just repeats the signature.
- When in doubt, leave the comment out.

## Writing

- No em dashes (U+2014) in generated content: docs, comments, commit messages,
  READMEs, specs. They read as AI-generated.
- Use a hyphen for `term - description` separators; rephrase prose with commas,
  parentheses, or a colon. Avoid en dashes and the ellipsis character too.
