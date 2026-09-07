#!/usr/bin/env python3
"""Restore and verify the reviewed assets locked in assets/manifest.json.

No dependencies, credentials, ZIP extraction, floating revisions, or arbitrary URL
arguments. Normal runs fetch missing files and verify existing ones. --verify is
strictly offline/read-only; --repair explicitly allows replacing damaged files.
All successful downloads are size/SHA-256 checked before an atomic installation.

Licence review: THIRD_PARTY_ASSETS.md, AUDIO_MANIFEST.md, ASSET_LICENSES/.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import sys
import tempfile
import urllib.parse
import urllib.request

REPO_ROOT = Path(__file__).resolve().parents[1]
MANIFEST_PATH = REPO_ROOT / "assets/manifest.json"
MAX_FILE_BYTES = 64 * 1024 * 1024
ALLOWED_SUFFIXES = {".glb", ".gltf", ".bin", ".png", ".ttf", ".ogg", ".wav", ".txt", ".md"}
HEX40 = re.compile(r"[0-9a-f]{40}\Z")
HEX64 = re.compile(r"[0-9a-f]{64}\Z")
REPOSITORY = re.compile(r"https://github\.com/([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)\Z")


def destination_for(relative: str, root: Path = REPO_ROOT) -> Path:
    """Reject noncanonical paths, traversal, and symlinks before any IO writes."""
    if not isinstance(relative, str) or "\\" in relative:
        raise ValueError(f"Invalid asset destination: {relative!r}")
    path = PurePosixPath(relative)
    if (path.is_absolute() or len(path.parts) < 2 or ".." in path.parts
            or str(path) != relative or path.parts[0] not in {"assets", "ASSET_LICENSES"}
            or path.suffix.lower() not in ALLOWED_SUFFIXES):
        raise ValueError(f"Unsafe asset destination: {relative!r}")
    root = root.resolve()
    dest = root
    for part in path.parts:
        dest /= part
        if dest.is_symlink():
            raise ValueError(f"Symlink in asset destination: {relative}")
    if not dest.resolve().is_relative_to(root):
        raise ValueError(f"Asset destination escapes repository: {relative}")
    return dest


def load_manifest(path: Path = MANIFEST_PATH, root: Path = REPO_ROOT) -> dict:
    """A malformed/empty manifest must never turn verification into a false pass."""
    manifest = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(manifest, dict) or manifest.get("schema_version") != 1:
        raise ValueError("Unsupported asset manifest schema")
    sources = manifest.get("sources")
    entries = manifest.get("files")
    if not isinstance(sources, dict) or not sources or not isinstance(entries, list) or not entries:
        raise ValueError("Manifest must contain reviewed sources and files")
    for pack, source in sources.items():
        if not isinstance(source, dict):
            raise ValueError(f"Invalid source: {pack}")
        if source.get("license") not in {"CC0-1.0", "OFL-1.1"}:
            raise ValueError(f"Unreviewed licence for {pack}")
        if not REPOSITORY.fullmatch(source.get("download_repository", "")):
            raise ValueError(f"Invalid download repository for {pack}")
        if not HEX40.fullmatch(source.get("revision", "")):
            raise ValueError(f"Source revision must be an immutable commit: {pack}")
        for field in ("name", "creator", "source_url", "license_url", "attribution", "reviewed_on"):
            if not isinstance(source.get(field), str) or not source[field]:
                raise ValueError(f"Source {pack} missing {field}")
        for field in ("commercial_use", "compiled_redistribution", "modification_permitted"):
            if source.get(field) is not True:
                raise ValueError(f"Source {pack} lacks reviewed {field} permission")
        destination_for(source.get("license_file"), root)

    seen: dict[str, str] = {}
    for entry in entries:
        if not isinstance(entry, dict) or entry.get("pack") not in sources:
            raise ValueError("File has no reviewed source")
        relative = entry.get("path")
        destination_for(relative, root)
        if relative in seen:
            raise ValueError(f"Duplicate asset destination: {relative}")
        seen[relative] = entry["pack"]
        if not isinstance(entry.get("sha256"), str) or not HEX64.fullmatch(entry["sha256"]):
            raise ValueError(f"Missing/invalid SHA-256: {relative}")
        if not isinstance(entry.get("git_blob_sha1"), str) or not HEX40.fullmatch(entry["git_blob_sha1"]):
            raise ValueError(f"Missing/invalid source blob hash: {relative}")
        if type(entry.get("bytes")) is not int or not 0 < entry["bytes"] <= MAX_FILE_BYTES:
            raise ValueError(f"Invalid/oversized asset length: {relative}")
        source_path = entry.get("source_path", "")
        if (not isinstance(source_path, str) or not source_path or "\\" in source_path
                or PurePosixPath(source_path).is_absolute() or ".." in PurePosixPath(source_path).parts):
            raise ValueError(f"Invalid upstream file path: {relative}")
        source = sources[entry["pack"]]
        repo = REPOSITORY.fullmatch(source["download_repository"]).group(1)
        expected_url = (f"https://api.github.com/repos/{repo}/contents/"
                        f"{urllib.parse.quote(source_path)}?ref={source['revision']}")
        if entry.get("url") != expected_url:
            raise ValueError(f"Download URL must match the reviewed pinned source: {relative}")
        for field in ("purpose", "downloaded_on"):
            if not isinstance(entry.get(field), str) or not entry[field]:
                raise ValueError(f"File {relative} missing {field}")
    for pack, source in sources.items():
        if seen.get(source["license_file"]) != pack:
            raise ValueError(f"Source {pack} must include its own checksum-locked licence notice")
    return manifest


def sha256_of(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def verification_problem(entry: dict, root: Path = REPO_ROOT) -> str:
    dest = destination_for(entry["path"], root)
    if not dest.is_file():
        return "missing file"
    if dest.stat().st_size != entry["bytes"]:
        return "byte length mismatch"
    if sha256_of(dest) != entry["sha256"]:
        return "SHA-256 mismatch"
    return ""


class ApprovedRedirects(urllib.request.HTTPRedirectHandler):
    """Do not allow HTTPS downgrades or unrelated download hosts on redirect."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        url = urllib.parse.urlsplit(newurl)
        if (url.scheme != "https" or url.hostname not in {"api.github.com", "raw.githubusercontent.com"}
                or url.username or url.password or url.port not in (None, 443)):
            raise ValueError("Asset server redirected to an unapproved download host")
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def open_download(request: urllib.request.Request):
    return urllib.request.build_opener(ApprovedRedirects()).open(request, timeout=60)


