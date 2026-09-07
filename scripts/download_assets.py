#!/usr/bin/env python3
"""Approved-asset downloader for "Last Stand: Arena".

Only downloads URLs that are explicitly approved in this file's APPROVED list
(after licence review recorded in THIRD_PARTY_ASSETS.md / AUDIO_MANIFEST.md).
It never follows arbitrary URLs from search results. After approved assets are
stored, the build is fully reproducible offline — the manifest keeps records.

Usage:
    python3 scripts/download_assets.py            # download all approved, missing assets
    python3 scripts/download_assets.py --verify   # verify already-downloaded files only

Exits non-zero when an approved asset cannot be fetched.
"""
from __future__ import annotations

import argparse
import hashlib
import os
import sys
import urllib.request

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Each entry: {
#   "url": "https://...",          approved + licence-checked
#   "dest": "assets/...",          relative to repo root
#   "sha256": "hex...",            optional checksum
#   "note": "licence/manifest id"
# }
APPROVED: list[dict] = [
    # Populated after each asset is licence-reviewed. Example only; do not ship
    # an asset here without its THIRD_PARTY_ASSETS.md / AUDIO_MANIFEST.md record.
    # {
    #   "url": "https://example.com/asset.glb",
    #   "dest": "assets/characters/hero.glb",
    #   "sha256": "",
    #   "note": "see THIRD_PARTY_ASSETS.md",
    # },
]

_KNOWN_GOOD_SHA = None  # placeholder to avoid unused-var lint noise


def sha256_of(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 16), b""):
            h.update(chunk)
    return h.hexdigest()


def fetch(entry: dict, verify_only: bool) -> bool:
    dest = os.path.join(REPO_ROOT, entry["dest"])
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    if verify_only or os.path.exists(dest):
        if not os.path.exists(dest):
            return False
        if entry.get("sha256"):
            return sha256_of(dest) == entry["sha256"]
        return os.path.getsize(dest) > 0
    print(f"Downloading {entry['note']} -> {entry['dest']}")
    try:
        req = urllib.request.Request(entry["url"], headers={"User-Agent": "LastStandArena-assets"})
        with urllib.request.urlopen(req, timeout=60) as resp:
            data = resp.read()
        if not data:
            raise OSError("empty download")
        with open(dest, "wb") as f:
            f.write(data)
    except Exception as exc:  # noqa: BLE001
        print(f"ERROR fetching {entry['url']}: {exc}")
        return False
    if entry.get("sha256") and sha256_of(dest) != entry["sha256"]:
        print(f"ERROR checksum mismatch for {entry['dest']}")
        return False
    print(f"OK {entry['dest']} ({os.path.getsize(dest)} bytes)")
    return True


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--verify", action="store_true", help="verify existing downloads")
    args = ap.parse_args()
    if not APPROVED:
        print("No approved assets pending download (offline build is ready).")
        return 0
    ok = True
    for entry in APPROVED:
        ok = fetch(entry, args.verify) and ok
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
