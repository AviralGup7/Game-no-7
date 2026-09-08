#!/usr/bin/env python3
"""Offline asset sanity checks; complements, but does not replace, Godot import.

Checks the checksum lock, glTF/GLB dependencies, rig/animation availability,
PNG chunk integrity, audio containers, fonts, and the game-specific asset map.
Run: python3 tool/validate_assets.py
"""
from __future__ import annotations

import base64
from collections import Counter
import json
from pathlib import Path
import re
import struct
import sys
import urllib.parse
import wave
import zlib

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from scripts.download_assets import load_manifest, verification_problem  # noqa: E402


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def gltf_document(path: Path) -> tuple[dict, bytes]:
    data = path.read_bytes()
    if path.suffix == ".gltf":
        return json.loads(data), b""
    require(len(data) >= 20, "truncated GLB header")
    magic, version, length = struct.unpack_from("<4sII", data)
    require(magic == b"glTF" and version == 2 and length == len(data), "invalid GLB v2 header/length")
    chunks = []
    offset = 12
    while offset < length:
        require(offset + 8 <= length, "truncated GLB chunk header")
        size, kind = struct.unpack_from("<II", data, offset)
        offset += 8
        require(size % 4 == 0 and offset + size <= length, "invalid GLB chunk extent/alignment")
        chunks.append((kind, data[offset:offset + size]))
        offset += size
    require(bool(chunks) and chunks[0][0] == 0x4E4F534A, "GLB must start with JSON")
    binary = next((chunk for kind, chunk in chunks if kind == 0x004E4942), b"")
    return json.loads(chunks[0][1]), binary


def check_model(path: Path, approved: set[Path]) -> dict:
    doc, binary = gltf_document(path)
    require(doc.get("asset", {}).get("version") == "2.0", "not glTF 2.0")
    require(bool(doc.get("meshes")), "model has no meshes")
    require(bool(doc.get("scenes")), "model has no scene")

    def external(uri: str) -> bytes:
        if uri.startswith("data:"):
            header, encoded = uri.split(",", 1)
            require(header.endswith(";base64"), "unsupported embedded URI encoding")
            return base64.b64decode(encoded, validate=True)
        parsed = urllib.parse.urlsplit(uri)
        require(not parsed.scheme and not parsed.netloc and not parsed.query and not parsed.fragment,
                "model depends on a remote/unapproved URI")
        dependency = (path.parent / urllib.parse.unquote(parsed.path)).resolve()
        require(dependency in approved, f"unapproved/missing dependency: {uri}")
        return dependency.read_bytes()

    buffers = []
    for buffer in doc.get("buffers", []):
        content = external(buffer["uri"]) if "uri" in buffer else binary
        require(len(content) >= buffer["byteLength"], "model buffer is truncated")
        buffers.append(content)
    views = doc.get("bufferViews", [])
    for view in views:
        require(0 <= view["buffer"] < len(buffers), "invalid bufferView buffer index")
        offset = view.get("byteOffset", 0)
        require(offset >= 0 and view["byteLength"] > 0
                and offset + view["byteLength"] <= len(buffers[view["buffer"]]), "bufferView out of bounds")
    for image in doc.get("images", []):
        if "uri" in image:
            content = external(image["uri"])
        else:
            require(0 <= image.get("bufferView", -1) < len(views), "invalid embedded texture view")
            view = views[image["bufferView"]]
            start = view.get("byteOffset", 0)
            content = buffers[view["buffer"]][start:start + view["byteLength"]]
        require(content.startswith(b"\x89PNG\r\n\x1a\n"), "expected a PNG model texture")
    for mesh in doc["meshes"]:
        require(bool(mesh.get("primitives")), "empty mesh")
        for primitive in mesh["primitives"]:
            require("POSITION" in primitive.get("attributes", {}), "mesh has no vertex positions")
    for skin in doc.get("skins", []):
        require(bool(skin.get("joints")), "empty character rig")
        require(all(0 <= joint < len(doc.get("nodes", [])) for joint in skin["joints"]), "invalid rig joint")
    for animation in doc.get("animations", []):
        require(bool(animation.get("channels")) and bool(animation.get("samplers")), "empty animation")
    return doc


