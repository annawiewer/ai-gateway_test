"""Synchronize upstream originals without changing either Terraform variant."""

import argparse
import base64
import json
import os
from pathlib import Path
import re
import subprocess
import sys


UPSTREAM_URL = "https://github.com/Azure/aigateway.git"
BRANCHES = ("main", "api2026gateway")
WORKFLOWS = {
    ".github/workflows/terraform-offline.yml",
    ".github/workflows/terraform-upstream-sync.yml",
}


def git(repository, *arguments, extra_env=None):
    env = dict(os.environ, GIT_TERMINAL_PROMPT="0")
    env.update(extra_env or {})
    result = subprocess.run(
        ["git", "--no-pager", "-C", str(repository), *arguments],
        capture_output=True, encoding="utf-8", env=env, timeout=300,
    )
    if result.returncode:
        raise RuntimeError(
            f"git {arguments[0]} failed: {result.stderr.strip() or result.stdout.strip()}"
        )
    return result.stdout.strip()


def protected(path):
    return (
        path == "samples/terraform"
        or path.startswith("samples/terraform/")
        or path in WORKFLOWS
    )


def tree(repository, revision):
    return {
        path: metadata
        for record in git(repository, "ls-tree", "-r", "-z", revision).split("\0")
        if record
        for metadata, path in [record.split("\t", 1)]
    }


def select(entries, terraform=False):
    return {path: value for path, value in entries.items() if protected(path) == terraform}


def check_workspace(repository, workspace):
    if repository == workspace or repository in workspace.parents or workspace in repository.parents:
        raise RuntimeError("The disposable workspace must be outside the repository.")


def save(workspace, state):
    (workspace / "state.json").write_text(json.dumps(state, indent=2) + "\n", encoding="utf-8")


def load(repository, workspace):
    check_workspace(repository, workspace)
    state = json.loads((workspace / "state.json").read_text(encoding="utf-8"))
    if (state["version"] != 1 or state["repository"] != str(repository)
            or state["workspace"] != str(workspace)):
        raise RuntimeError("Synchronization state belongs to another repository.")
    if set(state["branches"]) != set(BRANCHES):
        raise RuntimeError("Unexpected branch set in synchronization state.")
    revisions = [state["upstream"]]
    for branch in state["branches"].values():
        revisions.extend([branch["before"], branch["tip"]])
    if any(not re.fullmatch(r"[0-9a-f]{40}(?:[0-9a-f]{24})?", value) for value in revisions):
        raise RuntimeError("Invalid commit identifier in synchronization state.")
    return state


def signature(state):
    return {
        "upstream": state["upstream"],
        "branches": {name: branch["tip"] for name, branch in state["branches"].items()},
    }


def verify(repository, workspace, state):
    upstream = tree(repository, state["upstream"])
    if select(upstream, terraform=True):
        raise RuntimeError("Upstream now owns a Terraform extension path; manual review required.")
    for name, branch in state["branches"].items():
        candidate = tree(repository, branch["tip"])
        if select(candidate) != upstream:
            raise RuntimeError(f"{name}: upstream-owned files differ from upstream.")
        if select(candidate, terraform=True) != select(
            tree(repository, branch["before"]), terraform=True
        ):
            raise RuntimeError(f"{name}: synchronization changed the Terraform extension.")
        if branch["tip"] != branch["before"]:
            parents = git(repository, "show", "-s", "--format=%P", branch["tip"]).split()
            if parents != [branch["before"], state["upstream"]]:
                raise RuntimeError(f"{name}: unexpected merge parents.")
        worktree = workspace / name
        if git(worktree, "rev-parse", "HEAD") != branch["tip"] or git(
            worktree, "status", "--porcelain", "--untracked-files=all"
        ):
            raise RuntimeError(f"{name}: candidate worktree changed after preparation.")


def prepare(repository, workspace):
    check_workspace(repository, workspace)
    if git(repository, "status", "--porcelain", "--untracked-files=all"):
        raise RuntimeError("Start from a clean checkout.")
    workspace.mkdir()
    state = {
        "version": 1, "repository": str(repository), "workspace": str(workspace),
        "upstream": None, "branches": {}, "validation": None,
    }
    save(workspace, state)
    git(
        repository, "fetch", "--no-tags", "origin",
        *(f"refs/heads/{name}:refs/remotes/origin/{name}" for name in BRANCHES),
    )
    git(repository, "fetch", "--no-tags", UPSTREAM_URL, "refs/heads/main")
    upstream = git(repository, "rev-parse", "FETCH_HEAD^{commit}")
    if select(tree(repository, upstream), terraform=True):
        raise RuntimeError("Upstream now owns a Terraform extension path; manual review required.")
    state["upstream"] = upstream
    for name in BRANCHES:
        before = git(repository, "rev-parse", f"refs/remotes/origin/{name}")
        bases = git(repository, "merge-base", "--all", before, upstream).splitlines()
        if len(bases) != 1:
            raise RuntimeError(f"{name}: ambiguous upstream ancestry; manual review required.")
        if select(tree(repository, before)) != select(tree(repository, bases[0])):
            raise RuntimeError(f"{name}: fork-only changes outside Terraform; manual review required.")
        worktree = workspace / name
        git(repository, "worktree", "add", "--detach", str(worktree), before)
        if bases[0] != upstream:
            git(worktree, "merge", "--no-ff", "--no-commit", upstream)
            git(
                worktree, "-c", "user.name=github-actions[bot]",
                "-c", "user.email=41898282+github-actions[bot]@users.noreply.github.com",
                "commit", "-m", f"Sync Azure/aigateway main into {name}",
                "-m", f"Upstream-Commit: {upstream}",
            )
        state["branches"][name] = {
            "before": before, "tip": git(worktree, "rev-parse", "HEAD"),
        }
    verify(repository, workspace, state)
    save(workspace, state)
    changed = any(branch["tip"] != branch["before"] for branch in state["branches"].values())
    if os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as output:
            output.write(f"changed={str(changed).lower()}\n")
    print(f"Prepared both branches against upstream {upstream}; changes: {changed}.")
    return state


