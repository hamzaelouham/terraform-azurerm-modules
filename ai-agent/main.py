#!/usr/bin/env python3
"""Usage: python ai-agent/main.py <reviewed-version> <new-version> <true|false: major bump>

Proposes the module changes a new azurerm version needs, one agent session per affected
module, as listed in azurerm-affected.json. Exits 0 only after writing pr-body.md; on any
error or limit it exits 1 and leaves no pr-body.md.
"""
import json
import os
import re
import sys
from pathlib import Path

from langchain_core.messages import HumanMessage, SystemMessage

from graph import build_graph
from models import get_model
from tools import Toolbox

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
DEFAULT_MAX_STEPS = 60
DEFAULT_MAX_TOKENS = 400000


def build_messages(reviewed, latest, major_bump, module, info):
    # Release-note text is third-party; a fence in it mustn't end the block early.
    changes = "\n".join(f"- {line}" for line in info["changes"]).replace("```", "'''") or "None."
    prompt = (HERE / "prompts" / "upgrade.md").read_text()
    for key, value in {"{reviewed}": reviewed, "{latest}": latest, "{module}": module,
                       "{resources}": ", ".join(info["resources"]) or "none",
                       "{validates}": "validates" if info["validates"] else "no longer validates",
                       "{changes}": changes}.items():
        prompt = prompt.replace(key, value)
    if major_bump:
        major = int(latest.split(".")[0])
        guide = (HERE / "prompts" / "major.md").read_text()
        prompt += "\n" + guide.replace("{major}", str(major)).replace("{next_major}", str(major + 1))
    return [SystemMessage((HERE / "instructions" / "system.md").read_text()), HumanMessage(prompt)]


def summary(reviewed, latest, affected, every_module):
    others = sorted(set(every_module) - set(affected))
    lines = [f"## Summary\n\nazurerm {reviewed} → {latest}."]
    if affected:
        lines.append(f"The agent reviewed {', '.join(affected)}, one module per session, with only that "
                     "module's release-note changes.")
    else:
        lines.append("No release note mentions a resource the modules use, and every module validates, so no "
                     "agent session ran and no module changes. This PR only records the review.")
    if others:
        lines.append(f"Not reviewed, because nothing in this release affects them: {', '.join(others)}.")
    return " ".join(lines)


def run(reviewed, latest, major_bump, model=None, root=ROOT):
    """Returns the exit code. A model can be passed in so tests don't need a network."""
    root = Path(root)
    body = root / "pr-body.md"
    body.unlink(missing_ok=True)
    try:
        affected = json.loads((root / "azurerm-affected.json").read_text())["modules"]
        every_module = sorted(p.name for p in (root / "modules").iterdir() if p.is_dir() and any(p.glob("*.tf")))
        budget = int(os.environ.get("AI_AGENT_MAX_TOKENS") or DEFAULT_MAX_TOKENS)
        steps = int(os.environ.get("AI_AGENT_MAX_STEPS") or DEFAULT_MAX_STEPS)
        sections, used = [], 0
        if affected:
            model = model or get_model()
        for module, info in affected.items():
            toolbox = Toolbox(root, module)
            # One budget for the whole run: each session gets only what the earlier ones left.
            graph = build_graph(model, toolbox, budget - used)
            result = graph.invoke({"messages": build_messages(reviewed, latest, major_bump, module, info), "tokens": 0},
                                  {"recursion_limit": steps})
            if not toolbox.finished:
                raise RuntimeError(f"The {module} session stopped without writing its section.")
            used += result["tokens"]
            sections.append(f"## {module}\n\n{toolbox.section.strip()}")
            print(f"{module}: done after {toolbox.verify_runs} Verify runs, {result['tokens']} tokens.")
        body.write_text("\n\n".join([summary(reviewed, latest, list(affected), every_module)] + sections) + "\n")
    except Exception as error:  # any failure means no PR, and the next monthly run tries again
        print(f"Agent failed: {type(error).__name__}: {error}", file=sys.stderr)
        body.unlink(missing_ok=True)
        return 1
    print(f"Agent finished: {len(affected)} module sessions, {used} tokens.")
    return 0


def main():
    args = sys.argv[1:]
    if (len(args) != 3 or args[2] not in ("true", "false")
            or not all(re.fullmatch(r"\d+\.\d+\.\d+", v) for v in args[:2])):
        sys.exit(__doc__)
    sys.exit(run(args[0], args[1], args[2] == "true"))


if __name__ == "__main__":
    main()
