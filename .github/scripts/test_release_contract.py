import contextlib
import io
import json
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

import release_contract as contract

OTHER_TREE = "b" * 40
REPOSITORY = "example/litmus"
SOURCE_COMMIT = "c" * 40
TREE = "a" * 40
VERSION = "0.4.0-horse.1.2"


def release(tag, *, draft=False):
    return {
        "draft": draft, "name": tag, "prerelease": False,
        "published_at": None if draft else "2026-01-01T00:00:00Z",
        "tag_name": tag, "target_commitish": TREE,
    }


def tag_ref(**changes):
    result = {"object": {"sha": TREE, "type": "commit"}, "ref": f"refs/tags/{VERSION}"}
    result.update(changes)
    return result


def pull(**changes):
    result = {
        "base": {"ref": "release", "repo": {"full_name": REPOSITORY}},
        "merge_commit_sha": TREE,
        "merged_at": "2026-01-01T00:00:00Z",
        "title": f"Release {VERSION}",
    }
    result.update(changes)
    return result


class VersionTests(unittest.TestCase):
    def test_manifest_lock_and_version_must_all_agree(self):
        for root_matches in (False, True):
            for lock_matches in (False, True):
                with self.subTest(root_matches=root_matches, lock_matches=lock_matches):
                    version = VERSION if root_matches else "0.4.0-horse.1.3"
                    manifest = {"package": {"name": "litmus", "version": VERSION}}
                    lock = {"package": [{"name": "litmus", "version": VERSION if lock_matches else "0.4.0-horse.1.4"}]}
                    if root_matches and lock_matches:
                        contract.validate_versions(version, manifest, lock)
                    else:
                        with self.assertRaisesRegex(ValueError, "must agree"):
                            contract.validate_versions(version, manifest, lock)

    def test_requires_one_local_package_not_a_registry_dependency(self):
        package = {"name": "litmus", "version": VERSION}
        manifest = {"package": package}
        for packages in ([], [package, package], [dict(package, source="registry+example")]):
            with self.subTest(packages=packages), self.assertRaisesRegex(ValueError, "exactly one local"):
                contract.validate_versions(VERSION, manifest, {"package": packages})

    def test_title_is_exact(self):
        contract.validate_title(f"Release {VERSION}", VERSION)
        for title in (VERSION, f"release {VERSION}", f"Release v{VERSION}", f"Release {VERSION}\n", "Release 0.4.0-horse.1.3"):
            with self.subTest(title=title), self.assertRaisesRegex(ValueError, "title must be exactly"):
                contract.validate_title(title, VERSION)

    def test_rejects_malformed_versions(self):
        invalid = [
            "0.4.0", "v0.4.0-horse.1.2", "0.4.0-horse.1", "0.4.0-horse.1.2.3",
            "0.4.0-horse.1.2+build", "0.4.0-Horse.1.2", "0.4.0-horse.-1.2",
            "0.4.0-horse.1.2\n", " 0.4.0-horse.1.2", "0.4.0-horse.１.2",
        ]
        for index in range(5):
            parts = ["0", "4", "0", "1", "2"]
            parts[index] = "01"
            invalid.append(f"{'.'.join(parts[:3])}-horse.{'.'.join(parts[3:])}")
        for version in invalid:
            with self.subTest(version=version), self.assertRaises(ValueError):
                contract.fork_counter(version)

    def test_zero_and_multi_digit_components_are_valid(self):
        self.assertEqual(contract.fork_counter("0.0.0-horse.0.0"), (0, 0))
        self.assertEqual(contract.fork_counter("123.45.6-horse.12.34"), (12, 34))


