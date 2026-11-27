"""Resume an exact-SHA release without replacing tags, releases or assets."""

import argparse
import json
import re
import subprocess
import zipfile
from pathlib import Path
from urllib.parse import quote

from release_contract import (
    TREE_ID,
    flatten_pages,
    fork_counter,
    read_versions,
    validate_archives,
    validate_release_metadata,
    validate_tag,
)


class GHError(RuntimeError):
    pass


def missing_assets(assets, expected, *, draft):
    """Decide which uploads are safe, without performing any I/O."""
    names = [asset["name"] for asset in assets]
    if len(names) != len(set(names)) or set(names) - expected.keys():
        raise ValueError("The release contains duplicate or unexpected assets.")
    if any(asset["state"] != "uploaded" for asset in assets):
        raise ValueError("The release contains an incomplete asset upload.")
    missing = sorted(expected.keys() - set(names))
    if missing and not draft:
        raise ValueError("The published release is missing expected assets and cannot be changed.")
    return missing


def verify_assets(gh, release, expected):
    assets = gh.get_assets(release["id"])
    missing = missing_assets(assets, expected, draft=release["draft"])
    for asset in assets:
        if gh.download_asset(asset["id"]) != expected[asset["name"]]:
            raise ValueError(f'Existing asset "{asset["name"]}" differs from this run. Refusing to overwrite it.')
    return missing


def require_tag(gh, version, sha):
    validate_tag(version, sha, gh.get_tag(version))


def ensure_tag(gh, version, sha):
    tag = gh.get_tag(version)
    if tag is not None:
        validate_tag(version, sha, tag)
        return
    try:
        # Atomic creation never updates an existing ref. A timeout may hide success.
        gh.create_tag(version, sha)
    except GHError:
        tag = gh.get_tag(version)
        if tag is None:
            raise
        validate_tag(version, sha, tag)
    require_tag(gh, version, sha)


def checked_release(gh, version, sha, release_id):
    release = gh.get_release(version)
    if release is None or release["id"] != release_id:
        raise ValueError("The verified release disappeared or was replaced. Refusing to continue.")
    validate_release_metadata(release, version, sha)
    return release


def publish_release(gh, version, sha, directory):
    # The workflow already checked source/provenance/history. Keep archive validation
    # authoritative here too, before the first possible remote write.
    fork_counter(version)
    if not TREE_ID.fullmatch(sha):
        raise ValueError("Publication requires a full Git SHA-1 commit ID.")
    validate_archives(directory, version)
    expected = {path.name: path.read_bytes() for path in directory.iterdir()}
    tag = gh.get_tag(version)
    if tag is not None:
        validate_tag(version, sha, tag)
    release = gh.get_release(version)
    if release is not None:
        validate_release_metadata(release, version, sha)
        validate_tag(version, sha, tag)
        verify_assets(gh, release, expected)
    else:
        ensure_tag(gh, version, sha)
    if release is None:
        require_tag(gh, version, sha)
        try:
            gh.create_draft(version, sha)
        except GHError:
            # A racing create or a lost response is safe only if reinspection proves
            # the exact same metadata, tag and bytes. Other failures remain failures.
            release = gh.get_release(version)
            if release is None:
                raise
        release = gh.get_release(version)
        if release is None:
            raise ValueError("Draft creation did not produce the expected release.")
    release_id = release["id"]
    while True:
        release = checked_release(gh, version, sha, release_id)
        missing = verify_assets(gh, release, expected)
        latest = checked_release(gh, version, sha, release_id)
        if latest["draft"] != release["draft"]:
            continue
        require_tag(gh, version, sha)
        if not release["draft"]:
            return "Verified the published release. No changes were made."
        if not missing:
            # All four assets were downloaded and byte-compared, and the lightweight
            # tag was just rechecked. Never edit an already published release.
            gh.publish(release_id)
            final = checked_release(gh, version, sha, release_id)
            if final["draft"]:
                raise ValueError("The release is still a draft after publication.")
            verify_assets(gh, final, expected)
            require_tag(gh, version, sha)
            return "Published the verified release as non-prerelease."
        gh.upload_asset(release_id, directory / missing[0])


