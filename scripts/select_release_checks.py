"""Skip only known credential changes; uncertain history or edited build logic must build."""

import hashlib
import os
import subprocess
import sys
from pathlib import Path

SAFE = {
    "docs/release-credential-transport.md",
    "scripts/tests/test_release_scope.py",
    "scripts/macos_ci_credentials.py",
    ".github/workflows/credential-transport.yml",
    "scripts/tests/test_release_credentials.py",
    "scripts/select_release_checks.py",
    "tests/manual/test_macos_keychain_transport.py",
}
# Only the reviewed credential-fix workflow bytes may skip packaging. Future workflow edits build.
REVIEWED_WORKFLOWS = {
    ".github/workflows/build.yml": "daf1e0b2dc8254877fd4413c62dbafa638bfdd4d8064f892d4fbd714d71cb696"
}


def needs_package(paths):
    if not paths:
        return True
    for path in paths:
        if path in SAFE:
            continue
        expected = REVIEWED_WORKFLOWS.get(path)
        if expected and hashlib.sha256(Path(path).read_bytes()).hexdigest() == expected:
            continue
        return True
    return False


def select_package():
    before = os.environ.get("BEFORE", "")
    if (
        os.environ.get("GITHUB_EVENT_NAME") != "push"
        or os.environ.get("GITHUB_REF", "").startswith("refs/tags/")
        or not before
        or set(before) == {"0"}
    ):
        return True
    try:
        paths = subprocess.check_output(
            ["git", "diff", "--name-only", before, "HEAD"],
            text=True,
            stderr=subprocess.DEVNULL,
        ).splitlines()
        return needs_package(paths)
    except (subprocess.CalledProcessError, OSError):
        print(
            "Unable to classify changed paths; packaging remains enabled",
            file=sys.stderr,
        )
        return True


if __name__ == "__main__":
    print("package=" + str(select_package()).lower())
