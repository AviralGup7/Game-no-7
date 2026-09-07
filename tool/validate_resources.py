#!/usr/bin/env python3
"""Lightweight structural validator for Godot .tscn/.tres text files.

This is NOT a substitute for Godot's own importer; it catches common hand-authoring
mistakes before CI/editor: load_steps mismatches, missing referenced res:// files,
stale or duplicated script ids, and obviously unbalanced section headers.

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
            elif line.startswith("[node ") or line.startswith("[editable"):
                inside_resource = True
            elif line.startswith("[resource]"):
                inside_resource = True

    # Count actual ExtResource uses that lack a declared id.
    used_ids = set()
    for raw in lines:
        used_ids.update(EXTRES_USE_RE.findall(raw))

    for rid in used_ids:
        if rid not in ext_resources:
            problems.append(f"{rel}: ExtResource(\"{rid}\") used but not declared")

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