class HistoryTests(unittest.TestCase):
    def test_counter_order_is_numeric_and_independent_of_upstream_version(self):
        for older in ("99.0.0-horse.1.9", "0.1.0-horse.1.2", "v0.1.0-horse.1.9"):
            contract.validate_history("0.4.0-horse.1.10", [release(older)])
        contract.validate_history("0.1.0-horse.2.0", [release("99.0.0-horse.1.99")])
        for newer in ("0.1.0-horse.1.10", "0.1.0-horse.1.11", "0.1.0-horse.2.0"):
            with self.subTest(newer=newer), self.assertRaisesRegex(ValueError, "must exceed"):
                contract.validate_history("99.0.0-horse.1.10", [release(newer)])

    def test_checks_every_page_even_when_unsorted(self):
        pages = [[release("0.4.0")], [release("0.1.0-horse.9.9")], [release("0.3.0-horse.1.0")]]
        releases = contract.flatten_pages(pages)
        self.assertEqual(len(releases), 3)
        with self.assertRaisesRegex(ValueError, "must exceed"):
            contract.validate_history(VERSION, releases)
        for malformed in ({}, [release(VERSION)], [[], {}]):
            with self.subTest(malformed=malformed), self.assertRaises(ValueError):
                contract.flatten_pages(malformed)

    def test_only_published_fork_counters_count(self):
        contract.validate_history(VERSION, [release("v99.0.0"), release("0.1.0-horse.99.0", draft=True)])
        contract.validate_history(VERSION, [])
        with self.assertRaises(ValueError):
            contract.validate_history(VERSION, [release("0.1.0-horse.01.9")])
        with self.assertRaisesRegex(ValueError, "publication time"):
            contract.validate_history(VERSION, [dict(release("0.1.0"), published_at=None)])

    def test_same_version_is_refused_even_as_a_draft(self):
        for draft in (False, True):
            with self.subTest(draft=draft), self.assertRaisesRegex(ValueError, "Refusing to replace"):
                contract.validate_history(VERSION, [release(VERSION, draft=draft)])


    def test_publication_can_resume_only_the_exact_current_version_and_provenance(self):
        for draft in (False, True):
            current = release(VERSION, draft=draft)
            contract.validate_history(VERSION, [current], publication_sha=TREE, tag=tag_ref())
            invalid = [
                (current, None),
                (current, tag_ref(object={"sha": OTHER_TREE, "type": "commit"})),
                (current, tag_ref(object={"sha": TREE, "type": "tag"})),
                (current, tag_ref(ref="refs/tags/other")),
                (dict(current, target_commitish="release"), tag_ref()),
                (dict(current, name="Other"), tag_ref()),
            ]
            for item, tag in invalid:
                with self.subTest(draft=draft, item=item, tag=tag), self.assertRaises(ValueError):
                    contract.validate_history(VERSION, [item], publication_sha=TREE, tag=tag)
            with self.assertRaisesRegex(ValueError, "must exceed"):
                contract.validate_history(VERSION, [current, release("9.0.0-horse.1.2")],
                                          publication_sha=TREE, tag=tag_ref())
            with self.assertRaisesRegex(ValueError, "Multiple"):
                contract.validate_history(VERSION, [current, current], publication_sha=TREE, tag=tag_ref())
        with self.assertRaisesRegex(ValueError, "non-prerelease"):
            contract.validate_history(VERSION, [dict(release(VERSION), prerelease=True)],
                                      publication_sha=TREE, tag=tag_ref())