def check_png(path: Path) -> None:
    data = path.read_bytes()
    require(data.startswith(b"\x89PNG\r\n\x1a\n"), "invalid PNG signature")
    offset = 8
    kinds = []
    while offset < len(data):
        require(offset + 12 <= len(data), "truncated PNG chunk")
        length = struct.unpack_from(">I", data, offset)[0]
        end = offset + 8 + length
        require(end + 4 <= len(data), "truncated PNG payload")
        kind = data[offset + 4:offset + 8]
        crc = struct.unpack_from(">I", data, end)[0]
        require(zlib.crc32(data[offset + 4:end]) == crc, "PNG CRC mismatch")
        if kind == b"IHDR":
            width, height = struct.unpack_from(">II", data, offset + 8)
            require(0 < width <= 4096 and 0 < height <= 4096, "invalid/oversized mobile texture")
        kinds.append(kind)
        offset = end + 4
    require(bool(kinds) and kinds[0] == b"IHDR" and kinds[-1] == b"IEND" and b"IDAT" in kinds,
            "missing PNG image chunks")


def ogg_info(path: Path) -> dict:
    data = path.read_bytes()
    offset = 0
    sample_rate = 0
    channels = 0
    samples = 0
    while offset < len(data):
        require(offset + 27 <= len(data) and data[offset:offset + 5] == b"OggS\x00", "invalid Ogg page")
        granule = struct.unpack_from("<Q", data, offset + 6)[0]
        if granule != (1 << 64) - 1:
            samples = max(samples, granule)
        count = data[offset + 26]
        start = offset + 27 + count
        require(start <= len(data), "truncated Ogg lacing table")
        end = start + sum(data[offset + 27:start])
        require(end <= len(data), "truncated Ogg page body")
        if offset == 0:
            packet = data[start:end]
            require(len(packet) >= 30 and packet.startswith(b"\x01vorbis"), "expected Ogg Vorbis audio")
            channels = packet[11]
            sample_rate = struct.unpack_from("<I", packet, 12)[0]
        offset = end
    require(channels in (1, 2) and sample_rate > 0 and samples > 0, "empty/invalid audio stream")
    return {"channels": channels, "sample_rate": sample_rate, "duration_seconds": samples / sample_rate}


def check_font(path: Path) -> None:
    data = path.read_bytes()
    require(len(data) >= 12 and data[:4] in (b"\x00\x01\x00\x00", b"OTTO"), "invalid OpenType/TrueType font")
    table_count = struct.unpack_from(">H", data, 4)[0]
    require(len(data) >= 12 + 16 * table_count, "truncated font directory")
    names = set()
    for index in range(table_count):
        name, _checksum, offset, length = struct.unpack_from(">4sIII", data, 12 + index * 16)
        require(offset + length <= len(data), "truncated font table")
        names.add(name)
    require({b"cmap", b"name", b"head"} <= names, "font missing required tables")


def content_ids(category: str, field: str) -> set[str]:
    ids = set()
    for path in (ROOT / "data" / category).glob("*.tres"):
        match = re.search(r'^' + re.escape(field) + r' = &"([^"\n]+)"',
                          path.read_text(), re.MULTILINE)
        require(match is not None, f"missing {field} in {path.name}")
        require(match[1] not in ids, f"duplicate {field}: {match[1]}")
        ids.add(match[1])
    require(bool(ids), f"no content definitions for {category}")
    return ids


def check_asset_inventory(approved: set[Path]) -> None:
    # Raw downloads must never silently escape provenance/hash validation.
    raw_suffixes = {".glb", ".gltf", ".bin", ".png", ".ttf", ".ogg", ".wav"}
    for path in (ROOT / "assets").rglob("*"):
        if path.is_file() and path.suffix.lower() in raw_suffixes:
            require(path.resolve() in approved, f"untracked source asset: {path.relative_to(ROOT)}")
    for folder in ("scenes", "data", "assets/materials"):
        for path in (ROOT / folder).rglob("*"):
            if path.suffix not in (".tscn", ".tres"):
                continue
            for relative in re.findall(r'path="res://(assets/[^"\n]+)"', path.read_text()):
                asset = ROOT / relative
                require(asset.is_file(), f"missing runtime asset: {relative}")
                require(asset.suffix == ".tres" or asset.resolve() in approved,
                        f"runtime reference lacks provenance: {relative}")


