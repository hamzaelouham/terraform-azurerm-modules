# Fix: Retry a bot PR after a failed creation

**Type:** Fix
**Status:** verified
**Branch:** fix/retry-a-bot-pr-after-a-failed-creation
**Fixes:** F-34, F-35

## The problem

`scripts/publish-bot-pr.sh` pushes `bot/azurerm-<version>` and then runs
`gh pr create`. If creating the PR fails, the branch stays on GitHub with no PR.
That can happen when "Allow GitHub Actions to create and approve pull requests" is
off, or when the body is too long.

The `check` job only looks for an existing PR, so next month the agent runs again
and spends its tokens. Publish then fails at `git push`, because the branch already
exists and has a different commit. This repeats every month until someone deletes
the branch by hand.

There's a second cause of failed PR creation. The body is cut to 60,000 bytes
before every `@` becomes `&#64;`, so a body full of `@` can grow to about five times
that and go over GitHub's 65,536-character limit.

## The fix

In `scripts/publish-bot-pr.sh` only:

- **Force-push the bot branch.** Publish only runs when no PR, open or closed,
  exists for `bot/azurerm-<version>`. A branch with that name and no PR can only be
  left over from a failed run, and only the bot writes to it, so replacing it is
  safe. The next monthly run then rebuilds the proposal and retries the PR. This
  matches the existing rule for a failed run: no PR, and it tries again next month.
- **Escape `@` before cutting the body.** Escape first, then cut, so the result
  stays under the limit however many `@` it contains. The Verify summaries after
  the cut are escaped too, as now.

This must not change:
- the patch gate and its order: gate, then branch, apply, commit, push
- the `pr_exists` check, which still stops the agent once any PR exists
- the `@` escaping of all agent and module text
- the draft PR's title, base and head

The only workflow change is a `concurrency` group (step 2). No agent or tracker
changes, and no new settings.

## Build steps

- [x] 1. **Force-push and escape before the cut.** In `publish-bot-pr.sh`, push the
  bot branch with `--force`, and apply the `@` escape to `pr-body.md` before the
  60,000-byte cut.
  **Done when:**
  - In a scratch run against a local bare remote and a fake `gh`, a first run whose
    `gh pr create` fails leaves the branch. A second run with a working `gh`
    replaces the branch and creates the PR.
  - A `pr-body.md` of 70,000 `@` characters gives a body under 65,536 characters
    with no raw `@`.
  - `sh -n` passes, and `sh scripts/verify.sh` prints `All checks passed.`

- [x] 2. **One check-registry run at a time (F-35).** The review found that `--force`
  could overwrite a PR that another, overlapping run opened after this run's `check`
  job looked. Add a workflow-level `concurrency` group to `check-registry.yml` with
  `cancel-in-progress: false`, so a second run waits for the first to finish and its
  `check` job then sees the first run's PR. This is GitHub-only, like the agent;
  the other three platforms never publish.
  **Done when:** the workflow has the group, the YAML parses, and Verify passes.

## Verify

- Repeat both scratch runs above and read the fake `gh` log and the remote branch.
- `sh scripts/verify.sh`.
- The real GitHub path stays covered by the next monthly run. Optionally,
  run it by hand with a lowered reviewed version and the PR setting off, then on.


<!-- blueprint:completion {"schemaVersion":2,"specBytes":3373,"specSha256":"1395e3c87ce3ef46d6d899b003ba145a868f7fe28498f3c6519dca20a470cb45","branch":"refs/heads/fix/retry-a-bot-pr-after-a-failed-creation","head":"ef78737f2da423f269878e8c0cd621684cb3e353","baseRef":"refs/heads/main","baseCommit":"7c1645f62a29d607b426d074afaeee2dde1a4eba","sourceTree":"ba5a3116bec072c855eead487c3dc7925b589724","landing":"local-merge","absentOptional":[]} -->

## Findings

### retry-a-bot-pr-after-a-failed-creation/F-34 [P3] closed - A PR creation failure after the push leaves a branch that fails every later run

