#!/usr/bin/env python3
r"""Lightweight structural validator for Godot .tscn/.tres text files.

This is NOT a substitute for Godot's own importer; it catches common hand-authoring
mistakes before CI/editor: load_steps mismatches, missing referenced res:// files,
stale or duplicated script ids, obviously unbalanced section headers, and — for
scenes that inherit another scene (`instance=ExtResource(...)`) — property values
referencing `SubResource("id")` pools from the parent file. It also checks the two ways
the text-format reader is stricter than GDScript, both of which shipped broken resources
this tool could previously not see: an authored value constructor that is not a flat,
complete list of numbers (`Color(r, g, b)` is legal code and a parse error in a .tres),
and non-ASCII bytes in a resource file (the reader is Latin-1 oriented; Godot's writer
emits `\uXXXX` escapes and the reader reverses them). Sub-resource ids are
file-local: a child scene must declare what it references (or edit the base), the
editor's `[editable]` sections being the one sanctioned cross-file pointer.

Run from the repository root:
    python3 tool/validate_resources.py
Exits non-zero when problems are found.
"""
from __future__ import annotations

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

HEADER_RE = re.compile(r"^\[gd_(scene|resource) ([^\]]+)\]$")
EXT_RE = re.compile(r'^\[ext_resource[^\]]* type="([^"]+)" path="([^"]+)" id="([^"]+)"\]')
SUB_RE = re.compile(r"^\[sub_resource type=\"([^\"]+)\" id=\"([^\"]+)\"\]$")
NODE_INSTANCE_RE = re.compile(r'^\[node[^\]]* instance=ExtResource\("([^"]+)"\)\]')
NODE_RE = re.compile(r"^\[node ")
EXTRES_USE_RE = re.compile(r'ExtResource\("([^"]+)"\)')
SUBRES_USE_RE = re.compile(r'SubResource\("([^"]+)"\)')
EDITABLE_SUB_RE = re.compile(r'^\[editable [^\]]*\bsub_resource="([^"]+)"')

# Godot's text-format reader does not evaluate GDScript: it builds authored values by calling the
# constructor with a fixed number of flat scalar arguments. So `Color(0.22, 0.42, 0.68)` — legal, and
# what a hand-written .tres looks like when you copy from code — is a *parse error* in a resource file
# ("Expected 4 arguments for constructor"), the file never loads, and everything referencing it fails
# with it. Six shipped arena theme/landmark resources were broken this way, and no local check could
# see it: the scripts themselves parsed fine, and `gdparse` knows nothing of the engine's ClassDB.
ENGINE_ARITY = {
    "Color": 4, "Vector2": 2, "Vector2i": 2, "Vector3": 3, "Vector3i": 3, "Vector4": 4,
    "Rect2": 4, "Rect2i": 4, "AABB": 6, "Plane": 4, "Quat": 4, "Basis": 9,
    "Transform2D": 6, "Transform3D": 12, "Projection": 16,
}
# `[^()]*` deliberately declines to match a constructor call with a nested call inside it; nothing in
# the text format writes that way, and a false positive here would be worse than a miss.
NUM_RE = re.compile(r"-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?")
VALUE_RE = re.compile(
    r"\b(" + "|".join(ENGINE_ARITY) + r")\(([^()]*)\)")

# The text reader is Latin-1 oriented: a raw em dash in an authored string is reported as
# "Unicode parsing error: Invalid unicode codepoint (2014), cannot represent as ASCII/Latin-1".
# Godot's own writer escapes non-ASCII as \uXXXX, and the reader unescapes it — so escaping is not a
# workaround, it is the file format. (GDScript source is a different story: scripts are read as UTF-8,
# which is why a literal em dash in narrator.gd stays.)


def load_steps_from(header_line: str) -> int | None:
    m = re.search(r"load_steps=(\d+)", header_line)
    return int(m.group(1)) if m else None


