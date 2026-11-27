"""Validate release inputs without making network requests or changing Git refs."""

import argparse
import json
import re
import sys
import tomllib
import zipfile
from pathlib import Path

ARCHIVE_BINARIES = {
    "linux-x86_64": "litmus",
    "macos-aarch64": "litmus",
    "macos-x86_64": "litmus",
    "windows-x86_64": "litmus.exe",
}
FORK_VERSION = re.compile(
    r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)"
    r"-horse\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", re.ASCII
)
TREE_ID = re.compile(r"[0-9a-f]{40}", re.ASCII)


def fork_counter(version):
    match = FORK_VERSION.fullmatch(version)
    if match is None:
        raise ValueError(f'Version "{version}" must have the form X.Y.Z-horse.X.Y without leading zeros.')
    return tuple(int(part) for part in match.groups()[-2:])


def validate_versions(version, manifest, lock):
    package = manifest["package"]
    locked = [item for item in lock["package"] if item["name"] == package["name"] and "source" not in item]
    if len(locked) != 1:
        raise ValueError("Cargo.lock must contain exactly one local CLI package.")
    if version != package["version"] or version != locked[0]["version"]:
        raise ValueError("VERSION, cli/Cargo.toml and the local CLI package in cli/Cargo.lock must agree.")
    fork_counter(version)


def validate_title(title, version):
    if title != f"Release {version}":
        raise ValueError(f'The pull request title must be exactly "Release {version}".')


def flatten_pages(pages):
    if not isinstance(pages, list) or any(not isinstance(page, list) for page in pages):
        raise ValueError("The API response must contain every page from gh api --paginate --slurp.")
    return [item for page in pages for item in page]


def validate_tag(version, sha, tag):
    if not TREE_ID.fullmatch(sha):
        raise ValueError("Publication requires a full Git SHA-1 commit ID.")
    if (tag is None or tag["ref"] != f"refs/tags/{version}"
            or tag["object"]["type"] != "commit" or tag["object"]["sha"] != sha):
        raise ValueError("The existing tag must be lightweight and point exactly to the triggering SHA.")


def validate_release_metadata(release, version, sha):
    if (release["tag_name"] != version or release["name"] != version
            or release["target_commitish"] != sha):
        raise ValueError("The existing release must have the exact version, name and triggering SHA target.")
    if not release["draft"] and (release["prerelease"] or not release["published_at"]):
        raise ValueError("The published release must be non-prerelease and have a publication time.")


def validate_history(version, releases, *, publication_sha=None, tag=None):
    counter = fork_counter(version)
    current = [release for release in releases if release["tag_name"] == version]
    if len(current) > 1:
        raise ValueError("Multiple releases use the current version.")
    for release in releases:
        name = release["tag_name"]
        if name == version:
            if publication_sha is None:
                raise ValueError(f'A release for "{version}" already exists. Refusing to replace it or its assets.')
            validate_tag(version, publication_sha, tag)
            validate_release_metadata(release, version, publication_sha)
            continue
        if release["draft"]:
            continue
        if not release["published_at"]:
            raise ValueError(f'Release "{name}" has no publication time.')
        if "-horse." not in name:
            continue
        # Count older v-prefixed fork releases too, without permitting new v-prefixed tags.
        previous = fork_counter(name.removeprefix("v"))
        if counter <= previous:
            raise ValueError(f'The fork counter of "{version}" must exceed published release "{name}" regardless of its upstream version.')


def validate_tree(proposed_tree, main_tree):
    if not TREE_ID.fullmatch(proposed_tree) or not TREE_ID.fullmatch(main_tree):
        raise ValueError("Both tree IDs must be full Git SHA-1 tree IDs.")
    if proposed_tree != main_tree:
        raise ValueError("The proposed release tree must exactly match current origin/main.")


def validate_proposal_trees(head_tree, merge_tree, main_tree):
    validate_tree(head_tree, main_tree)
    validate_tree(merge_tree, main_tree)


def validate_main_snapshot(proposed_tree, history):
    if not TREE_ID.fullmatch(proposed_tree):
        raise ValueError("The landed tree must be a full Git SHA-1 tree ID.")
    lines = history.removesuffix("\n").split("\n")
    snapshots = {}
    for line in lines:
        if re.fullmatch(r"[0-9a-f]{40} [0-9a-f]{40}", line, re.ASCII) is None:
            raise ValueError("Main history must contain full commit/tree SHA-1 pairs separated by one space.")
        commit, tree = line.split(" ")
        if commit in snapshots:
            raise ValueError("Main history must not repeat commit IDs.")
        snapshots[commit] = tree
    for commit, tree in snapshots.items():
        if tree == proposed_tree:
            return commit
    raise ValueError("The landed release tree must exactly match a reachable origin/main snapshot.")


