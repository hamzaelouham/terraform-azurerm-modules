# Scripts and when they run

Every check in this repo is a script under `scripts/`. The four CI platforms (GitHub
Actions, Azure Pipelines, GitLab CI, Jenkins) only install tools and call these
scripts, so a local run and a pipeline run do the same thing.

Each section has a picture, then the same flow as a Mermaid diagram that GitHub draws
from text, which is easier to keep up to date when a script changes.

## The map

Who starts each use case, which pipeline runs, and which scripts it calls.

![Who runs which script](scripts-overview.png)

```mermaid
flowchart LR
  subgraph who["Trigger"]
    dev(["Developer<br/>on a laptop"])
    pr(["Pull request or<br/>push to main"])
    weekly(["Weekly schedule<br/>Monday 06:00 UTC"])
    tag(["Owner pushes a tag<br/>module/vX.Y.Z"])
    monthly(["Monthly schedule<br/>1st, 07:23 UTC"])
  end

  subgraph pipe["Pipeline"]
    ci["ci.yml / .gitlab-ci.yml / Jenkinsfile<br/>Verify job"]
    scan["ci.yml / .gitlab-ci.yml / Jenkinsfile<br/>weekly scan job"]
    rel["release.yml / .gitlab-ci.yml / Jenkinsfile<br/>release check"]
    reg["check-registry.yml / .gitlab-ci.yml / Jenkinsfile<br/>azurerm update check"]
  end

  subgraph scripts["scripts/"]
    tools["install-tools.sh"]
    tf["install-terraform.sh"]
    verify["verify.sh"]
    trivy["trivy-scan.sh"]
    release["release-check.sh"]
    registry["check-registry.py"]
    gate["check-bot-patch.sh"]
    publish["publish-bot-pr.sh"]
  end

  dev --> tools & verify & trivy & gate
  pr --> ci --> tools & verify
  weekly --> scan --> tools & trivy
  tag --> rel --> tools & release
  monthly --> reg --> registry
  reg -. "GitLab, Azure, Jenkins" .-> tf
  reg -. "GitHub only: AI agent" .-> verify & publish

  release --> verify & trivy
  publish --> gate
```

## How the scripts call each other

```mermaid
flowchart TD
  tools["install-tools.sh<br/>tflint, trivy, terraform-docs<br/>into .tools/bin"]
  tf["install-terraform.sh &lt;version&gt;<br/>terraform into .tools/bin"]
  verify["verify.sh [module]<br/>fmt, init, validate, tflint,<br/>trivy HIGH+, terraform-docs, test"]
  trivy["trivy-scan.sh &lt;severity&gt; [module]"]
  release["release-check.sh<br/>RELEASE_TAG=module/vX.Y.Z"]
  registry["check-registry.py [github|gitlab|azure]"]
  gate["check-bot-patch.sh &lt;patch&gt;"]
  publish["publish-bot-pr.sh &lt;version&gt; &lt;dir&gt;"]

  tools -. "provides tools for" .-> verify & trivy
  tf -. "provides terraform for" .-> registry
  release -- "verify.sh module" --> verify
  release -- "trivy-scan.sh MEDIUM module" --> trivy
  publish -- "gates the patch first" --> gate
  registry -- "terraform validate<br/>on every module" --> mods[("modules/*")]
  verify --> mods
  trivy --> mods
```

## Use case 1: a developer checks a change

![Use case 1](scripts-uc1-developer.png)

```mermaid
flowchart LR
  a["sh scripts/install-tools.sh<br/>(once)"] --> b["terraform fmt -recursive"]
  b --> c["sh scripts/verify.sh<br/>or verify.sh aks"]
  c -- "All checks passed." --> d["open a PR"]
  c -- "Failed checks: ..." --> b
  c -.-> e["sh scripts/trivy-scan.sh MEDIUM aks<br/>(before asking for a release)"]
```

`verify.sh` keeps going after a failure, so one run lists every failing check.

## Use case 2: a pull request or a push to main

![Use case 2](scripts-uc2-pull-request.png)

```mermaid
sequenceDiagram
  participant G as Git host
  participant P as Verify job
  participant T as install-tools.sh
  participant V as verify.sh
  G->>P: pull request, or push to main
  P->>P: install Terraform 1.17.0
  P->>T: run
  T-->>P: tflint 0.65.0, trivy 0.76.1, terraform-docs 0.24.0
  P->>V: run (all modules)
  loop each module with .tf files
    V->>V: init, validate, tflint
    V->>V: trivy HIGH and CRITICAL
    V->>V: terraform-docs check (if README.md)
    V->>V: terraform test (if tests/)
  end
  V-->>P: "All checks passed." or exit 1
  P-->>G: check result on the PR
```

## Use case 3: the weekly security scan

![Use case 3](scripts-uc3-weekly-scan.png)

```mermaid
flowchart LR
  s(["Monday schedule"]) --> t["install-tools.sh"] --> l["trivy-scan.sh LOW"]
  l -- "No findings." --> ok["green"]
  l -- "Findings in: modules/x" --> red["red run: fix it, or record a<br/>reviewed MEDIUM/LOW acceptance"]
```

A pull request is checked at HIGH and above. This scan uses the latest Trivy rules at
LOW and above, so it catches new rules that arrive between changes.

## Use case 4: releasing a module

![Use case 4](scripts-uc4-release.png)

