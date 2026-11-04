import pytest

from models import SettingsError, get_model
from tools import MAX_VERIFY_RUNS, READ_LINES, VERIFY_OUTPUT_CHARS, Toolbox, compact_verify_output


def call(toolbox, name, **args):
    return next(t for t in toolbox.tools if t.name == name).invoke(args)


def test_reads_its_module_and_input_files(repo):
    box = Toolbox(repo, "vnet")
    assert "azurerm_vnet" in call(box, "read_file", path="modules/vnet/main.tf")
    assert call(box, "read_file", path="azurerm-report.md") == "report"


@pytest.mark.parametrize("path", [
    ".git/config", ".env", "scripts/verify.sh", "../outside", "modules/../.env", "modules/key-vault/main.tf",
    "modules/vnet/.terraform/state", "/etc/passwd", "pr-body.md", "azurerm-affected.json", "modules/vnet",
])
def test_refuses_reads_elsewhere(repo, path):
    assert call(Toolbox(repo, "vnet"), "read_file", path=path).startswith("Refused")


def test_refuses_reading_through_a_symlink(repo):
    (repo / "modules" / "vnet" / "link.tf").symlink_to(repo / ".env")
    assert call(Toolbox(repo, "vnet"), "read_file", path="modules/vnet/link.tf").startswith("Refused")


def test_long_files_arrive_in_parts(repo):
    (repo / "azurerm-release-notes.md").write_text("\n".join(f"line {i}" for i in range(1, READ_LINES + 11)))
    box = Toolbox(repo, "vnet")
    first = call(box, "read_file", path="azurerm-release-notes.md")
    assert f"start_line={READ_LINES + 1}" in first
    assert call(box, "read_file", path="azurerm-release-notes.md", start_line=READ_LINES + 1).startswith(f"line {READ_LINES + 1}")


def test_listing_and_search_stay_in_its_module(repo):
    (repo / "modules" / "vnet" / "link.tf").symlink_to(repo / ".env")
    box = Toolbox(repo, "vnet")
    listing = call(box, "list_files")
    assert "modules/vnet/main.tf" in listing and "azurerm-report.md" in listing
    for hidden in (".env", ".terraform", "verify.sh", "link.tf", "key-vault"):
        assert hidden not in listing
    assert "azurerm-release-notes.md:2:" in call(box, "search_files", text="azurerm_vnet changed")
    assert call(box, "search_files", text="azurerm_key-vault") == "No matches."
    assert call(box, "search_files", text="secret") == "No matches."


def test_writes_in_its_module(repo):
    assert call(Toolbox(repo, "vnet"), "write_file", path="modules/vnet/new.tf", content="x\n") == "Wrote modules/vnet/new.tf."
    assert (repo / "modules" / "vnet" / "new.tf").read_text() == "x\n"


@pytest.mark.parametrize("path", [
    "scripts/verify.sh", ".github/workflows/ci.yml", ".azurerm-reviewed-version", "root.tf", "../outside.tf",
    "modules/../scripts/verify.sh", "modules/vnet/.terraform/x.tf", "modules/vnet/.terraformrc.tf",
    "modules/vnet/run.sh", "modules/vnet/noext", "/tmp/x.tf", "modules/vnet", "modules/key-vault/main.tf",
    "modules/new.tf", "modules/vnet/override.tf", "modules/vnet/x_override.tf", "modules/vnet/examples/a.tf",
])
def test_refuses_writes_elsewhere(repo, path):
    before = (repo / "modules" / "key-vault" / "main.tf").read_text()
    assert call(Toolbox(repo, "vnet"), "write_file", path=path, content="owned").startswith("Refused")
    assert (repo / "scripts" / "verify.sh").read_text().startswith('echo "--- tflint')
    assert (repo / "modules" / "key-vault" / "main.tf").read_text() == before
    assert not (repo.parent / "outside.tf").exists()