def merged_release_title(pulls, repository, sha):
    if not TREE_ID.fullmatch(sha):
        raise ValueError("Publication requires a full Git SHA-1 commit ID.")
    matches = [
        pull for pull in pulls
        if pull["merged_at"] is not None
        and pull["merge_commit_sha"] == sha
        and pull["base"]["ref"] == "release"
        and pull["base"]["repo"]["full_name"] == repository
    ]
    if len(matches) != 1:
        raise ValueError("The triggering commit must be the exact merge commit of one release pull request in this repository.")
    return matches[0]["title"]


def validate_archives(directory, version):
    expected = {
        f"litmus-{version}-{platform}.zip": binary
        for platform, binary in ARCHIVE_BINARIES.items()
    }
    if {path.name for path in directory.iterdir()} != expected.keys():
        raise ValueError("Publication requires exactly the four versioned platform ZIP archives.")
    for name, binary in expected.items():
        path = directory / name
        if not path.is_file() or path.is_symlink():
            raise ValueError(f'Archive "{name}" must be a regular file.')
        with zipfile.ZipFile(path) as archive:
            if archive.namelist() != [binary] or archive.getinfo(binary).file_size == 0:
                raise ValueError(f'Archive "{name}" must contain only the nonempty binary "{binary}" at its root.')
            if archive.testzip() is not None:
                raise ValueError(f'Archive "{name}" failed its CRC check.')


def read_versions(root):
    version = (root / "VERSION").read_text(encoding="utf-8").strip()
    manifest = tomllib.loads((root / "cli/Cargo.toml").read_text(encoding="utf-8"))
    lock = tomllib.loads((root / "cli/Cargo.lock").read_text(encoding="utf-8"))
    validate_versions(version, manifest, lock)
    return version


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--releases", type=Path, required=True)
    parser.add_argument("--proposed-tree", required=True)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--main-tree")
    source.add_argument("--main-history", type=Path)
    parser.add_argument("--merge-tree")
    parser.add_argument("--tag", type=Path, required=True)
    title = parser.add_mutually_exclusive_group(required=True)
    title.add_argument("--title")
    title.add_argument("--pulls", type=Path)
    parser.add_argument("--repository")
    parser.add_argument("--sha")
    parser.add_argument("--archives", type=Path)
    args = parser.parse_args(argv)
    try:
        version = read_versions(args.root)
        title = args.title
        tag = json.loads(args.tag.read_text(encoding="utf-8"))
        if args.pulls is not None:
            if not args.repository or not args.sha:
                raise ValueError("Publication requires the repository and exact triggering SHA.")
            pulls = flatten_pages(json.loads(args.pulls.read_text(encoding="utf-8")))
            title = merged_release_title(pulls, args.repository, args.sha)
            if tag is not None:
                validate_tag(version, args.sha, tag)
            if args.main_history is None:
                raise ValueError("Publication validation requires --main-history from origin/main.")
            source_commit = validate_main_snapshot(
                args.proposed_tree, args.main_history.read_text(encoding="utf-8")
            )
            print(f'Matched origin/main source commit "{source_commit}".', file=sys.stderr)
        else:
            if args.main_tree is None:
                raise ValueError("Proposal validation requires --main-tree for current origin/main.")
            if tag is not None:
                raise ValueError("The proposed version already has a tag. Choose an unused version.")
            if args.merge_tree is None:
                raise ValueError("Proposal validation requires --merge-tree.")
            validate_proposal_trees(args.proposed_tree, args.merge_tree, args.main_tree)
        validate_title(title, version)
        releases = flatten_pages(json.loads(args.releases.read_text(encoding="utf-8")))
        validate_history(version, releases, publication_sha=args.sha if args.pulls is not None else None, tag=tag)
        if args.archives is not None:
            validate_archives(args.archives, version)
    except (KeyError, OSError, TypeError, ValueError, zipfile.BadZipFile) as error:
        parser.exit(1, f"Release contract refused publication. {error}\n")
    print(version)


if __name__ == "__main__":
    main()
