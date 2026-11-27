import copy
import json
import subprocess
import tempfile
import unittest
import zipfile
from datetime import UTC, datetime
from pathlib import Path
from unittest.mock import patch

import publish_release as publisher
from release_artifacts import SYSTEMS, admit_artifacts
from release_contract import ARCHIVE_BINARIES

REPOSITORY = "example/litmus"
SHA = "a" * 40
VERSION = "0.4.0-horse.1.2"


def tag(sha=SHA, kind="commit"):
    return {"object": {"sha": sha, "type": kind}, "ref": f"refs/tags/{VERSION}"}


def release(*, draft=True, **changes):
    result = {
        "draft": draft, "id": 10, "name": VERSION, "prerelease": False,
        "published_at": None if draft else "2026-01-01T00:00:00Z",
        "tag_name": VERSION, "target_commitish": SHA,
    }
    result.update(changes)
    return result


class FakeGH:
    """Stateful remote model with atomic creates and injected partial failures."""

    def __init__(self, expected):
        self.expected = expected
        self.tag = None
        self.release = None
        self.assets = {}
        self.writes = []
        self.events = []
        self.hooks = {}

    def event(self, name):
        self.events.append(name)
        hook = self.hooks.pop(name, None)
        if hook:
            hook(self)

    def assert_tag(self):
        if self.tag != tag():
            raise AssertionError("A mutation occurred without the exact lightweight tag.")
        if not self.events or self.events[-1] != "get_tag":
            raise AssertionError("The tag was not rechecked immediately before mutation.")

    def get_tag(self, version):
        self.event("get_tag")
        return copy.deepcopy(self.tag)

    def create_tag(self, version, sha):
        if self.events[-1] != "get_tag":
            raise AssertionError("Tag creation must follow inspection.")
        self.event("create_tag")
        if self.tag is not None:
            raise publisher.GHError("The tag already exists.")
        self.tag = tag(sha)
        self.writes.append(("create_tag", version, sha))
        self.event("after_create_tag")

    def get_release(self, version):
        self.event("get_release")
        return copy.deepcopy(self.release)

    def create_draft(self, version, sha):
        self.assert_tag()
        self.event("create_draft")
        if self.release is not None:
            raise publisher.GHError("The release already exists.")
        self.release = release(target_commitish=sha)
        self.writes.append(("create_draft", version, sha))
        self.event("after_create_draft")

    def get_assets(self, release_id):
        self.event("get_assets")
        return [{"id": name, "name": name, "state": "uploaded"} for name in self.assets]

    def download_asset(self, asset_id):
        self.event("download_asset")
        return self.assets[asset_id]

    def upload_asset(self, release_id, path):
        self.assert_tag()
        self.event("upload_asset")
        if not self.release["draft"] or path.name in self.assets:
            raise publisher.GHError("Refusing to replace an asset or modify a published release.")
        self.assets[path.name] = path.read_bytes()
        self.writes.append(("upload_asset", path.name))
        self.event("after_upload_asset")

    def publish(self, release_id):
        self.assert_tag()
        self.event("publish")
        if not self.release["draft"] or self.assets != self.expected:
            raise AssertionError("Publication must have exactly the verified assets.")
        self.release.update(draft=False, prerelease=False, published_at="2026-01-01T00:00:00Z")
        self.writes.append(("publish", release_id))
        self.event("after_publish")


def fail(_):
    raise publisher.GHError("Injected network failure.")


class PublicationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        for platform, binary in ARCHIVE_BINARIES.items():
            with zipfile.ZipFile(self.directory / f"litmus-{VERSION}-{platform}.zip", "w") as archive:
                archive.writestr(binary, f"binary for {platform}".encode())
        self.expected = {path.name: path.read_bytes() for path in self.directory.iterdir()}
        self.gh = FakeGH(self.expected)

    def publish(self):
        return publisher.publish_release(self.gh, VERSION, SHA, self.directory)

    def seed(self, *, draft=True, count=0):
        self.gh.tag = tag()
        self.gh.release = release(draft=draft)
        self.gh.assets = dict(list(self.expected.items())[:count])

    def assert_complete(self):
        self.assertEqual(self.gh.tag, tag())
        self.assertEqual(self.gh.release, release(draft=False))
        self.assertEqual(self.gh.assets, self.expected)

    def test_absent_state_creates_tag_draft_assets_and_non_prerelease(self):
        self.publish()
        self.assert_complete()
        self.assertEqual([write[0] for write in self.gh.writes],
                         ["create_tag", "create_draft", *(["upload_asset"] * 4), "publish"])

    def test_tag_only_resumes_without_recreating_tag(self):
        self.gh.tag = tag()
        self.publish()
        self.assert_complete()
        self.assertNotIn("create_tag", [write[0] for write in self.gh.writes])

    def test_every_partial_draft_uploads_only_missing_assets(self):
        for count in range(5):
            with self.subTest(count=count):
                self.gh = FakeGH(self.expected)
                self.seed(count=count)
                original = dict(self.gh.assets)
                self.publish()
                self.assert_complete()
                uploads = {write[1] for write in self.gh.writes if write[0] == "upload_asset"}
                self.assertEqual(uploads, self.expected.keys() - original.keys())
                self.assertTrue(all(self.gh.assets[name] == data for name, data in original.items()))
                self.assertEqual(len(self.gh.writes), 5 - count)

    def test_original_run_artifacts_resume_a_lost_asset_upload_response_byte_for_byte(self):
        run = {"id": 123, "head_sha": SHA}
        metadata = []
        stored = {}
        for artifact_id, system in enumerate(SYSTEMS, start=1):
            metadata.append({
                "expired": False, "expires_at": "2026-02-01T00:00:00Z",
                "id": artifact_id, "name": f"release-{system}", "workflow_run": run,
            })
            stored[artifact_id] = {name: data for name, data in self.expected.items()
                                   if f"-{system}-" in name}
        self.seed(count=1)
        self.gh.hooks["after_upload_asset"] = fail
        with self.assertRaises(publisher.GHError):
            self.publish()
        original_assets = dict(self.gh.assets)
        self.assertEqual(len(original_assets), 2)

        # A rebuild is still refused. Recovery must download the stored original bytes.
        for path in self.directory.iterdir():
            with zipfile.ZipFile(path, "a") as archive:
                archive.comment = b"different nondeterministic build"
        writes_before = list(self.gh.writes)
        with self.assertRaisesRegex(ValueError, "differs from this run"):
            self.publish()
        self.assertEqual(self.gh.writes, writes_before)
        self.assertEqual(self.gh.assets, original_assets)

        selected = admit_artifacts(
            run, [{"artifacts": metadata, "total_count": len(metadata)}],
            run["id"], SHA, datetime(2026, 1, 1, tzinfo=UTC),
        )
        for artifact_id in selected.values():
            for name, data in stored[artifact_id].items():
                (self.directory / name).write_bytes(data)
        self.assertEqual({path.name: path.read_bytes() for path in self.directory.iterdir()}, self.expected)
        self.publish()
        self.assert_complete()
        uploads = [write[1] for write in self.gh.writes if write[0] == "upload_asset"]
        self.assertEqual(len(uploads), 3)
        self.assertEqual(len(set(uploads)), 3)
        self.assertTrue(all(self.gh.assets[name] == data for name, data in original_assets.items()))

    def test_published_release_is_a_verified_no_op(self):
        self.seed(draft=False, count=4)
        self.assertIn("No changes", self.publish())
        self.assert_complete()
        self.assertEqual(self.gh.writes, [])

    def test_wrong_or_annotated_tags_never_mutate(self):
        for wrong in (tag("b" * 40), tag(kind="tag"), dict(tag(), ref="refs/tags/other")):
            with self.subTest(wrong=wrong):
                self.gh.tag = wrong
                with self.assertRaisesRegex(ValueError, "lightweight"):
                    self.publish()
                self.assertEqual(self.gh.tag, wrong)
                self.assertEqual(self.gh.writes, [])

    def test_orphan_release_and_conflicting_metadata_never_mutate(self):
        for changes in ({"name": "other"}, {"target_commitish": "release"},
                        {"target_commitish": "b" * 40}, {"tag_name": "other"}):
            self.seed(count=2)
            self.gh.release.update(changes)
            before = copy.deepcopy(self.gh.release)
            with self.subTest(changes=changes), self.assertRaisesRegex(ValueError, "exact version"):
                self.publish()
            self.assertEqual(self.gh.release, before)
            self.assertEqual(self.gh.writes, [])
        self.seed(count=2)
        self.gh.tag = None
        with self.assertRaisesRegex(ValueError, "lightweight"):
            self.publish()
        self.assertEqual(self.gh.writes, [])

    def test_published_missing_extra_and_conflicting_assets_are_immutable(self):
        for defect in ("missing", "extra", "bytes", "prerelease"):
            with self.subTest(defect=defect):
                self.seed(draft=False, count=4)
                if defect == "missing":
                    self.gh.assets.pop(next(iter(self.expected)))
                elif defect == "extra":
                    self.gh.assets["extra.zip"] = b"unexpected"
                elif defect == "bytes":
                    self.gh.assets[next(iter(self.expected))] = b"different"
                else:
                    self.gh.release["prerelease"] = True
                before = copy.deepcopy((self.gh.release, self.gh.assets))
                with self.assertRaises(ValueError):
                    self.publish()
                self.assertEqual((self.gh.release, self.gh.assets), before)
                self.assertEqual(self.gh.writes, [])

    def test_draft_extra_or_conflicting_bytes_fail_before_any_upload(self):
        for extra in (False, True):
            self.seed(count=1)
            self.gh.assets["extra.zip" if extra else next(iter(self.expected))] = b"conflict"
            before = dict(self.gh.assets)
            with self.subTest(extra=extra), self.assertRaises(ValueError):
                self.publish()
            self.assertEqual(self.gh.assets, before)
            self.assertEqual(self.gh.writes, [])

    def test_exact_tag_creation_race_is_verified_not_overwritten(self):
        self.gh.hooks["create_tag"] = lambda gh: setattr(gh, "tag", tag())
        self.publish()
        self.assert_complete()
        self.assertNotIn("create_tag", [write[0] for write in self.gh.writes])

    def test_conflicting_tag_creation_race_is_refused(self):
        wrong = tag("b" * 40)
        self.gh.hooks["create_tag"] = lambda gh: setattr(gh, "tag", wrong)
        with self.assertRaisesRegex(ValueError, "lightweight"):
            self.publish()
        self.assertEqual(self.gh.tag, wrong)
        self.assertEqual(self.gh.writes, [])

    def test_lost_tag_and_draft_creation_responses_are_reinspected(self):
        for event in ("after_create_tag", "after_create_draft"):
            with self.subTest(event=event):
                self.gh = FakeGH(self.expected)
                self.gh.hooks[event] = fail
                self.publish()
                self.assert_complete()
                self.assertEqual(sum(write[0] == "create_tag" for write in self.gh.writes), 1)
                self.assertEqual(sum(write[0] == "create_draft" for write in self.gh.writes), 1)

    def test_draft_creation_race_requires_matching_metadata_and_bytes(self):
        for conflict in ("none", "metadata", "bytes", "extra"):
            with self.subTest(conflict=conflict):
                self.gh = FakeGH(self.expected)
                self.gh.tag = tag()

                def race(gh):
                    gh.release = release(name="other" if conflict == "metadata" else VERSION)
                    if conflict == "bytes":
                        gh.assets[next(iter(self.expected))] = b"conflict"
                    if conflict == "extra":
                        gh.assets["extra.zip"] = b"extra"

                self.gh.hooks["create_draft"] = race
                if conflict == "none":
                    self.publish()
                    self.assert_complete()
                else:
                    with self.assertRaises(ValueError):
                        self.publish()
                    self.assertEqual(self.gh.writes, [])

    def test_upload_race_never_clobbers_and_matching_bytes_can_resume(self):
        for matching in (False, True):
            with self.subTest(matching=matching):
                self.gh = FakeGH(self.expected)
                self.seed()
                name = sorted(self.expected)[0]
                data = self.expected[name] if matching else b"conflict"
                self.gh.hooks["upload_asset"] = lambda gh: gh.assets.update({name: data})
                with self.assertRaises(publisher.GHError):
                    self.publish()
                self.assertEqual(self.gh.assets, {name: data})
                self.assertEqual(self.gh.writes, [])
                if matching:
                    self.publish()
                    self.assert_complete()
                else:
                    with self.assertRaisesRegex(ValueError, "differs"):
                        self.publish()
                    self.assertEqual(self.gh.writes, [])

    def test_retry_after_every_partial_network_failure_preserves_content(self):
        for event in ("create_tag", "create_draft", "upload_asset", "after_upload_asset",
                      "publish", "after_publish", "get_tag", "get_release", "get_assets", "download_asset"):
            with self.subTest(event=event):
                self.gh = FakeGH(self.expected)
                self.gh.hooks[event] = fail
                with self.assertRaises(publisher.GHError):
                    self.publish()
                original = dict(self.gh.assets)
                self.publish()
                self.assert_complete()
                self.assertTrue(all(self.gh.assets[name] == data for name, data in original.items()))
                for name in self.expected:
                    self.assertEqual(self.gh.writes.count(("upload_asset", name)), 1)
                self.assertEqual(sum(write[0] == "publish" for write in self.gh.writes), 1)

    def test_changed_tag_before_upload_or_publish_fails_closed(self):
        for count in (0, 4):
            self.gh = FakeGH(self.expected)
            self.seed(count=count)
            original = dict(self.gh.assets)
            # Change the ref during asset inspection, after initial tag verification.
            self.gh.hooks["get_assets"] = lambda gh: setattr(gh, "tag", tag("b" * 40))
            with self.subTest(count=count), self.assertRaisesRegex(ValueError, "lightweight"):
                self.publish()
            self.assertEqual(self.gh.assets, original)
            self.assertEqual(self.gh.writes, [])

    def test_full_assets_are_compared_again_before_publishing(self):
        self.seed(count=3)

        def corrupt(gh):
            gh.assets[next(iter(self.expected))] = b"changed after upload"

        self.gh.hooks["after_upload_asset"] = corrupt
        with self.assertRaisesRegex(ValueError, "differs"):
            self.publish()
        self.assertTrue(self.gh.release["draft"])
        self.assertEqual([write[0] for write in self.gh.writes], ["upload_asset"])

    def test_tag_is_rechecked_after_upload_before_the_next_mutation(self):
        for count in (0, 3):
            with self.subTest(count=count):
                self.gh = FakeGH(self.expected)
                self.seed(count=count)
                original = dict(self.gh.assets)
                self.gh.hooks["after_upload_asset"] = lambda gh: setattr(gh, "tag", tag("b" * 40))
                with self.assertRaisesRegex(ValueError, "lightweight"):
                    self.publish()
                self.assertTrue(self.gh.release["draft"])
                self.assertEqual([write[0] for write in self.gh.writes], ["upload_asset"])
                self.assertTrue(all(self.gh.assets[name] == data for name, data in original.items()))

    def test_metadata_changes_or_release_replacement_stop_further_writes(self):
        for changes in ({"id": 11}, {"name": "other"}, {"target_commitish": "main"}):
            with self.subTest(changes=changes):
                self.gh = FakeGH(self.expected)
                self.seed(count=3)
                self.gh.hooks["after_upload_asset"] = lambda gh: gh.release.update(changes)
                with self.assertRaises(ValueError):
                    self.publish()
                self.assertTrue(self.gh.release["draft"])
                self.assertEqual(self.gh.assets, self.expected)
                self.assertEqual([write[0] for write in self.gh.writes], ["upload_asset"])

    def test_network_failure_during_published_verification_never_writes(self):
        for event in ("get_tag", "get_release", "get_assets", "download_asset"):
            with self.subTest(event=event):
                self.gh = FakeGH(self.expected)
                self.seed(draft=False, count=4)
                self.gh.hooks[event] = fail
                with self.assertRaises(publisher.GHError):
                    self.publish()
                self.assert_complete()
                self.assertEqual(self.gh.writes, [])
                self.assertIn("No changes", self.publish())
                self.assertEqual(self.gh.writes, [])

    def test_a_draft_marked_prerelease_is_explicitly_published_as_non_prerelease(self):
        self.seed(count=4)
        self.gh.release["prerelease"] = True
        self.publish()
        self.assert_complete()
        self.assertEqual(self.gh.writes, [("publish", 10)])

    def test_invalid_sha_or_archives_never_reach_remote_writes(self):
        for invalid in ("", "main", "a" * 7, "g" * 40):
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                publisher.publish_release(self.gh, VERSION, invalid, self.directory)
        (self.directory / next(iter(self.expected))).unlink()
        with self.assertRaisesRegex(ValueError, "four"):
            self.publish()
        self.assertEqual(self.gh.events, [])
        self.assertEqual(self.gh.writes, [])