def test_refuses_writes_when_git_cant_tell_if_ignored(repo):
    (repo / ".git").rename(repo / "not-git")
    assert call(Toolbox(repo, "vnet"), "write_file", path="modules/vnet/new.tf", content="x").startswith("Refused")
    assert not (repo / "modules" / "vnet" / "new.tf").exists()


def test_refuses_writing_through_a_symlink(repo):
    (repo / "modules" / "vnet" / "evil").symlink_to(repo / "scripts", target_is_directory=True)
    (repo / "modules" / "vnet" / "link.tf").symlink_to(repo / ".env")
    box = Toolbox(repo, "vnet")
    assert call(box, "write_file", path="modules/vnet/evil/verify.tf", content="owned").startswith("Refused")
    assert call(box, "write_file", path="modules/vnet/link.tf", content="owned").startswith("Refused")
    assert not (repo / "scripts" / "verify.tf").exists()
    assert (repo / ".env").read_text() == "TOKEN=secret\n"


@pytest.mark.parametrize("module", ["nope", "../scripts", "vnet/../..", "$(id)", ""])
def test_session_needs_a_real_module(repo, module):
    with pytest.raises(ValueError):
        Toolbox(repo, module)


def test_session_refuses_a_symlinked_module(repo):
    (repo / "modules" / "sneaky").symlink_to(repo / "scripts", target_is_directory=True)
    with pytest.raises(ValueError):
        Toolbox(repo, "sneaky")


def test_verify_runs_its_module_and_stops_after_the_limit(repo):
    box = Toolbox(repo, "vnet")
    for _ in range(MAX_VERIFY_RUNS):
        assert "ran with args: vnet" in call(box, "run_verify")
    assert call(box, "run_verify").startswith("Refused")
    assert box.verify_runs == MAX_VERIFY_RUNS


def test_verify_doesnt_get_the_model_settings(repo, monkeypatch):
    monkeypatch.setenv("OPENAI_API_KEY", "sk-secret")
    monkeypatch.setenv("AI_AGENT_MODEL", "some-model")
    result = call(Toolbox(repo, "vnet"), "run_verify")
    assert "key=absent" in result and "model=absent" in result
    assert "sk-secret" not in result


def test_verify_output_drops_successful_init_and_keeps_the_end():
    output = "\n".join(["--- tflint plugins", "Installing", "--- modules/vnet: init", "Initializing", "x" * 50,
                        "--- modules/vnet: validate", "Success!"])
    compact = compact_verify_output(output)
    assert "--- modules/vnet: init: ok" in compact and "Initializing" not in compact and "Success!" in compact
    failed = compact_verify_output("--- modules/vnet: init\nError: no provider\n")
    assert "Error: no provider" in failed
    long = compact_verify_output("--- modules/vnet: test\n" + "\n".join(f"line {i}" for i in range(5000)))
    assert long.startswith("[earlier output cut]") and long.endswith("line 4999")
    assert len(long) <= VERIFY_OUTPUT_CHARS + 30


def test_section_finishes_the_session(repo):
    box = Toolbox(repo, "vnet")
    assert call(box, "write_pr_section", text="   ").startswith("Refused")
    assert not box.finished
    call(box, "write_pr_section", text="**Changes** none")
    assert box.finished and box.section == "**Changes** none"


@pytest.mark.parametrize("missing", ["AI_AGENT_MODEL", "OPENAI_API_KEY"])
def test_missing_model_settings_fail_clearly(monkeypatch, missing):
    monkeypatch.setenv("AI_AGENT_MODEL", "some-model")
    monkeypatch.setenv("OPENAI_API_KEY", "sk-test")
    monkeypatch.delenv(missing)
    with pytest.raises(SettingsError, match=missing):
        get_model()


def test_empty_base_url_means_openai(monkeypatch):
    monkeypatch.setenv("AI_AGENT_MODEL", "some-model")
    monkeypatch.setenv("OPENAI_API_KEY", "sk-test")
    monkeypatch.setenv("OPENAI_BASE_URL", "")
    assert "api.openai.com" in str(get_model().root_client.base_url)