def install_download(entry: dict, root: Path = REPO_ROOT) -> None:
    dest = destination_for(entry["path"], root)
    dest.parent.mkdir(parents=True, exist_ok=True)
    temporary: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(dir=dest.parent, prefix=".asset-", suffix=".tmp", delete=False) as out:
            temporary = Path(out.name)
            request = urllib.request.Request(entry["url"], headers={
                "User-Agent": "LastStandArena-assets/1.0",
                "Accept": "application/vnd.github.raw+json",
            })
            digest = hashlib.sha256()
            length = 0
            with open_download(request) as response:
                for chunk in iter(lambda: response.read(65536), b""):
                    length += len(chunk)
                    if length > entry["bytes"]:
                        raise ValueError("response exceeds approved byte length")
                    digest.update(chunk)
                    out.write(chunk)
            if length != entry["bytes"]:
                raise ValueError(f"truncated response: {length} of {entry['bytes']} bytes")
            if digest.hexdigest() != entry["sha256"]:
                raise ValueError("downloaded SHA-256 does not match the approved file")
        os.replace(temporary, dest)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def fetch(entry: dict, verify_only: bool = False, repair: bool = False, root: Path = REPO_ROOT) -> bool:
    try:
        problem = verification_problem(entry, root)
        if not problem:
            return True
        dest = destination_for(entry["path"], root)
        if verify_only or (dest.exists() and not repair):
            hint = " (use --repair to restore)" if dest.exists() else " (run without --verify to download)"
            print(f"ERROR {entry['path']}: {problem}{hint}", file=sys.stderr)
            return False
        print(f"Downloading {entry['path']} ({entry['bytes']} bytes)")
        install_download(entry, root)
        print(f"OK {entry['path']}")
        return True
    except (OSError, ValueError) as exc:
        print(f"ERROR {entry['path']}: {exc}", file=sys.stderr)
        return False


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--verify", action="store_true", help="offline read-only size and checksum verification")
    mode.add_argument("--repair", action="store_true", help="also restore damaged approved files")
    mode.add_argument("--list", action="store_true", help="list approved asset packs without writing/downloading")
    parser.add_argument("--pack", action="append", help="select a pack id (repeatable; defaults to all packs)")
    args = parser.parse_args()
    try:
        manifest = load_manifest()
    except (OSError, ValueError, TypeError) as exc:
        print(f"ERROR loading asset manifest: {exc}", file=sys.stderr)
        return 1
    unknown = set(args.pack or []) - manifest["sources"].keys()
    if unknown:
        parser.error("unknown pack(s): " + ", ".join(sorted(unknown)))
    entries = [e for e in manifest["files"] if not args.pack or e["pack"] in args.pack]
    if args.list:
        for pack, source in manifest["sources"].items():
            selected = [e for e in entries if e["pack"] == pack]
            if selected:
                size = sum(e["bytes"] for e in selected) / 1048576
                print(f"{pack:20} {len(selected):3} files  {size:6.2f} MiB  {source['license']:8}  {source['name']}")
        return 0
    failed = sum(not fetch(e, args.verify, args.repair) for e in entries)
    total_mib = sum(e["bytes"] for e in entries) / 1048576
    print(f"Assets: {len(entries) - failed}/{len(entries)} verified, {failed} failed ({total_mib:.2f} MiB approved).")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