def check_catalog(catalog: dict, approved: set[Path], models: dict[str, dict]) -> None:
    def check_references(value):
        if isinstance(value, dict):
            for nested in value.values():
                check_references(nested)
        elif isinstance(value, list):
            for nested in value:
                check_references(nested)
        elif isinstance(value, str) and value.startswith("assets/"):
            require((ROOT / value).resolve() in approved, f"catalog references an unapproved file: {value}")
    check_references(catalog)
    enemy_ids = content_ids("enemies", "archetype_id")
    require(set(catalog["characters"]) == enemy_ids | {"player"}, "missing character role")
    for category, field in (("weapons", "weapon_id"), ("skills", "skill_id"),
                            ("pickups", "pickup_id"), ("arenas", "arena_id")):
        ids = content_ids(category, field)
        require(set(catalog["gameplay_" + category]) == ids, f"missing {category} role")
    for role, character in catalog["characters"].items():
        doc = models[character["model"]]
        require(bool(doc.get("skins")), f"{role}: character is not rigged")
        animations = {a.get("name") for a in doc.get("animations", [])}
        require(set(character["animations"].values()) <= animations, f"{role}: requested animation clip missing")
        require(len(doc["animations"]) == character["animation_count"], f"{role}: stale animation inventory")
        bones = {doc["nodes"][j].get("name") for skin in doc["skins"] for j in skin["joints"]}
        require(set(character.get("required_bones", [])) <= bones,
                f"{role}: required attachment joints missing")
    upgrade_ids = {p.stem for p in (ROOT / "data/upgrades").glob("*.tres")}
    require(set(catalog["upgrade_icons"]) == upgrade_ids, "upgrade icon map must cover every current upgrade")
    referenced_cues = set()
    for path in (ROOT / "scripts").rglob("*.gd"):
        referenced_cues.update(re.findall(r'play_sfx\(&"([^\"]+)"', path.read_text()))
    referenced_cues.update({"arena_menu", "arena_gameplay", "wave_started", "game_over"})
    require(referenced_cues <= catalog["audio_cues"].keys(), "catalog is missing a gameplay audio cue")


def main() -> int:
    problems = []
    models = {}
    counts = Counter()
    try:
        manifest = load_manifest()
        approved = {(ROOT / e["path"]).resolve() for e in manifest["files"]}
        for entry in manifest["files"]:
            try:
                problem = verification_problem(entry)
                require(not problem, problem)
                path = ROOT / entry["path"]
                suffix = path.suffix.lower()
                counts[suffix] += 1
                if suffix in (".glb", ".gltf"):
                    models[entry["path"]] = check_model(path, approved)
                elif suffix == ".png":
                    check_png(path)
                elif suffix == ".ogg":
                    ogg_info(path)
                elif suffix == ".wav":
                    with wave.open(str(path), "rb") as audio:
                        require(audio.getnframes() > 0 and audio.getnchannels() in (1, 2), "empty/invalid PCM audio")
                        require(audio.getcomptype() == "NONE", "expected PCM WAV")
                        require(len(audio.readframes(audio.getnframes())) == audio.getnframes()
                                * audio.getnchannels() * audio.getsampwidth(), "truncated PCM audio")
                elif suffix == ".ttf":
                    check_font(path)
            except (OSError, ValueError, KeyError, IndexError, struct.error, wave.Error) as exc:
                problems.append(f"{entry['path']}: {exc}")
        check_asset_inventory(approved)
        catalog = json.loads((ROOT / "assets/catalog.json").read_text())
        check_catalog(catalog, approved, models)
    except (OSError, ValueError, TypeError, KeyError) as exc:
        problems.append(str(exc))
    if problems:
        print(f"Asset validation: {len(problems)} problem(s)")
        for problem in problems:
            print(" - " + problem)
        return 1
    print(f"Assets OK: {len(models)} 3D models, {counts['.png']} PNGs, "
          f"{counts['.ogg'] + counts['.wav']} audio files, {counts['.ttf']} fonts; "
          "all dependencies, character animations, upgrade icons and cue mappings present.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
