# Feature: AI upgrade agent on Azure DevOps

**From build-plan:** feature 9
**Build attempt:** 1
**Status:** verified
**Branch:** feature/ai-upgrade-agent-on-azure-devops

## Goal

When the monthly check in Azure Pipelines finds a new azurerm release, the Azure
DevOps project:

- runs the same upgrade agent as GitHub;
- opens a **draft pull request** in Azure Repos for a person to review.

It uses the same three-job trust split as `.github/workflows/check-registry.yml`:

| Job | Can do | Can't do |
|---|---|---|
| `check` | Read the repo, write work items | Push |
| `propose` | Use the model key | Use write credentials in any step (on Azure it still runs as the build identity: accepted risk F-58) |
| `publish` | Write to the repo | Run AI or model code |

The agent's unit tests also run in Azure Pipelines. A setup guide covers the portal
steps that YAML can't do.

## In scope

- **`.azure-pipelines/check-registry.yml`.** Today it's a single job that opens or
  closes the `azurerm-update` work item. It becomes three jobs that mirror GitHub:
  - **`check`:**
    - Install Terraform and run `check-registry.py azure`, which keeps the work item
      behavior.
    - Expose `reviewed`, `new_version` and `major_bump` as job outputs.
    - Set `pr_exists` from the Azure Repos pull requests on
      `refs/heads/bot/azurerm-<version>`.
    - Publish the `azurerm-report` artifact.
  - **`propose`:**
    - No repo credentials (`persistCredentials: false`). The model key comes only
      from the `azurerm-upgrade-agent` variable group, linked at this job only.
    - Same steps as GitHub: install the pinned tools, Verify before the agent, run
      the agent, Verify after it, build `agent-patch.diff`, and publish the
      `agent-proposal` artifact.
  - **`publish`:**
    - No AI and no model key. Only this job maps `System.AccessToken` and keeps
      checkout credentials.
    - Runs `publish-bot-pr.sh <version> <dir> azure`.
  - **`retryClosed`:** a runtime parameter (boolean, default `false`). It does what
    GitHub's `retry_closed` does: when true, an **abandoned** bot PR no longer stops
    the agent. Active and completed PRs still do. Scheduled runs use the default.
- **`scripts/publish-bot-pr.sh`:**
  - **Arguments:** an optional third argument, `github` (the default, today's
    behavior) or `azure`.
  - **Shared steps, unchanged:** the patch check, branch, apply, commit, force-push,
    and the `@` escaping of the body.
  - **The `azure` path:** commits as the Azure Pipelines bot and creates a draft PR
    through the Azure Repos REST API.
    - Azure limits a PR description to 4,000 characters. So the description holds
      the agent's text, cut to fit, with a note that the full proposal is in the
      first comment.
    - The full body, including both Verify summaries, is posted as the PR's first
      comment thread.
- **`.azure-pipelines/ai-agent.yml`:** runs
  `pip install --require-hashes -r ai-agent/requirements-dev.txt` and
  `python -m pytest ai-agent/tests`. It runs on pushes to `main` that touch
  `ai-agent/**` or the file itself, like `.github/workflows/ai-agent.yml`.
- **`docs/azure-devops.md`, a new setup guide:**
  - create the four pipelines from their YAML paths;
  - add build validation on `main` for `ci.yml` and `ai-agent.yml` (Azure Repos
    ignores `pr:` in YAML);
  - create the variable group (`OPENAI_API_KEY` secret, `AI_AGENT_MODEL`, optional
    `OPENAI_BASE_URL`) and authorize it for the check-registry pipeline;
  - give the build service its permissions: create and edit work items; Read and
    Contribute to pull requests on the repo; Create tag denied; and Contribute,
    Create branch and Force push on the `bot` branch folder only (step 7 and 8);
  - explain how two platforms run together (below).
- **Doc updates:**
  - `docs/scripts.md`: the agent diagram and the `publish-bot-pr.sh` row say "GitHub
    and Azure DevOps".
  - `AGENTS.md`: the Commands line "the agent itself only runs in
    `check-registry.yml`" names both platforms.

## Out of scope

- No changes to the agent (`ai-agent/`), the patch check (`check-bot-patch.sh`),
  `check-registry.py`, or the GitHub workflows.
- Running the agent on GitLab CI or Jenkins.
- Syncing GitHub and Azure Repos automatically. Mirroring stays manual, through the
  two push URLs on the local `origin`.
- A tflint `GITHUB_TOKEN` on Azure. If anonymous GitHub rate limits break
  `tflint --init` there, that's a separate fix.
- Stopping two overlapping runs. GitHub has a concurrency group, and Azure has no
  simple YAML equivalent. The setup guide says not to start a manual run while
  another is running. F-36 stays open.
- Creating pipelines, policies, permissions or secrets in the portal. The guide
  documents them, and the user does them.

## Build loop

`workflow.stepReview` is `feature` and checkpoint commits are disabled. So
`/implement` runs every step, checks each step's done-when, runs Verify once at the
end, and presents one review packet. `/complete` creates the feature commit.

## Build steps

- [x] 1. **Azure path in `publish-bot-pr.sh`.**
  - Add the platform argument; anything other than `github` or `azure` fails with
    the usage message.
  - The `azure` path needs `SYSTEM_ACCESSTOKEN`, `SYSTEM_COLLECTIONURI`,
    `SYSTEM_TEAMPROJECT` and `BUILD_REPOSITORY_ID`.
  - It creates the draft PR, then the comment thread (contracts below), and fails
    with the HTTP error when a call fails.
  - Before writing, confirm the current Azure Repos limits for a PR description and
    a thread comment in Microsoft's REST docs, and record them in the spec notes.

  Done when:
  - a scratch run against a local bare remote, with a fake `curl` that records its
    requests, pushes `bot/azurerm-9.9.9` and sends both requests with the expected
    URLs and JSON;
  - the same run with platform `github` calls the fake `gh` with today's arguments;
  - an empty `pr-body.md` or a rejected patch still stops before the push.