def run_checks(worktree, include_cli):
    env = dict(os.environ)
    for key in ("GH_TOKEN", "GITHUB_TOKEN", "GH_ENTERPRISE_TOKEN", "GITHUB_ENTERPRISE_TOKEN"):
        env.pop(key, None)
    env["CLI_TEST_REAL_AZ"] = "0"
    subprocess.run(
        ["pwsh", "-NoLogo", "-NoProfile", "-File",
         str(worktree / "samples" / "terraform" / "scripts" / "Test-Offline.ps1")],
        cwd=worktree, env=env, check=True, timeout=1200,
    )
    if include_cli and (worktree / "cli" / "tests").is_dir():
        subprocess.run(
            [sys.executable, "-B", "-m", "unittest", "discover",
             "-s", str(worktree / "cli" / "tests"), "-p", "test_*.py"],
            cwd=worktree, env=env, check=True, timeout=600,
        )


def validate(repository, workspace):
    state = load(repository, workspace)
    state["validation"] = None
    save(workspace, state)
    verify(repository, workspace, state)
    for name in BRANCHES:
        run_checks(workspace / name, include_cli=name == "main")
    verify(repository, workspace, state)
    state["validation"] = signature(state)
    save(workspace, state)
    print("Both Terraform variants and the upstream CLI checks passed.")


def publication_environment(repository):
    token = os.environ.get("GH_TOKEN")
    if not token:
        return {}
    origin = git(repository, "remote", "get-url", "--push", "origin")
    if not re.fullmatch(r"https://github\.com/[^/\s:]+/[^/\s:]+", origin):
        raise RuntimeError("Refusing to attach a GitHub token to a non-GitHub HTTPS origin.")
    authorization = base64.b64encode(f"x-access-token:{token}".encode()).decode()
    # Process-local Git configuration keeps credentials out of argv and repository files.
    return {
        "GIT_CONFIG_COUNT": "2",
        "GIT_CONFIG_KEY_0": "credential.helper", "GIT_CONFIG_VALUE_0": "",
        "GIT_CONFIG_KEY_1": "http.https://github.com/.extraheader",
        "GIT_CONFIG_VALUE_1": f"AUTHORIZATION: basic {authorization}",
    }


def publish(repository, workspace):
    state = load(repository, workspace)
    if state["validation"] != signature(state):
        raise RuntimeError("Publication requires successful checks for these exact candidates.")
    verify(repository, workspace, state)
    source = git(repository, "ls-remote", UPSTREAM_URL, "refs/heads/main").split()
    if not source or source[0] != state["upstream"]:
        raise RuntimeError("Upstream changed during validation; rerun synchronization.")
    env = publication_environment(repository)
    remote = {
        ref: sha
        for line in git(
            repository, "ls-remote", "--heads", "origin",
            *(f"refs/heads/{name}" for name in BRANCHES), extra_env=env,
        ).splitlines()
        for sha, ref in [line.split()]
    }
    if any(remote.get(f"refs/heads/{name}") != branch["before"]
           for name, branch in state["branches"].items()):
        raise RuntimeError("A fork branch changed during validation; rerun synchronization.")
    changed = any(branch["tip"] != branch["before"] for branch in state["branches"].values())
    arguments = ["push", "--atomic"]
    if not changed:
        arguments.append("--dry-run")
    arguments.extend(["origin", *(
        f"{branch['tip']}:refs/heads/{name}" for name, branch in state["branches"].items()
    )])
    git(repository, *arguments, extra_env=env)
    print("Published both branches atomically." if changed else "Both branches are already current.")


def cleanup(repository, workspace):
    check_workspace(repository, workspace)
    state_path = workspace / "state.json"
    if not state_path.is_file():
        return
    state = json.loads(state_path.read_text(encoding="utf-8"))
    if (state.get("version") != 1 or state.get("repository") != str(repository)
            or state.get("workspace") != str(workspace)):
        raise RuntimeError("Refusing to clean a workspace not owned by this synchronizer.")
    registered = {
        Path(record.removeprefix("worktree ")).resolve()
        for record in git(repository, "worktree", "list", "--porcelain", "-z").split("\0")
        if record.startswith("worktree ")
    }
    for name in BRANCHES:
        worktree = workspace / name
        if worktree in registered:
            git(repository, "worktree", "remove", "--force", str(worktree))


def main():
    commands = {"prepare": prepare, "validate": validate, "publish": publish, "cleanup": cleanup}
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=commands)
    parser.add_argument("--workspace", type=Path, required=True)
    arguments = parser.parse_args()
    repository = Path(git(Path.cwd(), "rev-parse", "--show-toplevel")).resolve()
    workspace = arguments.workspace.resolve()
    try:
        commands[arguments.command](repository, workspace)
    except (OSError, RuntimeError, ValueError, subprocess.SubprocessError) as error:
        print(f"Upstream synchronization stopped: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
