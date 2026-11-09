# Azure DevOps setup

The pipelines in `.azure-pipelines/` do what the GitHub workflows in `.github/workflows/`
do. YAML can't create pipelines, branch policies, permissions or secrets, so do these
steps once in the Azure DevOps portal. The repo is
`hamzaelouham0104/terraform-azurerm-modules` in Azure Repos.

## 1. Create the pipelines

**Pipelines > New pipeline > Azure Repos Git >** the repo **> Existing Azure Pipelines
YAML file.** Create one pipeline for each file, and rename it to match:

| Pipeline | YAML file | Runs on |
|---|---|---|
| `ci` | `.azure-pipelines/ci.yml` | Pushes to `main`, pull requests (step 2), and a weekly Trivy scan |
| `release` | `.azure-pipelines/release.yml` | Tags `<module>/vX.Y.Z` |
| `check-registry` | `.azure-pipelines/check-registry.yml` | Monthly, and by hand |
| `ai-agent` | `.azure-pipelines/ai-agent.yml` | Pushes to `main` that change `ai-agent/`, and pull requests (step 2) |

## 2. Run checks on pull requests

Azure Repos ignores `pr:` in YAML. Pull requests need build validation policies instead.

Go to **Project settings > Repositories >** the repo **> Policies > Branch policies >
`main` > Build validation**, and add:

1. **`ci`:** trigger automatic, policy requirement required, build expiration after 12
   hours.
2. **`ai-agent`:** trigger automatic, required, path filter
   `/ai-agent/*; /.azure-pipelines/ai-agent.yml`.

These should also run on the upgrade agent's draft PRs. If a draft PR shows a policy
as not started, queue it from the PR's **Checks** panel. A draft PR can't be completed
until it's published.

On the same `main` policy page, also set:

1. **Require a minimum number of reviewers:** at least 1, with:
   - **Allow requestors to approve their own changes** off;
   - **Prohibit the most recent pusher from approving their own changes** on;
   - **When new changes are pushed:** reset all approval votes.
2. **Automatically included reviewers:** add the people or group who maintain this
   library as a **required** reviewer for every path. The build service can vote on
   pull requests, so on its own a minimum count could be met by its vote. A required
   human reviewer can't be.
3. **Bypass:** in the repo's **Security** settings, make sure the build service has
   **Bypass policies when pushing** and **Bypass policies when completing pull
   requests** set to Not set or Deny.

Only PRs a maintainer approved can then reach `main`. The upgrade agent's setup depends
on this (see the risk note in step 4).

## 3. Variable group for the upgrade agent

Go to **Pipelines > Library > + Variable group**, name it `azurerm-upgrade-agent`, and add:

| Variable | Value | Secret |
|---|---|---|
| `OPENAI_API_KEY` | A dedicated key with a spending limit | Yes (lock icon) |
| `AI_AGENT_MODEL` | The model name, with tool calling support | No |
| `OPENAI_BASE_URL` | Only for an OpenAI-compatible service other than OpenAI. Leave it out otherwise | No |

Under **Pipeline permissions**, allow only the `check-registry` pipeline.

Only the `propose` job links this group, and only the agent step gets the key. Neither
Verify run sees it, nor does the job that pushes.

## 4. Permissions for the build service

The pipelines run as **`<project> Build Service (<organization>)`**.

- **Work items:** open **Project settings > Project configuration > Areas**. On the
  root area, under **Security**, set **Edit work items in this node** and **View work
  items in this node** to Allow. The monthly check opens, updates and closes one
  `Task` tagged `azurerm-update`.
- **Repository, whole repo:** open **Project settings > Repositories >** the repo
  **> Security** and select the build service.
  - Set **Read** and **Contribute to pull requests** to Allow. The publish job opens
    the draft PR and its first comment with these.
  - Leave **Contribute**, **Create branch** and **Force push** Not set at this level,
    and check that the effective value isn't Allow (inherited). Repo-wide Contribute
    would let the build identity push to anyone's branch, including another person's
    open PR.
  - Set **Create tag** to **Deny**.
    - **Why:** consumers pin `<module>/vX.Y.Z` tags, and branch policies don't cover
      tags. No pipeline here creates tags; a person creates every release tag.
    - **Check it:** run
      `az devops security permission show --namespace-id 2e9eb7ed-3c0a-47d4-87c1-0ffdd275fd87 --subject "<build service>" --token "repoV2/<project id>/<repo id>"`.
      Create tag (bit 32) should show Deny.