- [x] 2. **Three-job `check-registry.yml`.**
  - Turn the pipeline into `check`, `propose` and `publish`, with the
    `retryClosed` parameter and the job conditions below.
  - Done when:
    - the file parses as YAML;
    - the step that turns `GITHUB_OUTPUT` into output variables, run locally on a
      sample file, prints the expected `##vso[task.setvariable …;isOutput=true]`
      lines;
    - the `pr_exists` step, run locally with a fake `curl` and sample responses,
      gives the expected result for each case:

      | PRs on the branch | `retryClosed` off | `retryClosed` on |
      |---|---|---|
      | none | `false` | `false` |
      | abandoned | `true` | `false` |
      | active | `true` | `true` |
      | completed | `true` | `true` |

- [x] 3. **Agent test pipeline and docs.**
  - Add `.azure-pipelines/ai-agent.yml` and `docs/azure-devops.md`, and update
    `docs/scripts.md` and `AGENTS.md`.
  - Done when:
    - both YAML files parse;
    - the guide covers every portal step listed in scope;
    - `pytest ai-agent/tests` passes;
    - `sh scripts/verify.sh` passes.

- [x] 4. **Fix F-57: curl flags.**
  - Use `-sS --fail-with-body` (no `-f`) in the `existing` step and in both Azure
    calls in `publish-bot-pr.sh`.
  - Done when the real curl 8.5.0 runs the `existing` step and the Azure publish path
    against a local HTTP stub:
    - a 200 JSON response gives the expected `pr_exists` and PR id;
    - a 4xx response fails the step with the response body shown.

- [x] 5. **Fix F-59 and F-60: text handling in the Azure path.**
  - Read the body with `errors="ignore"`, so a byte cut inside a character can't crash
    the script.
  - Cut the description by UTF-16 length (`len(text.encode("utf-16-le")) // 2`), so
    it stays within 4,000 however Azure counts.
  - Done when a scratch run with a 60,010-byte multibyte body and an emoji-heavy body
    opens the PR. The description must be at most 4,000 UTF-16 units and end with the
    note.

- [x] 6. **Record the accepted F-58 risk.**
  - **`.azure-pipelines/check-registry.yml`:** correct the `propose` comment. The job
    has no mapped token, but it still runs as the build service identity.
  - **`docs/scripts.md`:** the propose label says read-only only on GitHub.
  - **`docs/azure-devops.md`:**
    - **New step 2 requirement:** a minimum-reviewers policy on `main`, with
      "Bypass policies" denied for the build service.
    - **New risk note in §4:** the propose job and the bot PR's build validation run
      with the build identity's write rights. Agent-written code could push to `bot/`
      branches past the patch check, but not to `main`.
  - Done when those three files say this and `sh scripts/verify.sh` passes.

- [x] 7. **Fix F-61, F-62 and F-63 from the second review.**
  - **`docs/azure-devops.md` §4:**
    - At repo level, the build service gets Read and Contribute to pull requests
      only.
    - Contribute, Create branch and Force push are allowed on the `bot/` folder
      only. They're set with the Azure CLI, using the hex UTF-16LE folder token
      `62006f007400` and allow bits 28, plus a check command.
  - **`docs/azure-devops.md` §2:**
    - **Required reviewer:** a maintainer for every path.
    - **Votes:** "prohibit the most recent pusher" is on, and votes reset on new
      pushes.
    - **Draft PRs:** if a policy hasn't started on a draft PR, the guide says to
      queue it by hand.
  - **The F-58 note and the YAML comment:** narrowed to what the build identity can
    still reach.
  - **`scripts/check-registry.py`:** two comments now name GitHub and Azure. This is a
    comment-only exception to "`check-registry.py` unchanged".
  - Done when the guide and comments say this, both YAML files parse, and
    `sh scripts/verify.sh` passes.

- [x] 8. **Fix F-64, F-65 and F-66 from the third review.**
  - **`check-registry.yml`:**
    - The `registry` and publish steps send their output through
      `sed 's/##vso\[/# #vso[/g'`, with `set -o pipefail` so a failure still fails
      the step.
    - Both steps set `target.settableVariables: none`.
  - **`docs/azure-devops.md` §4:** denies Create tag to the build service, with a
    check command.
  - **The In scope permissions bullet:** now matches the guide.
  - Done when:
    - both steps, run locally with crafted `##vso[` output, print no `##vso[` and keep
      the exit code;
    - YAML parses;
    - `sh scripts/verify.sh` passes.

## Files / areas

- `.azure-pipelines/check-registry.yml` (rewrite)
- `.azure-pipelines/ai-agent.yml` (new)
- `scripts/publish-bot-pr.sh` (Azure path)
- `docs/azure-devops.md` (new), `docs/scripts.md`, `AGENTS.md`
- For reference only, unchanged: `.github/workflows/check-registry.yml`,
  `scripts/check-registry.py` (`write_outputs`, the `Azure` tracker),
  `scripts/check-bot-patch.sh`, `scripts/install-terraform.sh`,
  `scripts/install-tools.sh`

## Data / contracts

**Job outputs.** The `check` job uses step names `registry`, `outputs` and
`existing`:

- **`outputs`** reads the `GITHUB_OUTPUT` file that `check-registry.py` already
  writes. It points that variable at `$(Agent.TempDirectory)/registry-outputs`. It
  re-emits each of `reviewed`, `new_version` and `major_bump` as an output
  variable.
