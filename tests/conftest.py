"""Run the shell scripts against stub commands, so the tests need no Mac, router or network."""
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
BASH = shutil.which("bash")


class Stubs:
    def __init__(self, tmp_path):
        self.bin = tmp_path / "bin"
        self.bin.mkdir()
        self.log = tmp_path / "calls.log"
        self.log.touch()
        self.cwd = tmp_path

    def add(self, name, body="exit 0"):
        """A fake command that logs its arguments, then runs `body` (bash)."""
        path = self.bin / name
        path.write_text(f'#!/usr/bin/env bash\necho "{name} $*" >> "{self.log}"\n{body}\n')
        path.chmod(0o755)
        return path

    def calls(self):
        return self.log.read_text().splitlines()

    def run(self, script, *args, env=None, stdin=""):
        full_env = {"PATH": f"{self.bin}:/usr/bin:/bin", "HOME": str(self.cwd)}
        full_env.update(env or {})
        return subprocess.run(
            [BASH, str(ROOT / script), *args],
            cwd=self.cwd, env=full_env, input=stdin, capture_output=True, text=True, timeout=30,
        )


@pytest.fixture
def stubs(tmp_path):
    return Stubs(tmp_path)