```mermaid
sequenceDiagram
  actor O as Owner
  participant G as Git host
  participant R as release-check.sh
  participant V as verify.sh
  participant S as trivy-scan.sh
  O->>G: git tag aks/v1.0.0 and push it
  G->>R: RELEASE_TAG=aks/v1.0.0
  R->>R: tag looks like module/vX.Y.Z?
  R->>R: modules/aks exists?
  R->>G: fetch tags and main
  R->>R: tagged commit is on main?
  R->>V: verify.sh aks
  R->>S: trivy-scan.sh MEDIUM aks
  R->>R: write release-notes.md<br/>(commits since the previous aks tag)
  R-->>G: pass or fail
```

Only the owner creates tags. The script reads the repo and never creates, moves or
deletes a tag.

## Use case 5: the monthly azurerm update check

![Use case 5](scripts-uc5-azurerm-check.png)

### On GitLab, Azure Pipelines and Jenkins

```mermaid
flowchart LR
  m(["Monthly schedule"]) --> i["install-terraform.sh 1.17.0"]
  i --> c["check-registry.py gitlab / azure<br/>(Jenkins: no tracker)"]
  c --> q{"latest azurerm =<br/>.azurerm-reviewed-version?"}
  q -- yes --> close["close the azurerm-update issue"]
  q -- no --> rep["write azurerm-report.md<br/>validate every module<br/>open or update the issue"]
  rep -. "Jenkins" .-> unstable["report only,<br/>build marked unstable"]
```

### On GitHub Actions, with the AI agent

Three jobs, each with only the access it needs.

```mermaid
sequenceDiagram
  participant C as check job<br/>(read, issues)
  participant A as propose job<br/>(read only, model key)
  participant P as publish job<br/>(write, no AI)
  participant GH as GitHub
  C->>C: check-registry.py github
  C->>GH: open or update the issue
  C->>GH: does a bot/azurerm-X.Y.Z PR exist?
  alt new version and no PR yet
    C->>A: report, release notes, affected resources
    A->>A: install-tools.sh
    A->>A: verify.sh > verify-baseline.txt
    A->>A: ai-agent/main.py edits modules/
    A->>A: verify.sh > verify-final.txt
    A->>A: git diff > agent-patch.diff
    A->>P: patch, pr-body.md, both Verify logs
    P->>P: publish-bot-pr.sh
    P->>P: check-bot-patch.sh (only regular text files under modules/)
    P->>GH: push bot/azurerm-X.Y.Z (one commit)
    P->>GH: open a draft PR
    GH->>GH: the PR's own Verify runs (use case 2)
  else PR already exists, or versions match
    C-->>C: stop
  end
```

The agent never gets write access, and the job that writes never runs AI or code from
the patch. A person reviews the draft PR and decides whether to merge it.

## Script reference

| Script | Usage | What it does | Fails when | Called by |
|---|---|---|---|---|
| `install-tools.sh` | `sh scripts/install-tools.sh` | Downloads pinned tflint, trivy and terraform-docs into `.tools/bin`. POSIX sh and wget only, so it runs in the `hashicorp/terraform` image | A download fails | Developers; Verify, weekly scan, release and agent jobs on all platforms |
| `install-terraform.sh` | `sh scripts/install-terraform.sh 1.17.0` | Downloads one Terraform version into `.tools/bin`, for jobs with python3 but no Terraform | A download fails | Monthly check on GitLab, Azure Pipelines and Jenkins |
| `verify.sh` | `sh scripts/verify.sh [module]` | For each module: `fmt`, `init`, `validate`, `tflint`, Trivy HIGH+, terraform-docs check, `terraform test`. With a module name, checks only that one and skips Trivy | Any check fails; all failures are listed at the end | Developers; every PR and push to main; `release-check.sh`; the agent job, before and after the agent |
| `trivy-scan.sh` | `sh scripts/trivy-scan.sh <LOW\|MEDIUM\|HIGH\|CRITICAL> [module]` | Trivy at that severity and above, using `.trivyignore` | Any finding at or above the severity | Weekly scan (`LOW`); `release-check.sh` (`MEDIUM`); developers before tagging |
| `release-check.sh` | `RELEASE_TAG=aks/v1.0.0 sh scripts/release-check.sh` | Checks the tag format, that the module exists and that the tag is on main, runs `verify.sh` and `trivy-scan.sh MEDIUM` for that module, then writes `release-notes.md` | Bad tag, missing module, tag not on main, or a failing check | Release pipeline on a pushed `*/v*` tag |
| `check-registry.py` | `python3 scripts/check-registry.py [github\|gitlab\|azure]` | Compares `.azurerm-reviewed-version` with the registry, writes `azurerm-report.md`, release notes and `azurerm-affected.json`, validates every module, and opens, updates or closes one `azurerm-update` issue | Network or API error, or a module no longer validates | Monthly check on all four platforms |
| `check-bot-patch.sh` | `sh scripts/check-bot-patch.sh <patch>` | Gate on the agent's patch: only regular text files under `modules/`; no symlinks, binaries, renames, mode changes or hidden paths. Never applies the patch. An empty patch passes | The patch breaks any of those rules or git can't read it | `publish-bot-pr.sh`; developers testing a patch |
| `publish-bot-pr.sh` | `sh scripts/publish-bot-pr.sh <version> <dir>` | Requires `pr-body.md`, gates and applies the patch, bumps `.azurerm-reviewed-version`, pushes `bot/azurerm-<version>` and opens a draft PR with both Verify summaries | No `pr-body.md` or patch, a rejected patch, or a push or PR error | GitHub `check-registry.yml` publish job only |

Every platform pins Terraform 1.17.0. Tool versions are pinned in `install-tools.sh`.