def check_file(path: str, problems: list[str]) -> None:
    rel = os.path.relpath(path, ROOT)
    with open(path, "r", encoding="utf-8") as fh:
        lines = fh.readlines()

    first = lines[0].strip()
    hm = HEADER_RE.match(first)
    if not hm:
        problems.append(f"{rel}: missing/invalid [gd_scene] or [gd_resource] header")
        return

    ext_resources: dict[str, str] = {}
    sub_ids: set[str] = set()
    editable_sub_ids: set[str] = set()
    instanced = False
    sub_count = 0
    header_load_steps = load_steps_from(first)
    inside_resource = False

    for raw in lines[1:]:
        line = raw.strip()
        if line.startswith("["):
            if line.startswith("[ext_resource"):
                em = EXT_RE.match(line)
                if not em:
                    problems.append(f"{rel}: malformed ext_resource line: {line}")
                    continue
                _type, path, rid = em.groups()
                if rid in ext_resources:
                    problems.append(f"{rel}: duplicate ext_resource id '{rid}'")
                ext_resources[rid] = path
                real_path = os.path.join(ROOT, path.replace("res://", "", 1))
                if not os.path.exists(real_path):
                    problems.append(f"{rel}: referenced path missing: {path}")
            elif line.startswith("[sub_resource"):
                sm = SUB_RE.match(line)
                if not sm:
                    problems.append(f"{rel}: malformed sub_resource line: {line}")
                else:
                    sub_count += 1
                    sub_ids.add(sm.group(2))
            elif line.startswith("[node ") or line.startswith("[editable"):
                inside_resource = True
                if NODE_INSTANCE_RE.match(line):
                    instanced = True
                else:
                    em2 = EDITABLE_SUB_RE.match(line)
                    if em2:
                        # Sanctioned cross-file pointer: editing a base sub-resource.
                        editable_sub_ids.add(em2.group(1))
            elif line.startswith("[resource]"):
                inside_resource = True

    # Count actual ExtResource uses that lack a declared id.
    used_ids = set()
    for raw in lines:
        used_ids.update(EXTRES_USE_RE.findall(raw))

    for rid in used_ids:
        if rid not in ext_resources:
            problems.append(f"{rel}: ExtResource(\"{rid}\") used but not declared")

    # Inherited scenes: a SubResource("id") in a property must resolve inside THIS
    # file. Referencing the parent scene's sub-resource id silently yields a broken
    # (or missing) override — the classic hand-edit hazard on child scenes like the
    # enemy archetypes that inherit enemy_base.tscn.
    if instanced:
        used_subs: set[str] = set()
        for raw in lines:
            used_subs.update(SUBRES_USE_RE.findall(raw))
        for sid in sorted(used_subs):
            if sid not in sub_ids and sid not in editable_sub_ids:
                problems.append(
                    f'{rel}: SubResource("{sid}") referenced but not declared in this file — '
                    f"sub-resource ids are file-local; declare it here or edit the base scene"
                )

    # --- authored value constructors -------------------------------------------------------------
    for lineno, raw in enumerate(lines, 1):
        for m in VALUE_RE.finditer(raw):
            kind, inner = m.group(1), m.group(2)
            args = [a.strip() for a in inner.split(",") if a.strip()]
            if not all(NUM_RE.fullmatch(a) for a in args):
                problems.append(
                    f"{rel}:{lineno}: {kind}(...) is not a list of flat numbers — the .tres reader "
                    f"calls the constructor itself, so write the literals out "
                    f"(found: {inner.strip()[:60]!r})"
                )
                continue
            want = ENGINE_ARITY[kind]
            if len(args) != want:
                problems.append(
                    f"{rel}:{lineno}: {kind}(...) has {len(args)} components, the text format wants "
                    f"exactly {want} (a wrong count is a parse error: the resource does not load, and "
                    f"neither does anything that references it)"
                )

    # --- ASCII-only authored text --------------------------------------------------------------
    for lineno, raw in enumerate(lines, 1):
        odd = sorted({ord(c) for c in raw if ord(c) > 127})
        if odd:
            names = ", ".join("U+%04X" % c for c in odd)
            form = "".join("\\u%04x" % c for c in odd)
            problems.append(
                f"{rel}:{lineno}: non-ASCII {names} in a resource file - write it as {form}, which is "
                f"what Godot's own writer emits and what the Latin-1 text reader expects"
            )

    declared = len(ext_resources)
    expected_steps = declared + sub_count + 1
    if header_load_steps is not None and header_load_steps != expected_steps:
        problems.append(
            f"{rel}: load_steps={header_load_steps} but expected {expected_steps} "
            f"({declared} ext + {sub_count} sub + 1)"
        )

    # Sanity: a resource section should not be entirely empty of node/resource data.
    if not inside_resource and (declared == 0 and sub_count == 0):
        problems.append(f"{rel}: scene contains no content")


def main() -> int:
    problems: list[str] = []
    count = 0
    for dirpath, _dirnames, filenames in os.walk(os.path.join(ROOT, "scenes")):
        for name in filenames:
            if name.endswith((".tscn", ".tres")):
                count += 1
                check_file(os.path.join(dirpath, name), problems)
    for folder in ("data", "assets/materials"):
        for dirpath, _dirnames, filenames in os.walk(os.path.join(ROOT, folder)):
            for name in filenames:
                if name.endswith(".tres"):
                    count += 1
                    check_file(os.path.join(dirpath, name), problems)

    if problems:
        print(f"Validated {count} files: {len(problems)} problem(s)")
        for p in problems:
            print(" - " + p)
        return 1
    print(f"Validated {count} files: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