- **`existing`** emits `pr_exists=true|false`, by the rule in the table above.
- Both steps run with `condition: succeededOrFailed()`, because a module that no
  longer validates fails the `registry` step but still needs the agent.

**Pull request lookup.**

```
GET {SYSTEM_COLLECTIONURI}{SYSTEM_TEAMPROJECT}/_apis/git/repositories/{BUILD_REPOSITORY_ID}/pullrequests
    ?searchCriteria.sourceRefName=refs/heads/bot/azurerm-<version>&searchCriteria.status=all&api-version=7.1
```

Authenticated with `Authorization: Bearer $SYSTEM_ACCESSTOKEN`. The project name is
URL-encoded. An API error fails the step, so the agent never runs on an unknown
answer.

**Job conditions.**

- **`propose`:**
  `and(always(), ne(dependencies.check.outputs['outputs.new_version'], ''), eq(dependencies.check.outputs['existing.pr_exists'], 'false'))`
- **`publish`:** `and(always(), eq(dependencies.propose.result, 'Succeeded'))`

**Agent inputs.**

- The pipeline passes `reviewed`, `new_version` and `major_bump` from `check`
  outputs into `python ai-agent/main.py "$REVIEWED" "$VERSION" "$MAJOR_BUMP"`.
- The model settings come from the `azurerm-upgrade-agent` variable group:
  - `OPENAI_API_KEY`: secret, mapped only into the agent step;
  - `AI_AGENT_MODEL`: required;
  - `OPENAI_BASE_URL`: optional, defined as an empty YAML variable ahead of the
    group, so a missing value is an empty string and not the literal
    `$(OPENAI_BASE_URL)`.
- Neither Verify step gets the key.

**Artifacts.** `azurerm-report` holds `azurerm-report.md`,
`azurerm-release-notes.md` and `azurerm-affected.json`. `agent-proposal` holds
`agent-patch.diff`, `pr-body.md`, `verify-baseline.txt` and `verify-final.txt`.
These match GitHub.

**Draft PR.**

```
POST …/_apis/git/repositories/{BUILD_REPOSITORY_ID}/pullrequests?api-version=7.1
{"sourceRefName": "refs/heads/bot/azurerm-<version>", "targetRefName": "refs/heads/main",
 "title": "azurerm <version>: proposed module changes", "description": "<cut to the limit>",
 "isDraft": true}
```

Then:

```
POST …/pullRequests/{pullRequestId}/threads?api-version=7.1
{"comments": [{"parentCommentId": 0, "content": "<full escaped body>", "commentType": 1}],
 "status": 1}
```

JSON is built with `python3 -I -c 'import json…'`, never by joining strings. The
commit author is `Azure Pipelines <azure-pipelines@noreply.dev.azure.com>`.

**Two platforms together.** This was decided on 2026-11-09: both run monthly.

- Each platform opens its own tracker item and draft PR for a release.
- Review one PR and close or abandon the other.
- After a merge on one side, pull and push from a local clone. Both push URLs then
  update the other remote.
- The setup guide says this plainly.

## Testing

- `pytest ai-agent/tests` and `sh scripts/verify.sh`, the declared commands.
- The shell and YAML pieces have no test runner. The local checks in each step's
  done-when are scratch-only and aren't committed.
- Nothing here proves the pipeline works in Azure DevOps, since there's no portal
  access from this machine. After landing, the user:
  1. follows `docs/azure-devops.md`;
  2. runs the check-registry pipeline by hand with `retryClosed` set;
  3. expects a work item, a draft PR on `bot/azurerm-<version>` in Azure Repos with
     the full proposal in its first comment, and that PR's build-validation run.

## Notes for the AI

- Keep each job's trust level the same as on GitHub. Map secrets only into the
  steps that need them. Azure only puts secret variables and `System.AccessToken`
  into a script's environment when the step maps them under `env:`.
- `check-registry.py` already works on Azure with the `azure` argument. Leave it
  unchanged, and change only the pipeline around it.
- Azure hosted Ubuntu agents have `curl`, `unzip`, `python3` and `jq`. Prefer
  `python3 -I` over `jq` for building JSON. Install Python 3.13 with the
  `UsePythonVersion@0` task, so the agent runs on the same Python as on GitHub.
- No AI attribution in commits or the PR body.
- **Text limits, checked on 2026-11-09:**
  - Microsoft's REST docs for Pull Requests - Create and Threads - Create (7.1)
    confirm `isDraft` and the thread body shape. They don't document a length limit
    for either field.
  - The description is cut to 4,000 characters, the limit Azure Repos enforces in
    practice.
  - The comment carries the same body as GitHub, which is already cut at 60,000
    characters before the Verify summaries are added.
  - If Azure rejects the comment, the draft PR exists but has only the cut
    description. The next run then sees `pr_exists=true`.


<!-- blueprint:completion {"schemaVersion":2,"specBytes":15847,"specSha256":"0a0b3795b10e65ec33542315f9ea5246572213a36249e749e61c1562f46d1ebb","branch":"refs/heads/feature/ai-upgrade-agent-on-azure-devops","head":"6602ca3add692075e3b0b1dc2275e40eecdd92c3","baseRef":"refs/heads/main","baseCommit":"a8b4574675e51d2636938fd143382b8c8d8ee183","sourceTree":"47d211e4d34fb0fdad61e3bd0b79b6ba77192b45","landing":"local-merge","absentOptional":[]} -->

## Findings

### 9/F-57 [P1] closed - curl rejects -f with --fail-with-body, so the PR lookup and both Azure PR calls always fail