class TreeTests(unittest.TestCase):
    def test_proposal_requires_both_head_and_merge_to_match_main(self):
        for head_matches in (False, True):
            for merge_matches in (False, True):
                head = TREE if head_matches else OTHER_TREE
                merge = TREE if merge_matches else OTHER_TREE
                with self.subTest(head_matches=head_matches, merge_matches=merge_matches):
                    if head_matches and merge_matches:
                        contract.validate_proposal_trees(head, merge, TREE)
                    else:
                        with self.assertRaisesRegex(ValueError, "exactly match"):
                            contract.validate_proposal_trees(head, merge, TREE)

    def test_all_proposal_tree_ids_must_be_valid(self):
        for invalid in ("", "a" * 7, "origin/main", "A" * 40, "a" * 40 + "\n", "g" * 40):
            for index in range(3):
                trees = [TREE, TREE, TREE]
                trees[index] = invalid
                with self.subTest(trees=trees), self.assertRaises(ValueError):
                    contract.validate_proposal_trees(*trees)

    def test_compares_trees_not_commit_history(self):
        contract.validate_tree(TREE, TREE)
        with self.assertRaisesRegex(ValueError, "exactly match"):
            contract.validate_tree(TREE, OTHER_TREE)

    def test_missing_or_abbreviated_trees_fail_closed(self):
        for proposed, main in (("", ""), (TREE, ""), ("a" * 7, TREE), ("origin/main", TREE)):
            with self.subTest(proposed=proposed, main=main), self.assertRaises(ValueError):
                contract.validate_tree(proposed, main)

    def test_publication_accepts_an_older_matching_main_snapshot_and_pins_its_commit(self):
        history = f"{OTHER_TREE} {OTHER_TREE}\n{SOURCE_COMMIT} {TREE}\n"
        self.assertEqual(contract.validate_main_snapshot(TREE, history), SOURCE_COMMIT)
        with self.assertRaisesRegex(ValueError, "reachable origin/main snapshot"):
            contract.validate_main_snapshot(TREE, f"{OTHER_TREE} {OTHER_TREE}\n")
        # History cannot relax proposal parity with the current main tree.
        with self.assertRaisesRegex(ValueError, "current origin/main"):
            contract.validate_proposal_trees(TREE, TREE, OTHER_TREE)

    def test_history_is_strictly_parsed_in_full_even_after_a_matching_snapshot(self):
        valid = f"{SOURCE_COMMIT} {TREE}"
        for invalid in ("", "\n", "a b", f"{SOURCE_COMMIT}  {TREE}",
                        f"{SOURCE_COMMIT}\t{TREE}", f"{SOURCE_COMMIT} {TREE.upper()}",
                        valid + " extra", valid + "\r\n", valid + "\n\n",
                        valid + "\nmalformed", valid + "\n" + valid,
                        valid + f"\n{SOURCE_COMMIT} {OTHER_TREE}"):
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                contract.validate_main_snapshot(TREE, invalid)
        self.assertEqual(contract.validate_main_snapshot(TREE, valid), SOURCE_COMMIT)
        for invalid in ("", "a" * 7, "HEAD", TREE + "\n"):
            with self.subTest(tree=invalid), self.assertRaises(ValueError):
                contract.validate_main_snapshot(invalid, valid)

    def test_requires_the_exact_merge_commit_and_repository(self):
        self.assertEqual(contract.merged_release_title([pull()], REPOSITORY, TREE), f"Release {VERSION}")
        invalid = [
            [], [pull(), pull()], [pull(merge_commit_sha=OTHER_TREE)], [pull(merged_at=None)],
            [pull(base={"ref": "main", "repo": {"full_name": REPOSITORY}})],
            [pull(base={"ref": "release", "repo": {"full_name": "other/litmus"}})],
        ]
        for pulls in invalid:
            with self.subTest(pulls=pulls), self.assertRaisesRegex(ValueError, "exact merge commit"):
                contract.merged_release_title(pulls, REPOSITORY, TREE)