class DecisionTests(unittest.TestCase):
    def test_asset_name_and_upload_state_validation(self):
        expected = {"one.zip": b"one"}
        asset = {"id": 1, "name": "one.zip", "state": "uploaded"}
        self.assertEqual(publisher.missing_assets([], expected, draft=True), ["one.zip"])
        self.assertEqual(publisher.missing_assets([asset], expected, draft=False), [])
        for assets in ([], [asset, asset], [dict(asset, name="extra.zip")], [dict(asset, state="starter")]):
            with self.subTest(assets=assets), self.assertRaises(ValueError):
                publisher.missing_assets(assets, expected, draft=False)


class BoundaryTests(unittest.TestCase):
    def setUp(self):
        self.gh = publisher.GitHub(REPOSITORY)

    def response(self, stdout, *, code=0, stderr=b"failure"):
        return subprocess.CompletedProcess([], code, stdout, stderr)

    def test_only_http_404_means_tag_absence(self):
        for status, code in ((404, 1), (401, 1), (403, 1), (429, 1), (500, 1), (200, 1)):
            result = self.response(f"HTTP/2.0 {status} Status\r\nContent-Type: application/json\r\n\r\n{{}}".encode(), code=code)
            with self.subTest(status=status), patch.object(publisher.subprocess, "run", return_value=result):
                if status == 404:
                    self.assertIsNone(self.gh.get_tag(VERSION))
                else:
                    with self.assertRaises(publisher.GHError):
                        self.gh.get_tag(VERSION)
        for output in (b"", b'{"message":"Not Found"}', b"HTTP/2.0 200 OK\r\n\r\n{}"):
            with patch.object(publisher.subprocess, "run", return_value=self.response(output, code=1)):
                with self.assertRaises(publisher.GHError):
                    self.gh.get_tag(VERSION)

    def test_tag_response_parses_lf_and_crlf_headers(self):
        for newline in (b"\n", b"\r\n"):
            data = newline.join([b"HTTP/2.0 200 OK", b"Content-Type: application/json", b"", json.dumps(tag()).encode()])
            with patch.object(publisher.subprocess, "run", return_value=self.response(data)):
                self.assertEqual(self.gh.get_tag(VERSION), tag())

    def test_drafts_and_assets_are_paginated_and_duplicate_releases_refused(self):
        data = [[], [release()]]
        with patch.object(self.gh, "run", return_value=json.dumps(data).encode()) as run:
            self.assertEqual(self.gh.get_release(VERSION), release())
            self.assertIn("--paginate", run.call_args.args[0])
            self.assertIn("--slurp", run.call_args.args[0])
        with patch.object(self.gh, "run", return_value=b"[[], []]"):
            self.assertIsNone(self.gh.get_release(VERSION))
            self.assertEqual(self.gh.get_assets(10), [])
        with patch.object(self.gh, "run", return_value=json.dumps([[release()], [release()]]).encode()):
            with self.assertRaisesRegex(ValueError, "Multiple"):
                self.gh.get_release(VERSION)

    def test_mutation_commands_have_no_destructive_operations_and_force_non_prerelease(self):
        with patch.object(self.gh, "run", return_value=b"{}") as run:
            self.gh.create_tag(VERSION, SHA)
            self.gh.create_draft(VERSION, SHA)
            self.gh.upload_asset(10, Path("archives/one.zip"))
            self.gh.publish(10)
        calls = [call.args[0] for call in run.call_args_list]
        self.assertIn("--verify-tag", calls[1])
        self.assertIn(SHA, calls[1])
        self.assertIn("--prerelease=false", calls[1])
        self.assertIn("prerelease=false", calls[3])
        self.assertIn("draft=false", calls[3])
        for args in calls:
            self.assertNotIn("DELETE", args)
            self.assertNotIn("--clobber", args)
            self.assertNotIn("--force", args)
        self.assertEqual(calls[0][calls[0].index("--method") + 1], "POST")
        self.assertEqual(calls[2][calls[2].index("--method") + 1], "POST")

    def test_asset_download_preserves_exact_binary_bytes_and_errors_fail(self):
        data = b"PK\x00\xff\r\n\x80"
        with patch.object(publisher.subprocess, "run", return_value=self.response(data)):
            self.assertEqual(self.gh.download_asset(1), data)
        with patch.object(publisher.subprocess, "run", return_value=self.response(b"", code=1)):
            with self.assertRaises(publisher.GHError):
                self.gh.download_asset(1)


if __name__ == "__main__":
    unittest.main()
