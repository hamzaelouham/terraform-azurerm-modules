#!/usr/bin/env python3
"""Usage: python3 scripts/check-registry.py [github|gitlab|azure]

Compares .azurerm-reviewed-version with the latest azurerm release. When they differ,
writes azurerm-report.md and opens or updates one issue on the named tracker. When they
match, closes that issue. With no tracker it only writes the report (Jenkins, local runs).

Standard library only, so it needs nothing but python3 and terraform on the runner.
Exits 1 on any error, or when a module no longer validates.
"""
import base64
import glob
import http.client
import json
import os
import re
import subprocess
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request

LABEL = "azurerm-update"
REGISTRY_URL = "https://registry.terraform.io/v1/providers/hashicorp/azurerm"
RELEASES_URL = "https://api.github.com/repos/hashicorp/terraform-provider-azurerm/releases"
GUIDE_URL = ("https://raw.githubusercontent.com/hashicorp/terraform-provider-azurerm/v{latest}"
             "/website/docs/guides/{major}.0-upgrade-guide.html.markdown")
REPORT = "azurerm-report.md"
NOTES = "azurerm-release-notes.md"
AFFECTED = "azurerm-affected.json"


def call(method, url, headers=None, body=None, content_type="application/json"):
    data = None if body is None else json.dumps(body).encode()
    request = urllib.request.Request(url, data=data, method=method, headers=dict(headers or {}))
    if data is not None:
        request.add_header("Content-Type", content_type)
    with urllib.request.urlopen(request, timeout=60) as response:
        text = response.read().decode()
    return json.loads(text) if text else None


def env(name):
    value = os.environ.get(name, "")
    if not value:
        sys.exit(f"{name} is not set; see the pipeline file for this platform.")
    return value


class GitHub:
    def __init__(self):
        self.api = f"{env('GITHUB_API_URL')}/repos/{env('GITHUB_REPOSITORY')}"
        self.headers = {"Authorization": f"Bearer {env('GITHUB_TOKEN')}", "Accept": "application/vnd.github+json"}

    def find_open(self):
        items = call("GET", f"{self.api}/issues?state=open&labels={LABEL}", self.headers)
        return [i["number"] for i in items if "pull_request" not in i]  # this endpoint also lists PRs

    def create(self, title, body):
        try:
            call("POST", f"{self.api}/labels", self.headers,
                 {"name": LABEL, "color": "FBCA04", "description": "New azurerm version to review"})
        except urllib.error.HTTPError as e:
            if e.code != 422:  # 422: the label already exists
                raise
        call("POST", f"{self.api}/issues", self.headers, {"title": title, "body": body, "labels": [LABEL]})

    def update(self, number, title, body):
        call("PATCH", f"{self.api}/issues/{number}", self.headers, {"title": title, "body": body})

    def close(self, number, comment):
        call("POST", f"{self.api}/issues/{number}/comments", self.headers, {"body": comment})
        call("PATCH", f"{self.api}/issues/{number}", self.headers, {"state": "closed"})


class GitLab:
    def __init__(self):
        self.api = f"{env('CI_API_V4_URL')}/projects/{env('CI_PROJECT_ID')}/issues"
        self.headers = {"PRIVATE-TOKEN": env("GITLAB_TOKEN")}

    def find_open(self):
        return [i["iid"] for i in call("GET", f"{self.api}?state=opened&labels={LABEL}", self.headers)]

    def create(self, title, body):
        call("POST", self.api, self.headers, {"title": title, "description": body, "labels": LABEL})

    def update(self, iid, title, body):
        call("PUT", f"{self.api}/{iid}", self.headers, {"title": title, "description": body})

    def close(self, iid, comment):
        call("POST", f"{self.api}/{iid}/notes", self.headers, {"body": comment})
        call("PUT", f"{self.api}/{iid}", self.headers, {"state_event": "close"})