**File:** .azure-pipelines/check-registry.yml:62
**Found:** 2026-11-09 by /audit independent (scope: current; lens: quality, tests)
**Why it matters:** The `existing` step (line 62) and both Azure calls in `scripts/publish-bot-pr.sh` (lines 113 and 116) run `curl -fsS --fail-with-body`. curl treats `--fail` and `--fail-with-body` as mutually exclusive: curl 8.5.0, the version on Ubuntu 24.04 (`ubuntu-latest`), exits 2 with "option --fail-with-body: is badly used here" before sending anything. Running the committed `existing` script with the real curl exits 2, so under `set -eu` the step fails, `pr_exists` is never set, and `propose` never runs. The agent can never run on Azure. If it did, `publish-bot-pr.sh` would push `bot/azurerm-<version>` and then fail before creating the PR. The step done-when checks used a fake `curl` that accepted any arguments, which hid this.
**Suggested fix:** Drop `-f` and keep `-sS --fail-with-body` (or keep `-fsS` without `--fail-with-body`) in all three calls. Then rerun the scratch checks with the real curl against a local HTTP stub that returns 200 and 4xx responses.
**Resolution:** Fixed 2026-11-09 in feature 9 step 4: all three calls use `-sS --fail-with-body` and print Azure's error body on failure. The real curl 8.5.0 ran the `existing` step and the Azure publish path against a local HTTP stub: 200 responses gave the expected `pr_exists` and PR id 42, and 403 responses failed with the TF401027 message shown.
Closed 2026-11-09 by /audit independent (re-review of 7679ccc): no `-f` remains next to `--fail-with-body` in either file. The `existing` script, extracted from the committed YAML with PyYAML, ran with the real curl 8.5.0 against a local HTTP stub and matched all eight cells of the spec table (none/abandoned/active/completed x retryClosed False/True), sent the URL-encoded project path and the bearer header, and on a 403 exited 1 with Azure's message printed. The committed `publish-bot-pr.sh azure`, run from a clone of the target with the real curl, pushed `bot/azurerm-9.9.1`, posted both requests with the spec's JSON, and printed `Opened draft PR 42.`; a 403 exited 1 with the response body shown. No new defect in the repaired lines.

### 9/F-58 [P1] accepted - The propose job still holds the build service token, which this feature gives repo write access

**File:** .azure-pipelines/check-registry.yml:90
**Found:** 2026-11-09 by /audit independent (scope: current; lens: security)
**Why it matters:** The spec's trust table says `propose` can't write anything, and the comment at lines 90-93 says the job has "no System.AccessToken". Not mapping the token only keeps it out of script environments. Azure Pipelines has no per-job token permissions: every job gets a job access token for the same `<project> Build Service` identity, and the agent uses it for checkout, `download` and `publish` steps. On Microsoft-hosted Ubuntu agents, pipeline scripts run as the agent user with passwordless sudo, so code in the job can read the agent process's memory or environment. The pipeline's own comment says a malicious release note can steer the agent's HCL, and Verify after the agent runs `terraform init`/`validate` on that HCL, which runs any provider binary it declares. `docs/azure-devops.md` §4 now grants this identity repo-wide Contribute, Create branch, Contribute to pull requests, and Force push on `bot/`. So that code can push unchecked content past `check-bot-patch.sh`, force-push other bot branches, open PRs and edit work items. On GitHub the same job's `GITHUB_TOKEN` is `contents: read`. The same identity also runs the `ci` build validation that §2 adds. That validation runs automatically on the bot's draft PR, before anyone reviews it, and it runs the agent-written HCL. `docs/scripts.md` still labels propose "(read only, model key)" for both platforms. This was not reproduced in Azure because there is no portal access. It rests on Microsoft's documented job-token model and hosted-agent sudo.
**Suggested fix:** This needs a user decision because it changes the spec and setup. Keep the project build service read-only, apart from the work-item rights `check` needs. Give `publish` a separate write credential that only it receives, such as a bot PAT or a service connection in a secret variable group linked only to that job (optionally a deployment job behind an environment approval). Scope that credential to Create branch, Contribute and Force push on `refs/heads/bot/` plus Contribute to pull requests. Then update §4 of the guide, the trust table, and the YAML comment. If the risk is accepted instead, record that the Azure `propose` job and bot-PR build validation have the build identity's write rights.
**Resolution:** Accepted by the user on 2026-11-09 in chat. They chose to keep one build service identity with write access instead of a separate publish credential. The reason is that `main`'s branch policy requires a reviewed PR, so a bypass of the patch check can reach `bot/` branches and PRs but not `main`. Feature 9 step 6 states this risk in the YAML comment, in `docs/scripts.md`, and in `docs/azure-devops.md`, and makes the reviewer requirement on `main` (with no bypass for the build service) part of the setup.

### 9/F-59 [P2] closed - A 60,000-byte cut inside a multibyte character crashes the Azure path after the push

**File:** scripts/publish-bot-pr.sh:102
**Found:** 2026-11-09 by /audit independent (scope: current; lens: quality)
**Why it matters:** The body is cut with `head -c 60000`, which counts bytes, and the Azure path then reads it with Python's strict UTF-8 decoding. A scratch run with a 60,010-byte `pr-body.md` whose byte 60,000 falls inside "é" raised `UnicodeDecodeError` after `bot/azurerm-9.9.9` had been pushed, so no PR was created. The agent puts no size cap on `pr-body.md`, so a long, non-ASCII proposal reaches this. The next run retries, so nothing is lost, but that month's proposal never reaches a reviewer.
**Suggested fix:** In the Azure Python step, read with `open(sys.argv[1], encoding="utf-8", errors="ignore")`, or cut by characters there instead of with `head -c`. The GitHub path is unchanged.
**Resolution:** Fixed 2026-11-09 in feature 9 step 5: the Azure path reads the body with `errors="ignore"`. A scratch run whose byte-60,000 cut lands inside "é" opened the PR.
Closed 2026-11-09 by /audit independent (re-review of 7679ccc): a 60,010-byte `pr-body.md` whose byte 60,000 is the first byte of "é" ran through the committed Azure path with the real curl and opened the PR (exit 0); the thread content kept the 59,999 ASCII bytes and dropped only the split character. The GitHub path is unchanged (fake `gh` received `pr create --draft --base main --head bot/azurerm-9.9.5 ...`).