**File:** scripts/publish-bot-pr.sh:54
**Found:** 2026-11-04 by /audit independent (scope: current; lens: quality)
**Why it matters:** `publish-bot-pr.sh` pushes `bot/azurerm-<version>` before `gh pr create`. If PR creation fails (for example, "Allow GitHub Actions to create and approve pull requests" turned off, or a body over GitHub's limit, since `@` becomes `&#64;` after the 60,000-byte cut), the branch stays with no PR. The `check` job's `pr_exists` looks only at PRs, so next month the propose job runs and spends the model budget again, then publish fails at `git push` (non-fast-forward). This repeats every month until a person deletes the branch. Reproduced in a scratch copy with a local bare remote and a `gh` that fails: run 1 pushed the branch and failed at PR creation, and run 2 was rejected at push. Nothing unsafe reaches the repo; the cost is repeated failed runs and token spend.
**Suggested fix:** In the `existing` step, also treat an existing `bot/azurerm-<version>` branch (`git ls-remote --heads origin`) as existing, so the agent doesn't rerun and the run says why. Or push with `--force` in `publish-bot-pr.sh`, since the bot owns that branch and it has no PR. Applying the `@` escape before the cut also keeps the body under the limit. No current requirement is lost.
**Resolution:** Fixed 2026-11-04 by /implement (fix: Retry a bot PR after a failed creation): `publish-bot-pr.sh` force-pushes the bot branch, which is safe because publish only runs when no PR exists for it, and escapes `@` before the 60,000-byte cut. Scratch runs against a bare remote and a fake `gh`: a failed PR creation left the branch, the next run replaced it (forced update) and created the PR; a body of 70,000 `@` came out at 60,255 characters with no raw `@` (the old order gave 300,000).
Re-examined 2026-11-04 by /audit independent (fresh subagent, target 4c5c3f2): the original defect is gone. Scratch run against a bare remote: a failing fake `gh` left `bot/azurerm-9.9.9`, and the next run force-updated it (`a199ae9...03e9f13 (forced update)`) and called `gh pr create`. A 70,000-`@` body came out at 60,274 characters with no raw `@`. But the repair adds a new defect, F-35: `--force` can now replace the head of a PR created after the `check` job looked. Stays `fixed` until F-35 is repaired and re-reviewed. File line corrected from the stale `:116` to `:54`.
Closed 2026-11-04 by /audit independent (fresh subagent, target ef78737): re-reviewed `publish-bot-pr.sh:54-66`. Scratch run against a bare remote: a failing fake `gh` left `bot/azurerm-9.9.9` (exit 1), and the next run with a different patch force-updated it (`24ae218...c41f9ac (forced update)`) and called `gh pr create` (exit 0). A 70,000-`@` body came out at 60,267 characters with no raw `@`, including a `Failed checks:` summary. The new-defect blocker, F-35, is closed in this pass. A narrower residual (a manual re-run of an old failed publish job reuses its stale `pr_exists`) is recorded separately as unverified F-36.

### retry-a-bot-pr-after-a-failed-creation/F-35 [P3] closed - The force-push can replace the head of a PR opened after the check

**File:** scripts/publish-bot-pr.sh:54
**Found:** 2026-11-04 by /audit independent (scope: current; lens: quality, security)
**Why it matters:** The `--force` is safe only if no PR exists for `bot/azurerm-<version>`. But that is checked once, in the `check` job of `check-registry.yml:34-41`, about 30 minutes before `publish` runs, and the workflow has no `concurrency` group. If two runs overlap (the monthly schedule and a `workflow_dispatch`, or two dispatches), the first opens the draft PR, then the second force-pushes its own commit onto that PR's branch and fails at `gh pr create` because the PR exists. The open PR then shows run 2's diff under run 1's description and Verify summaries. Before this change the second push was rejected, so nothing was overwritten. The patch gate still limits the diff to `modules/`, and the PR's CI runs on the new head, so this is a mismatch, not a privilege gain. Not reproduced against GitHub; the force-update itself was reproduced in a scratch bare remote.
**Suggested fix:** In `publish-bot-pr.sh`, just before the push, count PRs again with `gh pr list --head "$branch" --state all --json number --jq length` and stop without pushing when it isn't `0`. That keeps the fix inside the script, as the spec requires. A `concurrency: check-registry` group in the workflow would also work but changes the workflow. No current requirement is lost.
**Resolution:** Fixed 2026-11-04 by /implement (fix: Retry a bot PR after a failed creation, step 2): `check-registry.yml` has a workflow-level `concurrency` group (`check-registry`, `cancel-in-progress: false`), so runs never overlap and a queued run's `check` job sees the PR the earlier run opened. The YAML parses; actionlint was unavailable.
Closed 2026-11-04 by /audit independent (fresh subagent, target ef78737): re-reviewed `check-registry.yml:11-15` and the `check`/`publish` jobs. The group is workflow-level with a fixed key, so every run of this workflow (schedule or dispatch, any ref) is serialized, and a later run's `check` job starts only after the earlier run's `publish` has opened its PR, so `pr_exists` is `true` and `propose`/`publish` are skipped. With three or more runs queued GitHub cancels the older pending one, which drops a run but never overlaps two. PyYAML parses `concurrency: {group: check-registry, cancel-in-progress: false}`. The repair added no new defect. GitHub-only, as the other three platforms only run `check-registry.py` and never publish. actionlint unavailable.

## Independent review

# Independent Review

**Status:** passed
**Target commit:** ef78737f2da423f269878e8c0cd621684cb3e353
**Base commit:** 7c1645f62a29d607b426d074afaeee2dde1a4eba
**Base ref:** main
**Spec hash:** 1395e3c87ce3ef46d6d899b003ba145a868f7fe28498f3c6519dca20a470cb45
**Prepared by:** claude
**Builder model:** claude-opus-5-5
**Requested reviewer:** claude
**Requested model:** claude-opus-5-5
**Requested execution:** automatic
**Requested at:** 2026-11-04T15:48:38Z
**Workflow:** regular
**Check required:** no
**Reviewer adapter:** claude
**Reviewer model:** claude-opus-5-5
**Reviewer context:** fresh subagent
**Actual execution:** automatic
**Reviewed at:** 2026-11-04T15:51:17Z
**Scope:** current
**Lenses:** quality, security, performance, tests
**Verdict:** passed
**Check result:** not-required

## Handoff

Review the active spec and the complete `7c1645f62a29d607b426d074afaeee2dde1a4eba..ef78737f2da423f269878e8c0cd621684cb3e353` delta in a fresh
session or isolated subagent without the builder conversation. Run all Audit lenses from scratch.
Run Check when required above. Do not edit product code, accept findings, or
reuse the existing findings as the review scope.

## Commands

- `git merge-base main HEAD`: pass (equals Base commit; HEAD equals Target commit; spec hash matches; only review.md and findings.md differ)
- `sh scripts/publish-bot-pr.sh 9.9.9 <in1>` with a failing fake `gh` against a scratch bare remote: pass (branch pushed, exit 1 at PR creation)
- `sh scripts/publish-bot-pr.sh 9.9.9 <in2>` with a working fake `gh`: pass (`24ae218...c41f9ac (forced update)`, `gh pr create` called, exit 0)
- `sh scripts/publish-bot-pr.sh 9.9.8 <in3>` with a 70,000-`@` `pr-body.md`: pass (60,267 characters, no raw `@`)
- `sh -n scripts/publish-bot-pr.sh`: pass
- PyYAML parse of `.github/workflows/check-registry.yml`: pass
- `sh scripts/verify.sh` (pinned tflint 0.65.0, terraform-docs 0.24.0, trivy 0.76.1, Terraform 1.17.1 local): pass (`All checks passed.`)
- `actionlint`: unavailable
- `shellcheck`: unavailable

## Evidence

- Delta is three files: `scripts/publish-bot-pr.sh` (force-push at :54, escape-then-cut at :60), `.github/workflows/check-registry.yml` (workflow-level concurrency at :11-15) and the spec. No `modules/` changes.
- Patch gate order unchanged (gate, branch, apply, commit, push); `pr_exists` check, outer `@` escape, and PR title/base/head unchanged, as the spec requires.
- Cutting mid-entity can leave a trailing `&#6`; harmless, and no raw `@` survives. Verify summaries after the cut are short and bounded.
- Parity: GitLab CI, Azure Pipelines and Jenkins run only `check-registry.py` and never publish, so the concurrency group is correctly GitHub-only.
- Scratch work only under the session scratchpad `review6/`; nothing written in the project tree besides the two evidence files.

## Findings

- F-34 [P3] closed
- F-35 [P3] closed
- F-36 [P3] unverified (new): a manual re-run of an old failed publish job reuses stale `pr_exists` and can force-push onto a newer PR

## Remaining risk

- `actionlint` unavailable: workflow checked by YAML parse and reading only.
- `shellcheck` unavailable: script checked by `sh -n` and scratch runs only.
- Real GitHub behavior (concurrency queueing, PR creation, re-run output reuse behind F-36) not exercised; the next monthly run covers the main path.
- Dashboard activity (`run.json`) not written: the reviewer was limited to findings.md and review.md.

## Try it now

1. Make a scratch bare clone of this repo and a work clone of it, then put a fake
   `gh` first on `PATH` that exits 1 for `pr create`. Run
   `sh scripts/publish-bot-pr.sh 9.9.9 <dir>` with a `pr-body.md`, an empty
   `agent-patch.diff` and two verify results in `<dir>`. Expect exit 1 and a
   `bot/azurerm-9.9.9` branch on the bare remote.
2. Switch the work clone back to `main`, delete the local bot branch, make the fake
   `gh` succeed, and run it again. Expect `(forced update)` and a `gh pr create` call.
3. On GitHub, start `check-registry` twice in a row by hand. Expect the second run
   to wait in the queue until the first finishes.