class Azure:
    # Task exists in all four default processes; only its state names differ between them.
    TYPE = "Task"
    PATCH = "application/json-patch+json"

    def __init__(self):
        project = urllib.parse.quote(env("SYSTEM_TEAMPROJECT"))
        self.api = f"{env('SYSTEM_COLLECTIONURI')}{project}/_apis/wit"
        self.headers = {"Authorization": f"Bearer {env('SYSTEM_ACCESSTOKEN')}"}

    def states(self, *categories):
        states = call("GET", f"{self.api}/workitemtypes/{self.TYPE}/states?api-version=7.1", self.headers)["value"]
        return [s["name"] for s in states if s["category"] in categories]

    def find_open(self):
        finished = ", ".join("'" + s.replace("'", "''") + "'" for s in self.states("Completed", "Removed"))
        query = ("SELECT [System.Id] FROM workitems WHERE [System.TeamProject] = @project "
                 f"AND [System.Tags] CONTAINS '{LABEL}' AND [System.State] NOT IN ({finished})")
        result = call("POST", f"{self.api}/wiql?api-version=7.1", self.headers, {"query": query})
        return [i["id"] for i in result["workItems"]]

    def patch(self, method, url, fields):
        ops = [{"op": "add", "path": f"/fields/{k}", "value": v} for k, v in fields.items()]
        if "System.Description" in fields:  # large text fields default to HTML
            ops.append({"op": "add", "path": "/multilineFieldsFormat/System.Description", "value": "Markdown"})
        call(method, f"{url}?api-version=7.1", self.headers, ops, self.PATCH)

    def create(self, title, body):
        self.patch("POST", f"{self.api}/workitems/${self.TYPE}",
                   {"System.Title": title, "System.Description": body, "System.Tags": LABEL})

    def update(self, item, title, body):
        self.patch("PATCH", f"{self.api}/workitems/{item}", {"System.Title": title, "System.Description": body})

    def close(self, item, comment):
        self.patch("PATCH", f"{self.api}/workitems/{item}",
                   {"System.State": self.states("Completed")[0], "System.History": comment})


TRACKERS = {"github": GitHub, "gitlab": GitLab, "azure": Azure}


def ver(s):
    return tuple(int(x) for x in re.findall(r"\d+", s)[:3])


def fetch_releases(reviewed):
    """Published releases newer than reviewed. Pages run newest first, so stop at the first old page."""
    headers = {"Accept": "application/vnd.github+json"}
    # Optional off GitHub: anonymous calls can hit rate limits on shared runners.
    if os.environ.get("GITHUB_TOKEN"):
        headers["Authorization"] = f"Bearer {os.environ['GITHUB_TOKEN']}"
    releases, page = [], 1
    while True:
        batch = call("GET", f"{RELEASES_URL}?per_page=100&page={page}", headers)
        if not batch:
            return releases
        releases += [r for r in batch if not r["draft"] and not r["prerelease"]]
        if all(ver(r["tag_name"]) <= reviewed for r in batch):
            return releases
        page += 1


def write_release_notes(reviewed_text, latest_text, releases):
    """Saves the notes and any upgrade guides for the agent. Returns the major versions with no guide."""
    reviewed, latest = ver(reviewed_text), ver(latest_text)
    new = sorted((r for r in releases if reviewed < ver(r["tag_name"]) <= latest), key=lambda r: ver(r["tag_name"]))
    parts = [f"# {r['tag_name']}\n\n{r['body'] or ''}" for r in new]
    missing = []
    for major in range(reviewed[0] + 1, latest[0] + 1):
        url = GUIDE_URL.format(latest=latest_text, major=major)
        try:
            with urllib.request.urlopen(url, timeout=60) as response:
                parts.append(f"# Upgrade guide for azurerm {major}.0\n\n{response.read().decode()}")
        # Any failure, including a timeout or a cut-off reply, counts as no guide, so the
        # report is still published.
        except (OSError, http.client.HTTPException, UnicodeDecodeError):
            missing.append(major)
    with open(NOTES, "w") as f:
        f.write("\n\n".join(parts) + "\n")
    return missing


def write_outputs(reviewed_text, latest_text, major_bump):
    """Tells later GitHub Actions jobs that the agent should run."""
    if os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a") as f:
            f.write(f"reviewed={reviewed_text}\nnew_version={latest_text}\nmajor_bump={str(major_bump).lower()}\n")