class GitHub:
    """The only subprocess/network boundary. Reads never interpret errors as absence."""

    def __init__(self, repository):
        self.repository = repository
        self.base = f"repos/{repository}"

    def run(self, args):
        result = subprocess.run(["gh", *args], capture_output=True, check=False)
        if result.returncode:
            raise GHError(result.stderr.decode("utf-8", errors="replace").strip())
        return result.stdout

    def pages(self, endpoint):
        return flatten_pages(json.loads(self.run(["api", endpoint, "--paginate", "--slurp"])))

    def get_tag(self, version):
        result = subprocess.run(
            ["gh", "api", f"{self.base}/git/ref/tags/{quote(version, safe='')}", "--include"],
            capture_output=True, check=False,
        )
        # Only an actual HTTP 404 is absence. Auth, rate-limit and transport errors
        # must not trigger a create. The header separator must not touch body bytes.
        header, separator, body = result.stdout.partition(b"\r\n\r\n")
        if not separator:
            header, separator, body = result.stdout.partition(b"\n\n")
        status = re.match(rb"HTTP/\S+\s+(\d{3})\b", header)
        if result.returncode:
            if status is not None and status[1] == b"404":
                return None
            raise GHError(result.stderr.decode("utf-8", errors="replace").strip())
        if status is None or not separator or status[1] != b"200":
            raise GHError("Tag inspection returned an unexpected HTTP response.")
        return json.loads(body)

    def create_tag(self, version, sha):
        self.run(["api", "--method", "POST", f"{self.base}/git/refs",
                  "-f", f"ref=refs/tags/{version}", "-f", f"sha={sha}"])

    def get_release(self, version):
        # Listing includes drafts and is paginated. The public tag endpoint alone
        # cannot reliably distinguish an absent release from a private draft.
        matches = [release for release in self.pages(f"{self.base}/releases?per_page=100")
                   if release["tag_name"] == version]
        if len(matches) > 1:
            raise ValueError("Multiple releases use the current version.")
        return matches[0] if matches else None

    def create_draft(self, version, sha):
        self.run(["release", "create", version, "--repo", self.repository,
                  "--verify-tag", "--draft", "--target", sha, "--title", version,
                  "--generate-notes", "--prerelease=false"])

    def get_assets(self, release_id):
        return self.pages(f"{self.base}/releases/{release_id}/assets?per_page=100")

    def download_asset(self, asset_id):
        return self.run(["api", f"{self.base}/releases/assets/{asset_id}",
                         "--header", "Accept: application/octet-stream"])

    def upload_asset(self, release_id, path):
        # The upload API rejects a duplicate name. No delete, PATCH or clobber path.
        self.run(["api", "--method", "POST",
                  f"https://uploads.github.com/{self.base}/releases/{release_id}/assets?name={quote(path.name, safe='')}",
                  "--header", "Content-Type: application/zip", "--input", str(path)])

    def publish(self, release_id):
        self.run(["api", "--method", "PATCH", f"{self.base}/releases/{release_id}",
                  "-F", "draft=false", "-F", "prerelease=false"])


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--repository", required=True)
    parser.add_argument("--sha", required=True)
    parser.add_argument("--archives", type=Path)
    parser.add_argument("--inspect-tag", action="store_true", help="Read-only tag inspection for the contract.")
    args = parser.parse_args(argv)
    try:
        version = read_versions(args.root)
        gh = GitHub(args.repository)
        if args.inspect_tag:
            print(json.dumps(gh.get_tag(version)))
        else:
            if args.archives is None:
                raise ValueError("Publication requires --archives.")
            print(publish_release(gh, version, args.sha, args.archives))
    except (GHError, KeyError, OSError, TypeError, ValueError, zipfile.BadZipFile) as error:
        parser.exit(1, f"Release publication refused. {error}\n")


if __name__ == "__main__":
    main()