- **Repository, `bot` folder only:**
  - **What to allow:** **Contribute**, **Create branch** and **Force push**, on the
    `bot/` branch folder only.
    - Publish creates `bot/azurerm-<version>`.
    - It uses `git push --force` to replace a branch left over from a run whose PR
      creation failed.
  - **Use the Azure CLI:** set these for the folder, so they also cover bot branches
    that don't exist yet. Branch security in the portal applies to one existing
    branch only.
  - **The token:** Azure stores branch tokens with each path part as hex UTF-16LE.
    `bot` is `62006f007400`. Allow bits 4 (Contribute), 8 (Force push) and 16 (Create
    branch), 28 in total. Run:

    ```sh
    az devops security permission update \
      --namespace-id 2e9eb7ed-3c0a-47d4-87c1-0ffdd275fd87 \
      --subject "<build service descriptor or name>" \
      --token "repoV2/<project id>/<repo id>/refs/heads/62006f007400/" \
      --allow-bit 28
    ```

  - **Check it:** confirm with
    `az devops security permission show` and the same namespace, subject and token.
    Contribute, Create branch and Force push should show Allow.
- **Token scope:** keep **Project settings > Pipelines > Settings > Limit job
  authorization scope to current project** turned on.

**Accepted risk (finding F-58):**

- **Who gets the rights:** Azure Pipelines can't make one job's token read-only. Every
  job runs as the same build service identity, so the `propose` job, which runs
  AI-written Terraform during Verify, has the rights above. So does the `ci` build
  validation on a bot PR.
- **What it allows:** code the agent was steered into writing could push to `bot/`
  branches, open or comment on PRs, or vote on them, without going through
  `check-bot-patch.sh`.
- **What it can't reach:** `main`, other people's branches, and release tags. The build service has
  Contribute only on `bot/`, and `main` needs a required maintainer's approval (step
  2). This holds only with the step 2 and step 4 settings exactly as above.
- **What to do:** review every bot PR's full diff, not only `modules/`, before
  approving it.
- **On GitHub:** this doesn't apply, because the `propose` job's token is read-only.

## 5. Try it

1. **Start it.** Open the `check-registry` pipeline and choose **Run pipeline**. To
   rerun the agent for a version whose bot PR you abandoned, tick **Run the agent even
   if a bot PR for this version was abandoned** (`retryClosed`). Scheduled runs never
   ignore abandoned PRs.
2. **When the reviewed version is behind the registry, expect:**
   - a work item, "azurerm X → Y: review provider changes";
   - a draft PR on `bot/azurerm-<version>`. Its description is the start of the
     proposal, cut to fit Azure's 4,000-character limit. The full proposal, with both
     Verify summaries, is the PR's first comment;
   - the PR's build validation runs. Trust that result, not the Verify run inside the
     `propose` job.
3. **When the versions match**, the run closes the open work item and stops after
   `check`.

Don't start a manual run while another `check-registry` run is still going. GitHub
queues these runs, but this pipeline has no such guard.

## Running on both GitHub and Azure DevOps

Both platforms run the monthly check and the agent. For each azurerm release you get:

- a GitHub issue and an Azure DevOps work item;
- a draft PR on each side, with possibly different proposals because each is its own
  model run.

Review one PR and close the other. **Abandon** it on Azure, or **Close** it on GitHub.
Then sync `main`. Local `origin` fetches from GitHub and pushes to both remotes, so:

- **merged on GitHub:** `git pull`, then `git push`, which also updates Azure Repos;
- **merged in Azure Repos:** `git pull <azure-url> main`, then `git push`.

The next monthly run on the other side sees the new `.azurerm-reviewed-version` and
closes its own issue or work item.