### 9/F-60 [P3] closed - The 4,000-character description cut counts code points, not UTF-16 units

**File:** scripts/publish-bot-pr.sh:104
**Found:** 2026-11-09 by /audit independent (scope: current; lens: quality)
**Why it matters:** `body[:4000 - len(note)]` counts Python code points. If Azure Repos enforces its 4,000-character limit as a .NET string length (UTF-16 units), a description with characters outside the BMP, such as emoji in the agent's text, goes over it. A scratch run with emoji gave a 4,000-code-point description that is 4,135 UTF-16 units, so PR creation would fail after the push. Unverified: how Azure counts was not tested.
**Suggested fix:** Cut by UTF-16 length (encode to `utf-16-le` and halve the byte count), or leave a margin such as 3,900.
**Resolution:** Fixed 2026-11-09 in feature 9 step 5: the description is cut by UTF-16 length. Emoji-heavy and multibyte scratch bodies gave descriptions of exactly 4,000 UTF-16 units ending with the cut note.
Closed 2026-11-09 by /audit independent (re-review of 7679ccc): with the committed script and the real curl, a 5,000-emoji body gave a description of 4,000 UTF-16 units (2,042 code points) ending with the cut note, and the 60,010-byte multibyte body gave 4,000 units ending with the note. The trim loop is bounded by the description length. How Azure counts its limit is still untested against the service (Remaining risk in the receipt), but the cut now holds under either counting.

### 9/F-61 [P1] closed - Repo-wide Contribute lets the build identity reach main through another person's PR, so F-58's "can't reach main" doesn't hold

**File:** docs/azure-devops.md:68
**Found:** 2026-11-09 by /audit independent (scope: current; lens: security)
**Why it matters:** F-58 was accepted on the condition that agent-steered code in `propose` "can reach `bot/` branches and PRs but not `main`", and the YAML comment (`.azure-pipelines/check-registry.yml:98-101`), the guide (§2 line 43 "Only reviewed PRs can then reach `main`", §4 line 93) and the spec's step 6 all state that boundary. The setup in §4 doesn't produce it. It grants the build service **Contribute** and **Create branch** at repository scope (lines 70-73), not on the `bot` folder, plus repo-wide **Contribute to pull requests**. With those rights the identity can push commits to any branch without a policy (any person's work branch, not only `bot/`), create branches anywhere, vote on pull requests, and complete them. The §2 policy only requires one approver and blocks the *requestor* from approving. It doesn't enable "Prohibit the most recent pusher from approving their own changes" or "Reset votes when there are new changes". So code running in `propose` (or in the `ci` validation of a bot PR) can push a commit to the source branch of a person's open PR to `main`, approve that PR as the build service (it isn't the requestor), and complete it once `ci` passes. Unreviewed content then reaches `main`. It needs an open PR by someone else in Azure Repos at the time of the run. Not reproduced, since there's no portal access. It rests on Azure Repos' documented permission scopes and branch-policy options, the same basis as F-58. It's P1 because the accepted risk's stated limit, which the user's decision relies on, is false for the documented setup.
**Suggested fix:** Smallest repair, keeping the user's single-identity decision: in §4, grant **Contribute** and **Create branch** to the build service only on the `bot` branch folder (the same scope as Force push), not on the repository. Without Contribute on `main` it can't complete a PR into `main`, and it can't push to other people's branches. Optionally also enable "Prohibit the most recent pusher from approving their own changes" in §2. Then make the YAML comment, the §4 risk note and the spec state the limit that actually holds. If the user prefers to keep repo-wide rights, the risk note must instead say that the build identity can push to any unprotected branch and approve and complete other people's PRs. That is a new decision for the user, not covered by the F-58 acceptance.
**Resolution:** Fixed 2026-11-09 in feature 9 step 7. `docs/azure-devops.md` §4 now gives the build service only Read and Contribute to pull requests at repo level. Contribute, Create branch and Force push are allowed only on the `bot/` folder. §2 adds a required maintainer reviewer for every path, "prohibit the most recent pusher", and vote reset, so neither a push to another person's branch nor a build-service vote can complete a PR into `main`. The F-58 note and the YAML comment now state that narrower reach.
Closed 2026-11-09 by /audit independent (re-review of 20d55b6): `docs/azure-devops.md:76-107` now grants only Read and Contribute to pull requests at repo level, tells the user to confirm Contribute, Create branch and Force push aren't inherited Allow there, and allows those three only on the `bot` folder token. §2 (lines 38-48) adds a required maintainer reviewer for every path, requestor self-approval off, "prohibit the most recent pusher", vote reset on new pushes, and no bypass for the build service. Without Contribute outside `bot/`, the build identity can't push to another person's PR branch, and its vote can't stand in for the required maintainer, so the F-61 path to `main` is gone. The YAML comment (`.azure-pipelines/check-registry.yml:98-101`) and the §4 risk note state the narrower reach. Not run against Azure DevOps. Separate new findings in the same area: F-64 (the `check` job is a further non-AI route to the same identity) and F-65 (tags are outside the stated bound, unverified).

### 9/F-62 [P2] closed - The Force push setup for the `bot` folder may not cover future bot branches