class ArchiveTests(unittest.TestCase):
    def setUp(self):
        self.directory = MagicMock(spec=Path)
        self.paths = []
        self.binaries = {}
        for platform, binary in contract.ARCHIVE_BINARIES.items():
            name = f"litmus-{VERSION}-{platform}.zip"
            path = MagicMock(spec=Path)
            path.name = name
            path.is_file.return_value = True
            path.is_symlink.return_value = False
            self.paths.append(path)
            self.binaries[name] = binary
        self.directory.iterdir.side_effect = lambda: iter(self.paths)
        self.directory.__truediv__.side_effect = lambda name: next(path for path in self.paths if path.name == name)
        self.archive = MagicMock()
        self.archive.testzip.return_value = None
        self.archive.getinfo.return_value.file_size = 1
        self.archive.namelist.side_effect = lambda: [self.binaries[self.current_path.name]]

    def open_archive(self, path):
        self.current_path = path
        result = MagicMock()
        result.__enter__.return_value = self.archive
        return result

    def test_accepts_exactly_four_archives_with_root_binaries(self):
        with patch.object(contract.zipfile, "ZipFile", side_effect=self.open_archive):
            contract.validate_archives(self.directory, VERSION)

    def test_missing_extra_or_wrong_version_archive_is_refused(self):
        original = list(self.paths)
        for names in (original[:-1], original + [Path("extra.zip")], [Path("litmus-other.zip")] + original[1:]):
            self.paths = names
            with self.subTest(names=names), self.assertRaisesRegex(ValueError, "exactly the four"):
                contract.validate_archives(self.directory, VERSION)

    def test_wrong_binary_empty_binary_corruption_and_symlinks_are_refused(self):
        with patch.object(contract.zipfile, "ZipFile", side_effect=self.open_archive):
            self.archive.namelist.side_effect = None
            self.archive.namelist.return_value = ["nested/litmus"]
            with self.assertRaisesRegex(ValueError, "nonempty binary"):
                contract.validate_archives(self.directory, VERSION)
            self.archive.namelist.side_effect = lambda: [self.binaries[self.current_path.name]]
            self.archive.getinfo.return_value.file_size = 0
            with self.assertRaisesRegex(ValueError, "nonempty binary"):
                contract.validate_archives(self.directory, VERSION)
            self.archive.getinfo.return_value.file_size = 1
            self.archive.testzip.return_value = "litmus"
            with self.assertRaisesRegex(ValueError, "CRC"):
                contract.validate_archives(self.directory, VERSION)
            self.paths[0].is_symlink.return_value = True
            with self.assertRaisesRegex(ValueError, "regular file"):
                contract.validate_archives(self.directory, VERSION)