def module_resources():
    """The azurerm resource and data source types each module uses."""
    found = {}
    for module in sorted(glob.glob("modules/*/")):
        name = os.path.basename(module.rstrip("/"))
        found[name] = set()
        for f in glob.glob(f"{module}**/*.tf", recursive=True):
            with open(f) as source:
                found[name] |= set(re.findall(r'^\s*(?:resource|data)\s+"(azurerm_[a-z0-9_]+)"', source.read(), re.M))
    return found


def write_affected(resources, ours, statuses, major_bump):
    """Which modules the agent looks at, so each of its sessions sees one module and only its changes.

    A module is affected when a release note names one of its resources, when it no longer
    validates, or, on a new major version, when it uses azurerm at all.
    """
    affected = {}
    for name, types in resources.items():
        changes = [line for t in sorted(types) for line in ours.get(t, [])]
        validates = statuses.get(name, True)
        if changes or not validates or (major_bump and types):
            affected[name] = {"resources": sorted(types), "changes": changes, "validates": validates}
    with open(AFFECTED, "w") as f:
        json.dump({"major_bump": major_bump, "modules": affected}, f, indent=2)


def build_report(reviewed_text, latest_text, releases):
    """Returns the report, and the release-note lines that mention each resource type."""
    reviewed, latest = ver(reviewed_text), ver(latest_text)

    # Resource and data source types our modules use
    used = set().union(*module_resources().values())

    new = sorted((r for r in releases if reviewed < ver(r["tag_name"]) <= latest), key=lambda r: ver(r["tag_name"]))

    breaking, ours = [], {t: [] for t in sorted(used)}
    for r in new:
        section = ""
        for line in (r["body"] or "").splitlines():
            s = line.strip()
            if re.fullmatch(r"#*\s*[A-Z][A-Z &]+:?", s):  # FEATURES:, BUG FIXES:, BREAKING CHANGES:
                section = s.strip("#: ").upper()
                continue
            if not s.startswith(("*", "-")):
                continue
            text = re.sub(r"^[*-]\s*", "", s)  # the bullet only: "* **New Resource**" keeps its bold
            item = f"{text} ([{r['tag_name']}]({r['html_url']}))"
            if "BREAKING" in section:
                breaking.append(item)
            for t in used:
                if re.search(rf"\b{t}\b", s):
                    ours[t].append(f"{section.title() or 'Change'}: {item}")

    out = [f"## azurerm {reviewed_text} → {latest_text}", "",
           f"{len(new)} new releases since the last review."]
    if latest[0] > reviewed[0]:
        out += ["", f"> **New major version.** Modules allow `< {reviewed[0] + 1}.0`, so callers won't get it "
                    "until the constraint changes. Read the upgrade guide before changing it."]

    out += ["", "### Changes to resources our modules use"]
    hits = {t: lines for t, lines in ours.items() if lines}
    if hits:
        for t, lines in hits.items():
            out += ["", f"**`{t}`**"] + [f"- {x}" for x in lines]
    else:
        out += ["", "None of the new releases mention resources our modules use."]

    out += ["", "### Breaking changes (all resources)", ""]
    # Major releases list theirs in the upgrade guide, so "None" alone would mislead.
    out += [f"- {x}" for x in breaking] or ["None listed in the release notes."]
    out += ["", "### Releases", ""] + [f"- [{r['tag_name']}]({r['html_url']})" for r in new]
    out += ["", "### When reviewed",
            f"Update `.azurerm-reviewed-version` to `{latest_text}` in a change request. "
            "The next run closes this issue."]
    return "\n".join(out)[:60000], ours  # the GitHub issue body limit is 65,536


