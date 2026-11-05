# Fix: Let a manual run retry a closed bot PR

**Type:** Fix
**Status:** verified
**Branch:** fix/let-a-manual-run-retry-a-closed-bot-pr

## The problem

In `.github/workflows/check-registry.yml`, the `check` job's `existing` step sets
`pr_exists` from:

```sh
gh pr list --head "bot/azurerm-$VERSION" --state all --json number --jq length
```

Any PR on that branch counts: open, merged or **closed**. When it finds one,
`propose` and `publish` are skipped. This is on purpose (feature 8: "A PR for that
version exists, open or closed → Agent doesn't run"), so that a bot PR a person
rejected isn't proposed again every month.

GitHub can't delete a PR. Once a bot PR for a version is closed, the agent can never
run for that version again, not even from a deliberate manual run. Found on
2026-11-05: closed PR #3 (`bot/azurerm-5.12.0`, from the feature-8 test) blocked a
manual test of the tightened upgrade prompts. The run opened the issue, but
`propose` was skipped. azurerm 5.12.0 is the latest release, so testing is blocked
until 5.13.0 comes out.

## The fix

- Add one `workflow_dispatch` input to `check-registry.yml`:
  `retry_closed` (boolean, default `false`). Description: "Run the agent even if a
  bot PR for this version was closed without merging".
- In the `existing` step, pass it as `RETRY_CLOSED: ${{ inputs.retry_closed }}`.
  When it is `true`, count only PRs whose state isn't `CLOSED`:
  `--json state --jq '[.[] | select(.state != "CLOSED")] | length'`.
  Otherwise, keep today's count of every PR.
- Scheduled runs have no inputs, so `inputs.retry_closed` is empty there and they
  behave exactly as today.
- An open or merged bot PR still stops the agent, with or without the input.
- `docs/scripts.md` sequence diagram: change "no PR yet" to say that a manual run
  with `retry_closed` ignores closed PRs.

Must not break:

- No other job, permission, `if:` condition, or script changes. `publish-bot-pr.sh`
  doesn't recount PRs: F-36 stays open and is out of scope. Its `git push --force`
  already handles a leftover branch, and GitHub allows a new PR from a head
  branch whose earlier PR was closed.
- The concurrency group and the `pr_exists=true|false` output format stay the same.
- The other three platforms never run the agent, so they don't change.
- Not a module change, so no `CHANGELOG.md` entry.

## Build steps

- [x] 1. **Add the input and the closed-PR rule.**
  Edit `check-registry.yml` and `docs/scripts.md`.
  Done when:
  - the workflow parses as YAML;
  - the jq filter, run locally on sample `gh` JSON, gives `0` for `[CLOSED]`, `1` for
    `[OPEN]`, `1` for `[MERGED]` and `0` for `[]`;
  - with `RETRY_CLOSED` empty, the step still counts every PR;
  - `sh scripts/verify.sh` passes.

## Verify

- Local checks: the YAML parse, the jq filter cases and Verify, as in step 1.
- On GitHub, after landing: Actions → check-registry → Run workflow on a test
  branch with `.azurerm-reviewed-version` temporarily set older, and `retry_closed`
  ticked. Expect `pr_exists=false`, `propose` and `publish` to run, and a new draft
  `bot/azurerm-5.12.0` PR. Run it again without the box: expect `pr_exists=true`
  while that PR is open.
- Don't merge the test branch this time. Close it and delete it after the test.


<!-- blueprint:completion {"schemaVersion":2,"specBytes":3270,"specSha256":"b767378675cf3ac354fb14b91c082398b32651bb313975cbda7c2cacf37fb9f6","branch":"refs/heads/fix/let-a-manual-run-retry-a-closed-bot-pr","head":"331dec35537029af8e8bd7095feb249723319b35","baseRef":"refs/heads/main","baseCommit":"331dec35537029af8e8bd7095feb249723319b35","sourceTree":"59a01e5748ea9f0108664caeb76db3b2343e4a0b","landing":"local-merge","absentOptional":[]} -->
