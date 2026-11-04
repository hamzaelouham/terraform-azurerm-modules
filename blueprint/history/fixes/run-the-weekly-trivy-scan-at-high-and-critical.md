# Fix: Run the weekly Trivy scan at HIGH and CRITICAL

**Type:** Fix
**Status:** verified
**Branch:** fix/run-the-weekly-trivy-scan-at-high-and-critical

## The problem

The user asked for the weekly security scan to run at HIGH and CRITICAL. Today all
four platforms run `sh scripts/trivy-scan.sh LOW` on the weekly schedule:

- `.github/workflows/ci.yml:35` (`weekly-scan` job)
- `.azure-pipelines/ci.yml:44` (`weekly_scan` job)
- `.gitlab-ci.yml:30` (`weekly-scan` job)
- `Jenkinsfile:112` ("Weekly scan" stage)

At LOW the scan fails every week, on findings that are below the release gate:
`aks`, `storage-account` and `virtual-machine` all have LOW or MEDIUM findings, such
as AZU-0066 and AZU-0067 on `aks`. A scan that is always red stops being read.
Checked on 2026-11-04: `trivy config --severity HIGH,CRITICAL modules` exits 0.

## The fix

- In all four pipeline files, change the weekly scan to
  `sh scripts/trivy-scan.sh HIGH`, which scans HIGH and CRITICAL. Keep the jobs,
  schedules and tool install steps as they are.
- `AGENTS.md`, Commands, the "Trivy at a severity and above" note: the weekly
  schedule runs `HIGH`; before tagging, run `MEDIUM`.
- `docs/scripts.md`:
  - Use case 3: the Mermaid diagram, the text and the reference table say `HIGH`
    in place of `LOW`.
  - The text should explain the purpose: Verify on each PR also scans HIGH and
    above, while the weekly run picks up new HIGH and CRITICAL rules between
    changes. MEDIUM is checked before each release.
- Regenerate `docs/scripts-uc3-weekly-scan.png` and `docs/scripts-overview.png`
  with the existing generator, so the pictures match the text.
- No change to `scripts/trivy-scan.sh`, `verify.sh`, `release-check.sh` or
  `.trivyignore`. The release gate stays MEDIUM.

Must not break: four-platform parity, the release check's MEDIUM scan, Verify, or
the weekly scan's existing triggers (GitHub and Azure schedules, the GitLab
pipeline schedule, the Jenkins timer).

Trade-off: LOW and MEDIUM findings no longer show up weekly. MEDIUM is still
enforced by the release check before every tag. LOW is no longer checked by any
automatic job. The rule for HIGH and CRITICAL (fix, never ignore) is unchanged.

## Build steps

- [x] 1. **Switch the weekly scan to HIGH on all four platforms and update the docs.**
  - The four pipeline files.
  - The `AGENTS.md` Commands note.
  - The `docs/scripts.md` text, Mermaid diagram and table.
  - The two regenerated PNGs.

  **Done when:**
  - `grep -rn "trivy-scan.sh" .github .azure-pipelines .gitlab-ci.yml Jenkinsfile`
    shows `HIGH` for every weekly scan and `MEDIUM` only in release checks.
  - The YAML files parse.
  - `sh scripts/trivy-scan.sh HIGH` prints `No findings.`
  - `sh scripts/verify.sh` prints `All checks passed.`

## Verify

- `sh scripts/trivy-scan.sh HIGH`: `No findings.`, so the weekly scan would be green
  today.
- `sh scripts/trivy-scan.sh MEDIUM aks`: `No findings.` The release gate is
  unchanged.
- After merging, a manual run of the GitHub weekly job isn't possible, because its
  only trigger is the schedule. The next Monday 06:00 UTC run shows the result in
  Actions.

## Notes for the AI

- CI files are Claude's to write, with four-platform parity. No `modules/` code
  changes in this fix.
- The PNG generator lives in this session's scratchpad (`svg/gen.py` and
  `render.sh`). Change only the use case 3 and overview text that says LOW.
- Out of scope:
  - Adding a `workflow_dispatch` trigger.
  - Changing which findings are accepted.
  - Fixing the existing LOW and MEDIUM findings.


<!-- blueprint:completion {"schemaVersion":2,"specBytes":3572,"specSha256":"a9142cc8f81f860254e89a019cb0364774e27dd8422feb6b253ea998d8faab39","branch":"refs/heads/fix/run-the-weekly-trivy-scan-at-high-and-critical","head":"205c3eb1d2666c176e5dec31dbf555089769706e","baseRef":"refs/heads/main","baseCommit":"205c3eb1d2666c176e5dec31dbf555089769706e","sourceTree":"30caca5df553acf54b69997edca0295133096d3f","landing":"local-merge","absentOptional":[]} -->

## Try it now

1. Run `sh scripts/trivy-scan.sh HIGH`. Expect `No findings.`
2. Run `grep -rn "trivy-scan.sh" .github .azure-pipelines .gitlab-ci.yml Jenkinsfile`.
   Expect `HIGH` on all four lines.
