import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location(
    "upstream_sync", Path(__file__).parents[1] / "scripts" / "sync-upstream.py"
)
sync = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sync)


class UpstreamSyncTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="upstream-sync-tests-")
        self.addCleanup(self.temporary.cleanup)
        root = Path(self.temporary.name).resolve()
        self.upstream = root / "upstream"
        self.origin = root / "origin.git"
        self.repository = root / "fork"
        self.workspace = root / "sync"
        sync.git(root, "init", "--initial-branch=main", str(self.upstream))
        sync.git(root, "init", "--bare", "--initial-branch=main", str(self.origin))
        self.write(self.upstream, "README.md", "Upstream v1\n")
        self.commit(self.upstream)
        sync.git(root, "clone", "--no-hardlinks", str(self.upstream), str(self.repository))
        sync.git(self.repository, "remote", "set-url", "origin", str(self.origin))
        self.write(self.repository, "samples/terraform/main.tf", "legacy-2025\n")
        self.write(self.repository, ".github/workflows/terraform-offline.yml", "offline\n")
        self.write(self.repository, ".github/workflows/terraform-upstream-sync.yml", "sync\n")
        self.commit(self.repository)
        sync.git(self.repository, "switch", "-c", "api2026gateway")
        self.write(self.repository, "samples/terraform/main.tf", "separate-2026\n")
        self.commit(self.repository)
        sync.git(self.repository, "push", "origin", "main", "api2026gateway")
        sync.git(self.repository, "switch", "main")
        self.original = self.remote_heads()
        self.addCleanup(sync.cleanup, self.repository, self.workspace)
        self.source_patch = patch.object(sync, "UPSTREAM_URL", str(self.upstream))
        self.source_patch.start()
        self.addCleanup(self.source_patch.stop)
        self.environment = patch.dict(os.environ, {"GH_TOKEN": "", "GITHUB_OUTPUT": ""})
        self.environment.start()
        self.addCleanup(self.environment.stop)

    def write(self, repository, path, text):
        destination = repository / path
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(text, encoding="utf-8")

    def commit(self, repository):
        sync.git(repository, "add", "-A")
        sync.git(
            repository, "-c", "user.name=Sync fixture", "-c", "user.email=fixture@example.invalid",
            "-c", "commit.gpgsign=false", "commit", "-m", "Fixture change",
        )
        return sync.git(repository, "rev-parse", "HEAD")

    def remote_heads(self):
        return dict(
            reversed(line.split())
            for line in sync.git(self.repository, "ls-remote", "--heads", "origin").splitlines()
        )

    def advance_upstream(self):
        self.write(self.upstream, "README.md", "Upstream v2\n")
        self.write(self.upstream, "cli/new.txt", "New upstream file\n")
        return self.commit(self.upstream)

    def validated_update(self):
        self.advance_upstream()
        state = sync.prepare(self.repository, self.workspace)
        with patch.object(sync, "run_checks") as checks:
            sync.validate(self.repository, self.workspace)
        self.assertEqual(2, checks.call_count)
        return state

    def test_updates_both_branches_and_preserves_distinct_terraform(self):
        state = self.validated_update()
        for name, expected in (("main", "legacy-2025"), ("api2026gateway", "separate-2026")):
            worktree = self.workspace / name
            self.assertEqual("Upstream v2", (worktree / "README.md").read_text().strip())
            self.assertEqual(expected, (worktree / "samples/terraform/main.tf").read_text().strip())
            self.assertEqual(
                [state["branches"][name]["before"], state["upstream"]],
                sync.git(worktree, "show", "-s", "--format=%P", "HEAD").split(),
            )
        self.assertEqual(self.original, self.remote_heads())
        sync.publish(self.repository, self.workspace)
        self.assertEqual(
            {f"refs/heads/{name}": branch["tip"] for name, branch in state["branches"].items()},
            self.remote_heads(),
        )

    def test_already_current_creates_no_commits(self):
        state = sync.prepare(self.repository, self.workspace)
        self.assertTrue(all(branch["tip"] == branch["before"] for branch in state["branches"].values()))
        with patch.object(sync, "run_checks"):
            sync.validate(self.repository, self.workspace)
        sync.publish(self.repository, self.workspace)
        self.assertEqual(self.original, self.remote_heads())

    def test_stops_on_fork_edits_to_upstream_files(self):
        self.write(self.repository, "README.md", "Fork-specific change\n")
        self.commit(self.repository)
        sync.git(self.repository, "push", "origin", "main")
        self.advance_upstream()
        expected = self.remote_heads()
        with self.assertRaisesRegex(RuntimeError, "fork-only changes"):
            sync.prepare(self.repository, self.workspace)
        self.assertEqual(expected, self.remote_heads())

    def test_stops_on_new_upstream_terraform_ownership(self):
        self.write(self.upstream, "samples/terraform/upstream.tf", "New namespace collision\n")
        self.commit(self.upstream)
        with self.assertRaisesRegex(RuntimeError, "Upstream now owns"):
            sync.prepare(self.repository, self.workspace)
        self.assertEqual(self.original, self.remote_heads())

    def test_second_branch_conflict_does_not_publish_first_candidate(self):
        sync.git(self.repository, "switch", "api2026gateway")
        self.write(self.repository, "README.md", "API branch customization\n")
        self.commit(self.repository)
        sync.git(self.repository, "push", "origin", "api2026gateway")
        sync.git(self.repository, "switch", "main")
        self.advance_upstream()
        expected = self.remote_heads()
        with self.assertRaisesRegex(RuntimeError, "fork-only changes"):
            sync.prepare(self.repository, self.workspace)
        self.assertTrue((self.workspace / "main").is_dir())
        self.assertEqual(expected, self.remote_heads())

    def test_stops_on_new_upstream_workflow_ownership(self):
        self.write(self.upstream, ".github/workflows/terraform-offline.yml", "Upstream workflow\n")
        self.commit(self.upstream)
        with self.assertRaisesRegex(RuntimeError, "Upstream now owns"):
            sync.prepare(self.repository, self.workspace)

    def test_requires_checks_before_publication(self):
        self.advance_upstream()
        sync.prepare(self.repository, self.workspace)
        with self.assertRaisesRegex(RuntimeError, "requires successful checks"):
            sync.publish(self.repository, self.workspace)
        self.assertEqual(self.original, self.remote_heads())

    def test_failed_checks_invalidate_previous_success(self):
        self.validated_update()
        with patch.object(sync, "run_checks", side_effect=[None, RuntimeError("checks failed")]):
            with self.assertRaisesRegex(RuntimeError, "checks failed"):
                sync.validate(self.repository, self.workspace)
        with self.assertRaisesRegex(RuntimeError, "requires successful checks"):
            sync.publish(self.repository, self.workspace)
        self.assertEqual(self.original, self.remote_heads())

    def test_rejects_candidate_changes_after_checks(self):
        self.validated_update()
        self.write(self.workspace / "api2026gateway", "README.md", "Unvalidated edit\n")
        with self.assertRaisesRegex(RuntimeError, "worktree changed"):
            sync.publish(self.repository, self.workspace)
        self.assertEqual(self.original, self.remote_heads())

    def test_rejects_a_committed_terraform_change_in_candidate(self):
        state = self.validated_update()
        candidate = self.workspace / "api2026gateway"
        self.write(candidate, "samples/terraform/main.tf", "Unapproved replacement\n")
        state["branches"]["api2026gateway"]["tip"] = self.commit(candidate)
        state["validation"] = sync.signature(state)
        sync.save(self.workspace, state)
        with self.assertRaisesRegex(RuntimeError, "changed the Terraform extension"):
            sync.publish(self.repository, self.workspace)
        self.assertEqual(self.original, self.remote_heads())

    def test_rejects_fork_movement_during_validation(self):
        self.validated_update()
        self.write(self.repository, "samples/terraform/new.tf", "Concurrent fork work\n")
        self.commit(self.repository)
        sync.git(self.repository, "push", "origin", "main")
        expected = self.remote_heads()
        with self.assertRaisesRegex(RuntimeError, "fork branch changed"):
            sync.publish(self.repository, self.workspace)
        self.assertEqual(expected, self.remote_heads())

    def test_rejects_upstream_movement_during_validation(self):
        self.validated_update()
        self.write(self.upstream, "README.md", "Upstream v3\n")
        self.commit(self.upstream)
        with self.assertRaisesRegex(RuntimeError, "Upstream changed"):
            sync.publish(self.repository, self.workspace)
        self.assertEqual(self.original, self.remote_heads())

    def test_atomic_push_does_not_partially_update_branches(self):
        self.validated_update()
        hook = self.origin / "hooks" / "update"
        hook.write_text(
            '#!/bin/sh\n[ "$1" != "refs/heads/api2026gateway" ]\n',
            encoding="utf-8", newline="\n",
        )
        hook.chmod(0o755)
        with self.assertRaisesRegex(RuntimeError, "git push failed"):
            sync.publish(self.repository, self.workspace)
        self.assertEqual(self.original, self.remote_heads())

    def test_checks_receive_no_publication_token(self):
        with patch.dict(os.environ, {"GH_TOKEN": "fixture-only", "GITHUB_TOKEN": "fixture-only"}):
            with patch.object(sync.subprocess, "run") as run:
                sync.run_checks(self.repository, include_cli=False)
        self.assertNotIn("GH_TOKEN", run.call_args.kwargs["env"])
        self.assertNotIn("GITHUB_TOKEN", run.call_args.kwargs["env"])
        self.assertEqual("0", run.call_args.kwargs["env"]["CLI_TEST_REAL_AZ"])

    def test_cleanup_leaves_unowned_worktrees_untouched(self):
        worktree = self.workspace / "main"
        sync.git(self.repository, "worktree", "add", "--detach", str(worktree), "main")
        self.addCleanup(sync.git, self.repository, "worktree", "remove", "--force", str(worktree))
        sync.cleanup(self.repository, self.workspace)
        self.assertTrue((worktree / "README.md").is_file())


if __name__ == "__main__":
    unittest.main()
