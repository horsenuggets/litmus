import contextlib
import copy
import io
import itertools
import json
import unittest
from datetime import UTC, datetime
from pathlib import Path
from unittest.mock import patch

import release_artifacts as artifacts

NOW = datetime(2026, 1, 1, tzinfo=UTC)
RUN_ID = 123
SHA = "a" * 40


def artifact(system="linux", artifact_id=1, **changes):
    result = {
        "expired": False, "expires_at": "2026-02-01T00:00:00Z", "id": artifact_id,
        "name": f"release-{system}", "workflow_run": {"head_sha": SHA, "id": RUN_ID},
    }
    result.update(changes)
    return result


def pages(*items):
    return [{"artifacts": list(items), "total_count": len(items)}]


def admit(metadata, *, run=None, run_id=RUN_ID, sha=SHA):
    if run is None:
        run = {"head_sha": SHA, "id": RUN_ID}
    return artifacts.admit_artifacts(run, metadata, run_id, sha, NOW)


class AdmissionTests(unittest.TestCase):
    def test_each_combination_reuses_present_platforms_and_builds_only_missing_ones(self):
        for present in itertools.product((False, True), repeat=len(artifacts.SYSTEMS)):
            original = [artifact(system, index + 1)
                        for index, system in enumerate(artifacts.SYSTEMS) if present[index]]
            metadata = pages(*original)
            before = copy.deepcopy(metadata)
            expected = {item["name"].removeprefix("release-"): item["id"] for item in original}
            with self.subTest(present=present):
                self.assertEqual(admit(metadata), expected)
                self.assertEqual(admit(metadata), expected)
                self.assertEqual(metadata, before)

    def test_later_attempts_of_the_same_run_keep_the_original_artifact_ids(self):
        metadata = pages(artifact())
        for attempt in (1, 2, 10):
            run = {"head_sha": SHA, "id": RUN_ID, "run_attempt": attempt}
            with self.subTest(attempt=attempt):
                self.assertEqual(admit(metadata, run=run), {"linux": 1})

    def test_accepts_all_pages_and_ignores_unrelated_artifacts(self):
        metadata = [{"artifacts": [artifact(), {"name": "logs"}], "total_count": 3},
                    {"artifacts": [artifact("macos", 2)], "total_count": 3}]
        self.assertEqual(admit(metadata), {"linux": 1, "macos": 2})

    def test_expired_or_missing_expiry_metadata_never_authorizes_a_rebuild(self):
        invalid = [artifact(expired=True), artifact(expired=None), artifact(expired=0),
                   artifact(expires_at="2025-12-31T23:59:59Z"),
                   artifact(expires_at="2026-01-01T00:00:00Z"),
                   artifact(expires_at=None), artifact(expires_at="not a timestamp"),
                   artifact(expires_at="2026-02-01T00:00:00")]
        for item in invalid:
            with self.subTest(item=item), self.assertRaises(ValueError):
                admit(pages(item))

    def test_duplicate_names_or_ids_fail_closed_across_pages(self):
        for items in ((artifact(), artifact(artifact_id=2)),
                      (artifact(), artifact("macos", 1)),
                      (artifact(), artifact(expired=True))):
            metadata = [{"artifacts": [item], "total_count": len(items)} for item in items]
            with self.subTest(items=items), self.assertRaises(ValueError):
                admit(metadata)

    def test_wrong_run_or_sha_fails_even_when_no_artifacts_exist(self):
        for run in ({"id": RUN_ID + 1, "head_sha": SHA},
                    {"id": RUN_ID, "head_sha": "b" * 40},
                    {"id": str(RUN_ID), "head_sha": SHA}, {}, []):
            with self.subTest(run=run), self.assertRaises(ValueError):
                admit(pages(), run=run)
        for sha in ("a" * 7, SHA.upper(), SHA + "\n"):
            with self.subTest(sha=sha), self.assertRaises(ValueError):
                admit(pages(), sha=sha)
        for run_id in (0, -1, True):
            with self.subTest(run_id=run_id), self.assertRaises(ValueError):
                admit(pages(), run_id=run_id)

    def test_wrong_artifact_identity_and_malformed_metadata_fail_closed(self):
        invalid = [artifact(workflow_run={"id": RUN_ID + 1, "head_sha": SHA}),
                   artifact(workflow_run={"id": RUN_ID, "head_sha": "b" * 40}),
                   artifact(workflow_run=None), artifact(workflow_run={}),
                   artifact(name="release-linux-extra"), artifact(name=None),
                   artifact(artifact_id=0), artifact(artifact_id=True),
                   artifact(artifact_id="1"), {}]
        for item in invalid:
            with self.subTest(item=item), self.assertRaises(ValueError):
                admit(pages(item))
        invalid_pages = [[], {}, [{}], [{"total_count": 1, "artifacts": []}],
                         [{"total_count": 0, "artifacts": [artifact()]}],
                         [{"total_count": True, "artifacts": [artifact()]}],
                         [{"total_count": 0, "artifacts": {}}],
                         [{"total_count": 2, "artifacts": [artifact()]},
                          {"total_count": 1, "artifacts": [artifact("macos", 2)]}]]
        for metadata in invalid_pages:
            with self.subTest(metadata=metadata), self.assertRaises(ValueError):
                admit(metadata)

    def test_lost_upload_response_reuses_original_artifact_without_a_second_build(self):
        # The upload succeeded remotely, but the job never observed its response.
        remote_metadata = pages()
        remote_bytes = {}
        builds = []

        def attempt(*, lose_response=False):
            selected = admit(remote_metadata)
            if "linux" in selected:
                return remote_bytes[selected["linux"]]
            builds.append(len(builds) + 1)
            payload = f"nondeterministic ZIP from build {builds[-1]}".encode()
            remote_metadata[0]["artifacts"].append(artifact())
            remote_metadata[0]["total_count"] += 1
            remote_bytes[1] = payload
            if lose_response:
                raise ConnectionError("The successful upload response was lost.")
            return payload

        with self.assertRaises(ConnectionError):
            attempt(lose_response=True)
        original = copy.deepcopy(remote_metadata)
        self.assertEqual(attempt(), b"nondeterministic ZIP from build 1")
        self.assertEqual(attempt(), b"nondeterministic ZIP from build 1")
        self.assertEqual(builds, [1])
        self.assertEqual(remote_metadata, original)
        self.assertEqual(remote_bytes, {1: b"nondeterministic ZIP from build 1"})


