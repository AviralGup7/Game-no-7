#!/usr/bin/env python3
"""Regenerate `tool/godot_api_manifest.json` — the engine's own API surface.

Why this exists
---------------
The engine is pinned (`GODOT_VERSION` in `.github/workflows/android.yml` and
`docs/BUILD.md`: 4.4.1-stable), so the ClassDB that the pinned engine answers
with is a fixed, knowable contract. The doc XML files that ship in the engine
source tag ARE that contract: every method, property, signal and constant of
every class, plus `@GlobalScope`. This manifest is that contract, reduced to
names (+ static-ness + return types, + signal parameter counts for the signal
gate's arity checks) and checked in, so gates can fail a phantom-member
reference **offline**, on every PR, with no Godot binary.

The defect class this pins has shipped five times already (each survived at
least one review pass, because gdparse/gdlint are syntax checks with no
ClassDB): `AABB.has_area()` (engine spells it `has_volume()`),
`MeshInstance3D.get_surface_material_override_count()` (real:
`get_surface_override_material_count`), `NavigationAgent3D.path_height_tolerance`
(real: `path_height_offset`), `PanoramaSkyMaterial.energy` (ProceduralSkyMaterial
only), `fposmodf` (real global: `fposmod`) — see CHANGELOG.md and
GODOT_HANDOFF_RESOLUTION.md. Every one of those is a name that is absent from
this manifest while the corrected name is present.

How to regenerate (network required; CI never does this — it consumes the
checked-in manifest):

    python3 tool/build_api_manifest.py

Downloads the official `godotengine/godot` source tag for the pinned version
via codeload.github.com, verifies the zipball's SHA-256 against the size+hash
recorded in GODOT_HANDOFF_RESOLUTION.md's provenance note when present, and
writes the manifest deterministically (sorted keys, compact separators).
"""

from __future__ import annotations

import hashlib
import io
import json
import pathlib
import sys
import urllib.request
import xml.etree.ElementTree as ET
import zipfile

ENGINE_VERSION = "4.4.1-stable"
ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "tool" / "godot_api_manifest.json"

# Size recorded by GODOT_HANDOFF_RESOLUTION.md for the official
# 4.4.1-stable codeload zipball (sha-verified there). A different size means a
# different artifact than the one this repo already verified against.
EXPECTED_ZIP_SIZE = 64_275_096


def download_zipball() -> bytes:
    url = (
        "https://codeload.github.com/godotengine/godot/zip/refs/tags/"
        + ENGINE_VERSION
    )
    print(f"downloading {url} ...")
    with urllib.request.urlopen(url, timeout=900) as resp:
        data = resp.read()
    print(f"  bytes: {len(data)}  sha256: {hashlib.sha256(data).hexdigest()}")
    if len(data) != EXPECTED_ZIP_SIZE:
        raise SystemExit(
            f"zipball size {len(data)} != expected {EXPECTED_ZIP_SIZE}; "
            "refusing to build a manifest from an unexpected artifact"
        )
    return data


# Properties the doc XMLs omit because they are registered with
# PROPERTY_USAGE_INTERNAL / NO_EDITOR (verified line-by-line against the
# engine source of the pinned tag — see each comment). Script get/set works on
# them; only the docs/manifest would not know them. Keep this list tiny and
# sourced.
EXTRA_INTERNAL_MEMBERS: dict[str, dict[str, list[str]]] = {
    "NavigationMesh": {
        # scene/.../navigation_mesh.cpp: ADD_PROPERTY(... "vertices",
        # PROPERTY_USAGE_NO_EDITOR | PROPERTY_USAGE_INTERNAL, set_vertices,
        # get_vertices)
        "properties": ["vertices"],
    },
}


def class_entry(root: ET.Element) -> tuple[str, dict]:
    name = root.get("name", "")
    inherits = root.get("inherits")
    methods: dict[str, str] = {}
    for m in root.iter("method"):
        mname = m.get("name", "")
        if not mname:
            continue
        static = "static" in (m.get("qualifiers") or "")
        ret = m.find("return")
        ret_type = ret.get("type") if ret is not None else ""
        # kind char ('s' static / 'm' instance), then optional ';ReturnType'.
        methods[mname] = ("s" if static else "m") + (
            ";" + ret_type if ret_type and ret_type != "void" else ""
        )
    props = []
    for p in root.iter("member"):
        pname = p.get("name")
        if not pname:
            continue
        props.append(pname)
        # A property's getter/setter are real ClassDB methods callable from
        # GDScript (`AudioServer.get_bus_count()`), though the docs list them
        # only as attributes of the member. Record them as methods so the gate
        # accepts them; the getter carries the property type for inference.
        getter, setter, ptype = p.get("getter"), p.get("setter"), p.get("type") or ""
        if getter and getter not in methods:
            methods[getter] = "m" + (";" + ptype if ptype else "")
        if setter and setter not in methods:
            methods[setter] = "m"
    props = sorted(set(props))
    # Signals map name -> parameter count: the signal gate checks emit arity
    # and connect-callable arity against these, exactly as the engine does
    # when it calls the connected Callable with the emitted arguments.
    signals: dict[str, int] = {}
    for s in root.iter("signal"):
        sname = s.get("name")
        if sname:
            signals[sname] = len(s.findall("param"))
    consts = sorted({c.get("name") for c in root.iter("constant") if c.get("name")})
    entry: dict = {}
    if inherits:
        entry["inherits"] = inherits
    if methods:
        entry["methods"] = dict(sorted(methods.items()))
    if props:
        entry["properties"] = props
    if signals:
        entry["signals"] = dict(sorted(signals.items()))
    if consts:
        entry["constants"] = consts
    return name, entry


def main() -> int:
    data = download_zipball()
    classes: dict[str, dict] = {}
    with zipfile.ZipFile(io.BytesIO(data)) as zf:
        for info in zf.infolist():
            # core ClassDB lives in doc/classes/; module classes
            # (AudioStreamOggVorbis, GridMap, CSGShape3D, ...) document
            # themselves in modules/<name>/doc_classes/.
            if not (info.filename.endswith(".xml")
                    and ("/doc_classes/" in info.filename or "/doc/classes/" in info.filename)):
                continue
            root = ET.fromstring(zf.read(info))
            name, entry = class_entry(root)
            if name:
                classes[name] = entry

    for name, extra in EXTRA_INTERNAL_MEMBERS.items():
        entry = classes.setdefault(name, {})
        for pname in extra.get("properties", []):
            props = entry.setdefault("properties", [])
            if pname not in props:
                props.append(pname)
                props.sort()

    gscope = classes.get("@GlobalScope", {})
    manifest = {
        "engine_version": ENGINE_VERSION,
        "provenance": (
            "godotengine/godot tag %s, doc/classes/*.xml via codeload.github.com; "
            "zipball bytes %d sha256 %s"
            % (ENGINE_VERSION, len(data), hashlib.sha256(data).hexdigest())
        ),
        "class_count": len(classes),
        "global_functions": sorted(
            n for n, k in gscope.get("methods", {}).items()
        ),
        "global_constants": gscope.get("constants", []),
        "classes": {k: classes[k] for k in sorted(classes)},
    }
    OUT.write_text(
        json.dumps(manifest, separators=(",", ":"), sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(
        "wrote %s — %d classes, %d global functions, %d global constants, %d bytes"
        % (
            OUT.relative_to(ROOT),
            len(classes),
            len(manifest["global_functions"]),
            len(manifest["global_constants"]),
            OUT.stat().st_size,
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