class CommandTests(unittest.TestCase):
    def setUp(self):
        self.files = {
            "VERSION": VERSION + "\n",
            "cli/Cargo.toml": f'[package]\nname = "litmus"\nversion = "{VERSION}"\n',
            "cli/Cargo.lock": f'[[package]]\nname = "litmus"\nversion = "{VERSION}"\n',
            "releases.json": "[[]]",
            "tag.json": "null",
            "pulls.json": json.dumps([[pull()]]),
            "main-history.txt": f"{SOURCE_COMMIT} {TREE}\n",
        }
        self.args = ["--root", ".", "--releases", "releases.json", "--tag", "tag.json",
                     "--proposed-tree", TREE]
        self.publication = ["--pulls", "pulls.json", "--repository", REPOSITORY, "--sha", TREE]

    def run_contract(self, args, *, source=None):
        if source is None:
            source = (["--main-history", "main-history.txt"] if "--pulls" in args
                      else ["--main-tree", TREE])
        output = io.StringIO()
        self.errors = io.StringIO()
        with patch.object(Path, "read_text", autospec=True, side_effect=lambda path, **kwargs: self.files[str(path)]):
            with contextlib.redirect_stdout(output), contextlib.redirect_stderr(self.errors):
                contract.main(self.args + source + args)
        return output.getvalue()

    def test_pr_and_publication_modes_use_the_same_contract(self):
        self.assertEqual(self.run_contract(["--title", f"Release {VERSION}", "--merge-tree", TREE]), VERSION + "\n")
        self.assertEqual(self.run_contract(["--pulls", "pulls.json", "--repository", REPOSITORY, "--sha", TREE]), VERSION + "\n")

    def test_advanced_main_accepts_only_the_exact_release_retry_from_main_history(self):
        self.files["main-history.txt"] = f"{OTHER_TREE} {OTHER_TREE}\n{SOURCE_COMMIT} {TREE}\n"
        self.files["tag.json"] = json.dumps(tag_ref())
        for draft in (False, True):
            self.files["releases.json"] = json.dumps([[release(VERSION, draft=draft)]])
            self.assertEqual(self.run_contract(self.publication), VERSION + "\n")
            self.assertIn(SOURCE_COMMIT, self.errors.getvalue())
        self.files["main-history.txt"] = f"{OTHER_TREE} {OTHER_TREE}\n"
        with self.assertRaises(SystemExit):
            self.run_contract(self.publication)
        self.assertIn("reachable origin/main snapshot", self.errors.getvalue())

    def test_historical_admission_is_only_for_publication(self):
        proposal = ["--title", f"Release {VERSION}", "--merge-tree", TREE]
        for args, source in ((proposal, ["--main-tree", OTHER_TREE]),
                             (proposal, ["--main-history", "main-history.txt"]),
                             (self.publication, ["--main-tree", TREE]),
                             (self.publication, [])):
            with self.subTest(args=args, source=source), self.assertRaises(SystemExit):
                self.run_contract(args, source=source)

    def test_historical_snapshot_never_relaxes_merged_pr_or_triggering_sha_checks(self):
        self.files["main-history.txt"] = f"{OTHER_TREE} {OTHER_TREE}\n{SOURCE_COMMIT} {TREE}\n"
        invalid = [
            [pull(merge_commit_sha=OTHER_TREE)], [pull(merged_at=None)], [pull(), pull()],
            [pull(title="Release other")],
            [pull(base={"ref": "main", "repo": {"full_name": REPOSITORY}})],
            [pull(base={"ref": "release", "repo": {"full_name": "other/litmus"}})],
        ]
        for pulls in invalid:
            self.files["pulls.json"] = json.dumps([pulls])
            with self.subTest(pulls=pulls), self.assertRaises(SystemExit):
                self.run_contract(self.publication)
        self.files["pulls.json"] = json.dumps([[pull()]])
        for sha in (OTHER_TREE, "a" * 7):
            with self.subTest(sha=sha), self.assertRaises(SystemExit):
                self.run_contract(["--pulls", "pulls.json", "--repository", REPOSITORY, "--sha", sha])

    def test_proposal_requires_merge_tree_even_when_head_matches(self):
        with self.assertRaises(SystemExit):
            self.run_contract(["--title", f"Release {VERSION}"])
        with self.assertRaises(SystemExit):
            self.run_contract(["--title", f"Release {VERSION}", "--merge-tree", OTHER_TREE])

    def test_used_versions_are_only_accepted_for_exact_publication_provenance(self):
        self.files["tag.json"] = json.dumps(tag_ref())
        with self.assertRaises(SystemExit):
            self.run_contract(["--title", f"Release {VERSION}", "--merge-tree", TREE])
        for draft in (False, True):
            self.files["releases.json"] = json.dumps([[release(VERSION, draft=draft)]])
            with self.assertRaises(SystemExit):
                self.run_contract(["--title", f"Release {VERSION}", "--merge-tree", TREE])
            self.assertEqual(self.run_contract(["--pulls", "pulls.json", "--repository", REPOSITORY,
                                                "--sha", TREE]), VERSION + "\n")
        self.files["tag.json"] = "null"
        with self.assertRaises(SystemExit):
            self.run_contract(["--pulls", "pulls.json", "--repository", REPOSITORY, "--sha", TREE])

    def test_refuses_inconsistent_source_and_wrong_merge_title(self):
        self.files["VERSION"] = "0.4.0-horse.1.3\n"
        with self.assertRaises(SystemExit) as error:
            self.run_contract(["--title", f"Release {VERSION}", "--merge-tree", TREE])
        self.assertEqual(error.exception.code, 1)
        self.files["VERSION"] = VERSION
        self.files["pulls.json"] = json.dumps([[pull(title="Release something else")]])
        with self.assertRaises(SystemExit):
            self.run_contract(["--pulls", "pulls.json", "--repository", REPOSITORY, "--sha", TREE])

    def test_current_unsuffixed_version_is_not_publishable(self):
        for path in ("VERSION", "cli/Cargo.toml", "cli/Cargo.lock"):
            self.files[path] = self.files[path].replace(VERSION, "0.4.0")
        with self.assertRaises(SystemExit):
            self.run_contract(["--title", "Release 0.4.0"])


if __name__ == "__main__":
    unittest.main()