class CommandTests(unittest.TestCase):
    def run_helper(self, metadata, selection, *, run=None):
        files = {"run.json": json.dumps(run if run is not None else {"id": RUN_ID, "head_sha": SHA}),
                 "artifacts.json": json.dumps(metadata)}
        output = io.StringIO()
        with patch.object(Path, "read_text", autospec=True, side_effect=lambda path, **kwargs: files[str(path)]), \
                patch.object(artifacts, "datetime") as clock, \
                contextlib.redirect_stdout(output), contextlib.redirect_stderr(io.StringIO()):
            clock.now.return_value = NOW
            clock.fromisoformat.side_effect = datetime.fromisoformat
            artifacts.main(["--run", "run.json", "--artifacts", "artifacts.json",
                            "--run-id", str(RUN_ID), "--sha", SHA, *selection])
        return output.getvalue()

    def test_prints_only_the_exact_id_or_explicit_missing_decision(self):
        self.assertEqual(self.run_helper(pages(artifact()), ["--system", "linux"]), "1\n")
        self.assertEqual(self.run_helper(pages(artifact()), ["--system", "windows"]), "missing\n")

    def test_publication_requires_and_pins_all_three_system_artifacts(self):
        items = [artifact(system, index + 1) for index, system in enumerate(artifacts.SYSTEMS)]
        self.assertEqual(self.run_helper(pages(*reversed(items)), ["--all"]), "1,2,3\n")
        for missing in range(3):
            with self.subTest(missing=missing), self.assertRaises(SystemExit):
                self.run_helper(pages(*(item for index, item in enumerate(items) if index != missing)), ["--all"])

    def test_refusals_never_emit_a_build_decision(self):
        for metadata in (pages(artifact(expired=True)), pages(artifact(), artifact(artifact_id=2))):
            with self.subTest(metadata=metadata), self.assertRaises(SystemExit):
                self.run_helper(metadata, ["--system", "linux"])
        with self.assertRaises(SystemExit):
            self.run_helper(pages(), ["--system", "linux"], run={"id": RUN_ID, "head_sha": "b" * 40})


class WorkflowTests(unittest.TestCase):
    def test_expensive_build_steps_are_all_gated_on_missing_original_artifacts(self):
        workflow = (Path(__file__).parent.parent / "workflows/release.cd.yml").read_text(encoding="utf-8")
        build = workflow.split("  build-release:\n", 1)[1].split("  publish-release:\n", 1)[0]
        for label in ("Initialize build submodules only for missing artifacts", "Install the declared tools",
                      "Install stable Rust and the binary targets", "Test the native CLI",
                      "Build the release binaries", "Archive the binaries", "uses: actions/upload-artifact@v7"):
            marker = label if label.startswith("uses:") else f"name: {label}"
            step = build.split("      - " + marker + "\n", 1)[1].split("\n      - ", 1)[0]
            with self.subTest(step=label):
                self.assertIn("if: steps.artifacts.outputs.artifact-id == 'missing'", step)
        self.assertIn("overwrite: false", build)
        self.assertIn("actions: read", build)
        self.assertIn('--run-id "$GITHUB_RUN_ID" --sha "$GITHUB_SHA" --system "$SYSTEM"', build)
        publish = workflow.split("  publish-release:\n", 1)[1]
        self.assertIn("actions: read", publish)
        self.assertIn("artifact-ids: ${{ steps.artifacts.outputs.artifact-ids }}", publish)
        self.assertIn("run-id: ${{ github.run_id }}", publish)
        self.assertIn("github-token: ${{ github.token }}", publish)
        self.assertIn("digest-mismatch: error", publish)
        self.assertNotIn("pattern: release-*", publish)
        self.assertEqual(workflow.count("git log --format='%H %T' origin/main"), 2)
        self.assertEqual(workflow.count('--main-history "$RUNNER_TEMP/main-history.txt"'), 2)
        self.assertNotIn("--main-tree", workflow)


if __name__ == "__main__":
    unittest.main()