**File:** docs/azure-devops.md:78
**Found:** 2026-11-09 by /audit independent (scope: current; lens: quality)
**Why it matters:** The publish job needs Force push only when `bot/azurerm-<version>` already exists: a retry after a failed PR creation, or `retryClosed` after an abandoned PR, whose branch Azure doesn't delete. The guide gives two ways to set it. "Branch security on any `bot/...` branch" in the portal sets the permission on that one branch, not on the folder, so later version branches wouldn't get it. The `az devops security permission update` example uses the token `repoV2/<project id>/<repo id>/refs/heads/bot/`, but the Git Repositories namespace encodes each branch path segment after `refs/heads/` as hex UTF-16LE (for example `bot` is `62006f007400`). With a plain-text token the ACL may not match the folder. In that case the documented `retryClosed` flow fails at `git push --force` after the earlier PR was abandoned. Unverified: no Azure DevOps access here to confirm the token format or the portal's folder-security option.
**Suggested fix:** Check the token format against Microsoft's "Require branches to be created in folders" and "security namespace" docs (or list an existing ACL with `az devops security permission list`) and correct the example. Change the portal instruction to set the permission on the `bot` folder.
**Resolution:** Fixed 2026-11-09 in feature 9 step 7. The guide now sets the folder permissions with the Azure CLI, using the hex UTF-16LE token `refs/heads/62006f007400/` (`bot` encoded with `python3 -c "print(''.join(f'{b:02x}' for b in 'bot'.encode('utf-16-le')))"`) and allow bits 28, plus an `az devops security permission show` check. It drops the per-branch portal route. Not run against Azure DevOps.
Closed 2026-11-09 by /audit independent (re-review of 20d55b6): `docs/azure-devops.md:90-107` sets the rights on the folder token `repoV2/<project id>/<repo id>/refs/heads/62006f007400/` in the Git Repositories namespace `2e9eb7ed-3c0a-47d4-87c1-0ffdd275fd87`. That matches the documented per-segment hex UTF-16LE branch token format, so `bot/azurerm-<version>` branches created later inherit it. `python3 -c "print(''.join(f'{b:02x}' for b in 'bot'.encode('utf-16-le')))"` printed `62006f007400`. Bits 4 (GenericContribute) + 8 (ForcePush) + 16 (CreateBranch) = 28. The per-branch portal route is gone and a `permission show` check is given. Running the command against a real organization is still untested (Remaining risk in the receipt).

### 9/F-63 [P3] closed - check-registry.py still says only GitHub runs the agent

