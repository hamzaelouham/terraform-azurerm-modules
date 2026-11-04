import json
import sys
from pathlib import Path

import pytest

# ai-agent has a hyphen, so it's a folder of scripts rather than an importable package.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))


@pytest.fixture
def repo(tmp_path):
    """A small repo layout: two modules, the input files, and files the agent must not reach."""
    for module in ("vnet", "key-vault"):
        (tmp_path / "modules" / module).mkdir(parents=True)
        (tmp_path / "modules" / module / "main.tf").write_text(f'resource "azurerm_{module}" "x" {{}}\n')
    (tmp_path / "modules" / "vnet" / ".terraform").mkdir()
    (tmp_path / "modules" / "vnet" / ".terraform" / "state").write_text("hidden\n")
    (tmp_path / "scripts").mkdir()
    (tmp_path / "scripts" / "verify.sh").write_text(
        'echo "--- tflint plugins"\necho "Installing plugin"\necho "--- modules/$1: init"\necho "Initializing"\n'
        'echo "--- modules/$1: validate"\necho "ran with args: $*"\n'
        'echo "key=${OPENAI_API_KEY:-absent}"\necho "model=${AI_AGENT_MODEL:-absent}"\n'
    )
    (tmp_path / ".git").mkdir()
    (tmp_path / ".git" / "config").write_text("secret\n")
    (tmp_path / ".env").write_text("TOKEN=secret\n")
    (tmp_path / "azurerm-report.md").write_text("report\n")
    (tmp_path / "azurerm-release-notes.md").write_text("note one\nazurerm_vnet changed\n")
    (tmp_path / "verify-baseline.txt").write_text("All checks passed.\n")
    (tmp_path / "azurerm-affected.json").write_text(json.dumps({"major_bump": False, "modules": {
        "vnet": {"resources": ["azurerm_vnet"], "changes": ["Bug Fixes: `azurerm_vnet` - fixed"], "validates": True},
    }}))
    return tmp_path