def validate_modules():
    """Returns the report's table, whether every module validated, and each module's result."""
    lines = ["", "### Validation with the newest allowed azurerm", "",
             "| Module | azurerm used | validate |", "|---|---|---|"]
    ok = True
    statuses = {}
    cache = os.path.abspath(".tools/plugin-cache")
    os.makedirs(cache, exist_ok=True)
    for module in sorted(glob.glob("modules/*/")):
        if not glob.glob(f"{module}*.tf"):  # same skip as verify.sh: no code yet
            continue
        with tempfile.TemporaryDirectory() as data_dir:
            run_env = {**os.environ, "TF_DATA_DIR": data_dir, "TF_PLUGIN_CACHE_DIR": cache,
                       "TF_PLUGIN_CACHE_MAY_BREAK_DEPENDENCY_LOCK_FILE": "true"}

            def terraform(*args):
                return subprocess.run(["terraform", f"-chdir={module}", *args], env=run_env,
                                      capture_output=True, text=True)

            passed = (terraform("init", "-backend=false", "-upgrade", "-input=false").returncode == 0
                      and terraform("validate", "-no-color").returncode == 0)
            ok = ok and passed
            statuses[os.path.basename(module.rstrip("/"))] = passed
            selections = json.loads(terraform("version", "-json").stdout or "{}").get("provider_selections", {})
            used = selections.get("registry.terraform.io/hashicorp/azurerm", "-")
        lines.append(f"| {os.path.basename(module.rstrip('/'))} | {used} | {'pass' if passed else 'FAIL'} |")
    return "\n".join(lines), ok, statuses


def main():
    os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
    os.environ["PATH"] = f"{os.path.abspath('.tools/bin')}{os.pathsep}{os.environ['PATH']}"
    for stale in (REPORT, NOTES, AFFECTED):
        if os.path.exists(stale):
            os.remove(stale)

    names = sys.argv[1:]
    if len(names) > 1 or (names and names[0] not in TRACKERS):
        sys.exit(__doc__)
    tracker = TRACKERS[names[0]]() if names else None  # before any work: a missing token fails fast

    with open(".azurerm-reviewed-version") as f:
        reviewed = f.read().strip()
    latest = call("GET", REGISTRY_URL).get("version", "")
    # Without this, a bad registry answer would overwrite the open issue with an empty report.
    if not re.fullmatch(r"\d+\.\d+\.\d+", latest):
        sys.exit(f"Registry returned no usable version: {latest!r}")
    print(f"Reviewed: {reviewed}   Latest: {latest}")

    if reviewed == latest:
        for item in tracker.find_open() if tracker else []:
            tracker.close(item, f"azurerm {latest} has been reviewed. Closing.")
            print(f"Closed {item}.")
        return

    releases = fetch_releases(ver(reviewed))
    missing_guides = write_release_notes(reviewed, latest, releases)
    report, ours = build_report(reviewed, latest, releases)
    table, valid, statuses = validate_modules()
    write_affected(module_resources(), ours, statuses, ver(latest)[0] > ver(reviewed)[0])
    report += "\n" + table + "\n"
    with open(REPORT, "w") as f:
        f.write(report)
    print(report)

    if tracker:
        title = f"azurerm {reviewed} → {latest}: review provider changes"
        items = tracker.find_open()
        if items:
            tracker.update(items[0], title, report)
            print(f"Updated {items[0]}.")
        else:
            tracker.create(title, report)
            print("Opened an issue.")

    # Written after publishing and before any exit: a module that no longer validates
    # is exactly what the agent is for, but it never runs on a major without its guide.
    # Only GitHub runs the agent; the other platforms keep the report-only check.
    if missing_guides and os.environ.get("GITHUB_OUTPUT"):
        sys.exit(f"No upgrade guide found for azurerm {missing_guides}; the agent won't run.")
    write_outputs(reviewed, latest, ver(latest)[0] > ver(reviewed)[0])

    if not valid:
        sys.exit("A module no longer validates; see the table above.")


if __name__ == "__main__":
    try:
        main()
    except urllib.error.HTTPError as e:
        sys.exit(f"{e.url} failed: {e.code} {e.read().decode()[:500]}")
    except urllib.error.URLError as e:
        sys.exit(f"Network error: {e.reason}")
    except TimeoutError as e:  # a read timeout isn't wrapped in URLError
        sys.exit(f"Network error: {e}")
