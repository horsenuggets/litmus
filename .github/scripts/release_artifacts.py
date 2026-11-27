"""Admit immutable release artifacts from every attempt of the exact workflow run."""

import argparse
import json
from datetime import UTC, datetime
from pathlib import Path

from release_contract import TREE_ID

SYSTEMS = ("linux", "macos", "windows")


def admit_artifacts(run, pages, run_id, sha, now):
    if type(run_id) is not int or run_id <= 0 or not TREE_ID.fullmatch(sha):
        raise ValueError("Artifact admission requires a positive run ID and full triggering SHA.")
    if (not isinstance(run, dict) or type(run.get("id")) is not int
            or run["id"] != run_id or run.get("head_sha") != sha):
        raise ValueError("The workflow run must have the exact current run ID and triggering SHA.")
    if not isinstance(pages, list) or not pages:
        raise ValueError("Artifact metadata must include every paginated API response.")
    artifacts = []
    counts = []
    for page in pages:
        if (not isinstance(page, dict) or type(page.get("total_count")) is not int
                or not isinstance(page.get("artifacts"), list)):
            raise ValueError("Artifact pages must contain a total count and artifact list.")
        artifacts.extend(page["artifacts"])
        counts.append(page["total_count"])
    if any(count != len(artifacts) for count in counts):
        raise ValueError("Artifact metadata must include all artifacts with a consistent total count.")
    admitted = {}
    ids = set()
    for artifact in artifacts:
        if not isinstance(artifact, dict) or not isinstance(artifact.get("name"), str):
            raise ValueError("Each artifact must have a name.")
        name = artifact["name"]
        if not name.startswith("release-"):
            continue
        system = name.removeprefix("release-")
        if system not in SYSTEMS:
            raise ValueError(f'Unexpected release artifact "{name}".')
        if system in admitted:
            raise ValueError(f'Duplicate artifact name "{name}". Refusing to choose or replace it.')
        artifact_id = artifact.get("id")
        if type(artifact_id) is not int or artifact_id <= 0 or artifact_id in ids:
            raise ValueError("Release artifacts must have unique positive integer IDs.")
        identity = artifact.get("workflow_run")
        if (not isinstance(identity, dict) or type(identity.get("id")) is not int
                or identity["id"] != run_id or identity.get("head_sha") != sha):
            raise ValueError(f'Artifact "{name}" does not belong to the exact workflow run and SHA.')
        expires_at = artifact.get("expires_at")
        if (not isinstance(expires_at, str)
                or not expires_at.endswith("Z")
                or datetime.fromisoformat(expires_at) <= now
                or artifact.get("expired") is not False):
            raise ValueError(f'Artifact "{name}" is expired or has invalid expiry metadata. Refusing to rebuild it.')
        admitted[system] = artifact_id
        ids.add(artifact_id)
    return admitted


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", type=Path, required=True)
    parser.add_argument("--artifacts", type=Path, required=True)
    parser.add_argument("--run-id", type=int, required=True)
    parser.add_argument("--sha", required=True)
    selection = parser.add_mutually_exclusive_group(required=True)
    selection.add_argument("--system", choices=SYSTEMS)
    selection.add_argument("--all", action="store_true")
    args = parser.parse_args(argv)
    try:
        admitted = admit_artifacts(
            json.loads(args.run.read_text(encoding="utf-8")),
            json.loads(args.artifacts.read_text(encoding="utf-8")),
            args.run_id, args.sha, datetime.now(UTC),
        )
        if args.all:
            if set(admitted) != set(SYSTEMS):
                raise ValueError("Publication requires original artifacts for all three systems.")
            print(",".join(str(admitted[system]) for system in SYSTEMS))
        else:
            print(admitted.get(args.system, "missing"))
    except (KeyError, OSError, TypeError, ValueError) as error:
        parser.exit(1, f"Release artifact admission refused. {error}\n")


if __name__ == "__main__":
    main()