**File:** scripts/check-registry.py:342
**Found:** 2026-11-09 by /audit independent (scope: current; lens: quality)
**Why it matters:** After this feature, Azure Pipelines also runs the agent and also sets `GITHUB_OUTPUT` (the `registry` step's env). But the comment at line 342 still reads "Only GitHub runs the agent; the other platforms keep the report-only check", and the `write_outputs` docstring (line 180) says it "tells later GitHub Actions jobs". Behaviour is right, because the `GITHUB_OUTPUT` checks now cover Azure too. But a maintainer reading the comment would think the missing-guide guard and the outputs are GitHub-only. The spec put `check-registry.py` out of scope, so this drift was left on purpose, but it isn't recorded anywhere.
**Suggested fix:** Change the two comments to "GitHub Actions and Azure Pipelines run the agent (both set GITHUB_OUTPUT)". That needs the user to allow a comment-only edit to `check-registry.py`, or it can be left for a follow-up. No behaviour change.
**Resolution:** Fixed 2026-11-09 in feature 9 step 7. The `write_outputs` docstring and the comment before the missing-guide exit in `scripts/check-registry.py` now name GitHub and Azure Pipelines. These are comment-only changes.
Closed 2026-11-09 by /audit independent (re-review of 20d55b6): `git diff a8b4574..20d55b6 -- scripts/check-registry.py` shows only the `write_outputs` docstring (line 180) and the comment before the missing-guide exit (line 342) changed, and both now name GitHub and Azure Pipelines. No code changed. `sh scripts/verify.sh` passed on the target.

### 9/F-64 [P2] closed - Release-note text printed in the Azure check job runs as logging commands, so the check job can be made to run code as the build identity

**File:** .azure-pipelines/check-registry.yml:30
**Found:** 2026-11-09 by /audit independent (scope: current; lens: security)
**Why it matters:** The `registry` step runs `check-registry.py azure`, and that script prints the report to stdout (`scripts/check-registry.py:328`). The report copies release-note bullets word for word, and the pipeline treats release notes as untrusted. The Azure agent runs any `##vso[...]` logging command it finds in a step's output. `task.setvariable` turns a variable into an environment variable for every later step. A scratch run of `build_report` with a bullet such as ``* `azurerm_resource_group` - ##vso[task.setvariable variable=BASH_ENV]$(cmd)`` produced that text in a report line. `BASH_ENV='$(cmd) ([v4.99.0](…))' bash --noprofile --norc step.sh` ran `cmd` before the step, and Azure's `script:` steps run that way. So one bullet in an upstream release note, with no model involved, runs code in the `outputs` and `existing` steps. `existing` has `SYSTEM_ACCESSTOKEN` mapped, and the job runs as the build identity, which now has Contribute and Force push on `bot/` and Contribute to pull requests. This breaks the spec's trust table (`check`: "Can't do: Push"). The F-58 note in `docs/azure-devops.md:113-116` names only `propose` and the bot PR's `ci` run as holders of these rights. The identity's reach is the same as what F-58 accepted, but this route needs no steering of the model. On GitHub the same print is harmless, because the check token is read-only for contents and workflow commands can't set environment variables. Not run on a real Azure agent. The agent's logging-command handling and `setvariable`-to-environment behavior are documented by Microsoft.
**Suggested fix:** Add `target: { settableVariables: none }` to the `registry` step. That step sets no variables of its own, so this blocks `setvariable` and `prependpath` from it. Alternatively, send its stdout to a file. The spec allows no change to `check-registry.py`. Then name the `check` job in the F-58 note. If the user would rather accept this, that is their decision, recorded with a reason. It is not covered by the F-58 acceptance, which was about agent-written code in `propose`.
**Resolution:** Fixed 2026-11-09 in feature 9 step 8. The `registry` step and the publish step pipe their output, stderr included, through `sed -u 's/##vso\[/# #vso[/g'` under `set -o pipefail`, and both set `target.settableVariables: none`. Both step scripts, taken from the YAML and run in bash with fake scripts that print crafted `##vso[` lines (setvariable BASH_ENV, prependpath, artifact.upload), left no raw `##vso[` and kept exit codes 0 and 1.
Closed 2026-11-09 by /audit independent (re-review of 6602ca3): `.azure-pipelines/check-registry.yml:32-38` and `:177-183` pipe stdout and stderr through `sed -u 's/##vso\[/# #vso[/g'` under `set -o pipefail`, and both steps set `target.settableVariables: none` (confirmed with PyYAML). Both step scripts, extracted from the committed YAML and run with `bash --noprofile --norc` (how Azure runs `script:` on Linux) against fakes printing `##vso[task.setvariable variable=BASH_ENV]`, `artifact.upload`, `prependpath` and back-to-back prefixes on stdout and stderr, printed no raw `##vso[` and kept exit codes 0 and 1. The real publish step, run from a clone of the target with the real curl 8.5.0 against a local stub, opened draft PR 42 (exit 0) with a `##vso[` line in `pr-body.md`, and exited 1 with Azure's message on a 403; the PR body itself is unchanged, only the log is defanged. The other `check` steps print only regex-validated versions (`check-registry.py:310`), a count, or Azure's own error body. Not run on a real Azure agent; the defang relies on the agent matching the case-sensitive `##vso[` prefix (Remaining risk in the receipt).

### 9/F-65 [P1] closed - The setup doesn't remove Create tag, so the build identity may tag unreviewed bot commits as module releases

**File:** docs/azure-devops.md:76
**Found:** 2026-11-09 by /audit independent (scope: current; lens: security)
**Why it matters:** The F-58 acceptance and §4 (lines 120-122) bound the build identity's reach to `bot/` branches and PRs: "not `main`". But module releases are git tags. Consumers pin `?ref=<module>/vX.Y.Z` (`blueprint/context/project-overview.md:100`), and AGENTS.md says pipelines and agents never create tags. §4 checks only Contribute, Create branch and Force push at repo level, and leaves **Create tag** at its inherited value. Microsoft's documentation for running Git commands from a pipeline lists Create tag as allowed by default for the build service. If that holds, code running as the build identity can push a new `<module>/vX.Y.Z` tag on a commit already on a `bot/` branch. That code can come from agent-written HCL in `propose`, the bot PR's `ci` run, or F-64. Branch policies don't cover tags. The `release` pipeline's `release-check.sh` would then fail ("isn't on main"), but the tag stays in Azure Repos and resolves for any consumer that uses that remote. Unverified because there's no portal access: the effective default of Create tag for `<project> Build Service`, and whether consumers resolve module sources from Azure Repos or only from GitHub, were not checked.
**Suggested fix:** In §4, add **Create tag** to the repo-level rights that must not be effectively Allow for the build service. If it's inherited Allow, set it to Deny for the build service on the repo. Add tags to the "What it can't reach" line only after that check. To confirm, run `az devops security permission show` for the build service on token `repoV2/<project id>/<repo id>` and look at bit 32 (CreateTag).
**Resolution:** Fixed 2026-11-09 in feature 9 step 8. `docs/azure-devops.md` §4 now sets Create tag to Deny for the build service at repo level, with an `az devops security permission show` check (bit 32). The F-58 note lists release tags as out of reach. The default value wasn't checked against Azure DevOps (no portal access), so the guide denies it explicitly whatever the default.
Closed 2026-11-09 by /audit independent (re-review of 6602ca3): `docs/azure-devops.md:84-89` sets Create tag to Deny for the build service at repo level, whatever the default, with an `az devops security permission show` check on `repoV2/<project id>/<repo id>` in the Git Repositories namespace `2e9eb7ed-3c0a-47d4-87c1-0ffdd275fd87`, bit 32 (CreateTag). Moving or deleting an existing tag needs Force push, which the build service has only on the `bot` folder token, so release tags are out of reach and the F-58 note (line 126) now says so. No pipeline creates tags (`grep` of `.azure-pipelines/`), so the Deny breaks nothing. Not run against Azure DevOps.

### 9/F-66 [P3] closed - The spec's In scope still lists repo-wide Contribute and Create branch for the build service

**File:** blueprint/context/current-feature.md:73
**Found:** 2026-11-09 by /audit independent (scope: current; lens: quality)
**Why it matters:** The In scope guide bullet still says to give the build service "Contribute, Create branch and Contribute to pull requests on the repo". Step 7 and `docs/azure-devops.md` §4 now grant only Read and Contribute to pull requests at repo level, and Contribute and Create branch only on `bot/`. The trust table also says `check` can't push. That stops being true on Azure once F-64 is counted. The spec is archived as the feature's record, so a later reader could restore the repo-wide grant that F-61 removed.
**Suggested fix:** Update the In scope permissions bullet to match step 7 and §4. This is a spec-only edit, and it changes the spec hash, so the next review needs a new request.
**Resolution:** Fixed 2026-11-09 in feature 9 step 8. The In scope permissions bullet now matches the guide: Read and Contribute to pull requests on the repo, Create tag denied, and Contribute, Create branch and Force push on the `bot` folder only.
Closed 2026-11-09 by /audit independent (re-review of 6602ca3): `blueprint/context/current-feature.md:73-75` now lists work items; Read and Contribute to pull requests on the repo; Create tag denied; and Contribute, Create branch and Force push on the `bot` folder only. That matches `docs/azure-devops.md:72-113` and step 7 and 8. With F-64 closed, release-note text can no longer set variables in `check`, so the trust table's "`check`: can't push" holds again.

## Independent review

**Status:** passed
**Target commit:** 6602ca3add692075e3b0b1dc2275e40eecdd92c3
**Base commit:** a8b4574675e51d2636938fd143382b8c8d8ee183
**Base ref:** main
**Spec hash:** 0a0b3795b10e65ec33542315f9ea5246572213a36249e749e61c1562f46d1ebb
**Prepared by:** claude
**Builder model:** claude-opus-5-5
**Requested reviewer:** claude
**Requested model:** claude-opus-5-5
**Requested execution:** automatic
**Requested at:** 2026-11-09T12:01:42Z
**Workflow:** regular
**Check required:** no
**Reviewer adapter:** claude
**Reviewer model:** claude-opus-5-5
**Reviewer context:** fresh subagent
**Actual execution:** automatic
**Reviewed at:** 2026-11-09T12:09:03Z
**Scope:** current
**Lenses:** quality, security, performance, tests
**Verdict:** passed
**Check result:** not-required

### Handoff

Review the active spec and the complete `a8b4574675e51d2636938fd143382b8c8d8ee183..6602ca3add692075e3b0b1dc2275e40eecdd92c3` delta in a fresh
session or isolated subagent without the builder conversation. Run all Audit lenses from scratch.
Run Check when required above. Do not edit product code, accept findings, or
reuse the existing findings as the review scope.

### Commands

- `git rev-parse HEAD`, `git merge-base main HEAD`, `sha256sum blueprint/context/current-feature.md`, `git status --porcelain --untracked-files=all`: pass (HEAD, base and spec hash match the request; only `blueprint/context/review.md` differs)
- `git diff a8b4574..6602ca3` (full delta, 13 files) and `git diff 20d55b6..6602ca3`: reviewed
- PyYAML parse of `.azure-pipelines/check-registry.yml` and `.azure-pipelines/ai-agent.yml`, with a per-step listing of mapped `env:` keys: pass
- `bash --noprofile --norc` on the `registry` and publish step scripts extracted from the YAML, with fakes printing crafted `##vso[` lines and exiting 0 or 1: pass (no raw `##vso[`; exit codes 0 and 1 kept)
- Committed publish step from a clone of the target, real curl 8.5.0 against the local stub: pass (draft PR 42 opened, exit 0; on 403, exit 1 with Azure's message)
- `sh -n scripts/publish-bot-pr.sh`: pass
- `python -m pytest -q ai-agent/tests` (scratch venv): pass (65 passed)
- `sh scripts/verify.sh`: pass ("All checks passed.")
- Dashboard activity helper (`run-state.mjs`): not run, because this reviewer may write only the two review files

### Evidence

- Secrets: `System.AccessToken` is mapped only into `registry`, `existing` (check) and "Open the draft PR" (publish). `OPENAI_API_KEY` is mapped only into "Run the agent". The group is linked only in `propose`, whose checkout has `persistCredentials: false`. Only publish keeps checkout credentials.
- Logging commands: both token-holding steps that print untrusted text defang `##vso[` and set `settableVariables: none`. The other `check` steps print only versions checked against `\d+\.\d+\.\d+` (`scripts/check-registry.py:310`), a count, or Azure's error body.
- `scripts/publish-bot-pr.sh` runs `check-bot-patch.sh` before `git apply`, and only reads the artifact's files as data. JSON is built with `python3 -I`, and the token goes into a header file inside a `mktemp -d` folder that is deleted on exit.
- The YAML mirrors `.github/workflows/check-registry.yml`: the same outputs, `pr_exists` rule, job conditions, artifacts and step order. The only gaps are the ones the spec puts out of scope (no concurrency group, F-36; no tflint `GITHUB_TOKEN`).
- F-58 boundary: `docs/azure-devops.md` §2 requires a maintainer reviewer, resets votes, blocks the most recent pusher and denies bypass. §4 grants Read and Contribute to pull requests at repo level, denies Create tag, and grants bits 28 only on the `bot` folder token `refs/heads/62006f007400/`. That makes "can't reach `main` or release tags" true. F-67 records two docs gaps around it.
- F-64, F-65 and F-66 were re-examined against the target and closed with evidence in the ledger. F-58 stays `accepted`.

### Findings

- F-64 [P2] closed
- F-65 [P1] closed
- F-66 [P3] closed
- F-67 [P3] open: the guide doesn't say what to do when repo-wide Contribute is inherited Allow, and the F-58 note leaves out work items
- No P0 or P1 finding is open or fixed

### Remaining risk

- Nothing ran in Azure DevOps (no portal access). Not checked: the pipeline end to end, the build service's default rights, the hex folder token, `az devops security permission` behavior, and the 4,000-character description limit.
- The `##vso[` defang assumes the Azure agent matches the prefix case-sensitively. `##VSO[` passes through `sed` unchanged. `settableVariables: none` still blocks variable injection in both steps, but not other commands such as `artifact.upload`.
- F-58 (accepted): `propose` and the bot PR's `ci` run hold the build identity's write rights on `bot/` and on pull requests.
- The first work item with the new `azurerm-update` tag may need the project-level "Create tag definition" permission for the build service. The guide doesn't mention it. This is unverified and was already true before this feature.
- Dashboard activity tracking was not written in this review session.
- No browser or runtime Check was required, so none was run.
