"""The only actions the agent can take. There is no shell and no web access.

These checks are the security boundary, because the release notes the agent reads are
third-party text. They're enforced here rather than in the prompt, and a refusal goes
back to the model as an ordinary tool result. scripts/check-bot-patch.sh checks the
result again, without AI, before anything reaches the repo.

Each session works on one module, so it can only see and change that module.
"""
import functools
import os
import re
import subprocess
from pathlib import Path

from langchain_core.tools import StructuredTool

INPUT_FILES = ("azurerm-report.md", "azurerm-release-notes.md", "verify-baseline.txt")
WRITABLE_SUFFIXES = (".tf", ".hcl", ".md")
MAX_VERIFY_RUNS = 3
# Every tool result stays in the conversation and is paid for again on each later call.
READ_LINES = 200
READ_CHARS = 12000
SEARCH_RESULTS = 50
SEARCH_LINE_CHARS = 200
VERIFY_OUTPUT_CHARS = 6000
VERIFY_TIMEOUT_SECONDS = 900


class Refused(Exception):
    pass


def compact_verify_output(text):
    """Drops successful init output, which is long and says nothing, and keeps the end."""
    kept, block = [], []

    def flush():
        if block and block[0].endswith((": init", "tflint plugins")) and "Error" not in "\n".join(block):
            kept.append(f"{block[0]}: ok")
        else:
            kept.extend(block)

    for line in text.splitlines():
        if line.startswith("--- "):
            flush()
            block = [line]
        else:
            block.append(line)
    flush()
    compact = "\n".join(line for line in kept if line.strip())
    if len(compact) > VERIFY_OUTPUT_CHARS:
        compact = "[earlier output cut]\n" + compact[-VERIFY_OUTPUT_CHARS:]
    return compact


class Toolbox:
    def __init__(self, root, module):
        self.root = Path(root).resolve()
        self.module = module
        self.module_dir = self.root / "modules" / module
        if not re.fullmatch(r"[a-z0-9-]+", module) or not self.module_dir.is_dir() or self.module_dir.is_symlink():
            raise ValueError(f"{module} isn't a module.")
        self.verify_runs = 0
        self.finished = False
        self.section = ""
        self.tools = [
            self._tool(self.list_files),
            self._tool(self.read_file),
            self._tool(self.search_files),
            self._tool(self.write_file),
            self._tool(self.run_verify),
            self._tool(self.write_pr_section),
        ]

    @staticmethod
    def _tool(method):
        @functools.wraps(method)
        def run(*args, **kwargs):
            try:
                return method(*args, **kwargs)
            except Refused as refused:
                return f"Refused: {refused}"

        return StructuredTool.from_function(run, name=method.__name__, description=method.__doc__)

    def _in_module(self, path):
        """The path, if it's a visible, real path inside this session's module."""
        relative = Path(path)
        if relative.is_absolute() or ".." in relative.parts:
            raise Refused(f"{path} isn't a relative path inside the repo.")
        if relative.parts[:2] != ("modules", self.module) or len(relative.parts) < 3:
            raise Refused(f"{path} is outside modules/{self.module}/, the only module in this session.")
        if any(part.startswith(".") for part in relative.parts):
            raise Refused(f"{path} is a hidden path.")
        current = self.root
        for part in relative.parts:
            current = current / part
            if current.is_symlink():
                raise Refused(f"{path} goes through a symlink.")
        return self.root / relative

    def _readable(self, path):
        if path in INPUT_FILES:
            target = self.root / path
            if target.is_symlink():
                raise Refused(f"{path} is a symlink.")
            return target
        return self._in_module(path)

    def _module_files(self):
        found = []
        for directory, folders, files in os.walk(self.module_dir, followlinks=False):
            folders[:] = sorted(f for f in folders if not f.startswith("."))
            for name in sorted(files):
                path = Path(directory) / name
                if not name.startswith(".") and not path.is_symlink():
                    found.append(path.relative_to(self.root).as_posix())
        return found

    def list_files(self) -> str:
        """List the input files and every file in this session's module."""
        inputs = [name for name in INPUT_FILES if (self.root / name).is_file()]
        return "\n".join(inputs + self._module_files())

    def read_file(self, path: str, start_line: int = 1) -> str:
        """Read an input file or a file in this module, from a 1-based line. Long files arrive in parts."""
        target = self._readable(path)
        if not target.is_file():
            raise Refused(f"{path} doesn't exist.")
        lines = target.read_text(errors="replace").splitlines()
        first = max(start_line, 1) - 1
        taken, size = [], 0
        for line in lines[first:first + READ_LINES]:
            if size + len(line) > READ_CHARS and taken:
                break
            taken.append(line)
            size += len(line) + 1
        text = "\n".join(taken)
        end = first + len(taken)
        if end < len(lines):
            text += f"\n[{len(lines)} lines in total; continue with start_line={end + 1}]"
        return text

    def search_files(self, text: str) -> str:
        """Find literal text in the input files and this module. Returns path:line: matching line. Search before reading long files."""
        if not text:
            raise Refused("Search text can't be empty.")
        results = []
        for name in [n for n in INPUT_FILES if (self.root / n).is_file()] + self._module_files():
            content = (self.root / name).read_text(errors="replace")
            for number, line in enumerate(content.splitlines(), 1):
                if text in line:
                    results.append(f"{name}:{number}: {line[:SEARCH_LINE_CHARS]}")
                    if len(results) == SEARCH_RESULTS:
                        return "\n".join(results) + "\n[more results not shown; search for something more specific]"
        return "\n".join(results) or "No matches."

    def write_file(self, path: str, content: str) -> str:
        """Create or replace a .tf, .hcl or .md file in this module with the full new content."""
        target = self._in_module(path)
        if target.suffix not in WRITABLE_SUFFIXES:
            raise Refused(f"Only {', '.join(WRITABLE_SUFFIXES)} files can be written.")
        if target.is_dir():
            raise Refused(f"{path} is a folder.")
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content)
        return f"Wrote {path}."

    def run_verify(self) -> str:
        """Run the checks for this module: sh scripts/verify.sh <module>. Allowed 3 times, so use them well."""
        if self.verify_runs >= MAX_VERIFY_RUNS:
            raise Refused(f"Verify has run {MAX_VERIFY_RUNS} times. Finish with write_pr_section and list what still fails.")
        self.verify_runs += 1
        # The checks run code from the module, so they don't get the model's settings.
        environment = {k: v for k, v in os.environ.items() if not k.startswith(("OPENAI_", "AI_AGENT_"))}
        try:
            result = subprocess.run(["sh", "scripts/verify.sh", self.module], cwd=self.root, env=environment,
                                    stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                    text=True, errors="replace", timeout=VERIFY_TIMEOUT_SECONDS)
        except subprocess.TimeoutExpired:
            return f"Verify timed out after {VERIFY_TIMEOUT_SECONDS} seconds."
        return f"Exit code {result.returncode}.\n{compact_verify_output(result.stdout)}"

    def write_pr_section(self, text: str) -> str:
        """Write this module's part of the pull request description. This ends the session, so do it last."""
        if not text.strip():
            raise Refused("The section can't be empty.")
        self.section = text
        self.finished = True
        return "Saved this module's section."
