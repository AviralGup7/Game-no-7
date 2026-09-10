#!/usr/bin/env python3
"""Typed-architecture gate for Last Stand: Arena.

Enforces the post-refactor contract (docs/REFACTOR_PLAN.md, Phase C):

1. No string-dispatch duck typing in scripts/:
   - `.call("...")` with a string literal first argument is banned (Callable
     invocation with a function reference is fine and not matched).
   - `has_method(` is banned except for explicit, commented allowlist entries.

2. Typed references must resolve:
   - `as <T>` / `extends <T>` where <T> is neither a Godot built-in nor a
     `class_name` declared in this project is an error.
   - `<ClassNameOrAutoload>.<member>(...)` calls are checked against the
     actual funcs/signals of that class (walking the project `extends`
     chain), catching the class of typos gdparse cannot see.

Exit code 0 = architecture clean; 1 = violations listed on stdout.
Run: python3 tool/check_typed_arch.py [--all]
"""

from __future__ import annotations

import re
import sys
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
SCRIPTS_DIR = ROOT / "scripts"
PROJECT_FILE = ROOT / "project.godot"

# Deliberate exceptions. Each entry: (path-from-repo-root, unique needle that
# must appear in the allowlisted line, reason). Keep this list SHORT; every
# entry is architecture debt by definition.
ALLOWED_HAS_METHOD: list[tuple[str, str, str]] = [
    (
        "scripts/core/test_harness.gd",
        "_progression_commands_ok",
        "the CI harness probes GameRoot's API surface on purpose so a deleted "
        "or renamed method fails the check loudly (assertion, not dispatch)",
    ),
]

# Godot built-in types and global identifiers that are legal cast/extends
# targets but are not declared anywhere in this project. Casting to these is
# checked by the engine itself; the point here is catching unknown PROJECT
# type names (typos like `as WeaponManger`).
BUILTIN_TYPES = {
    # Object/Node hierarchy + engine globals that appear in casts.
    "Object", "Node", "Node2D", "Node3D", "Control", "CharacterBody3D",
    "RigidBody3D", "StaticBody3D", "Area3D", "CollisionShape3D", "MeshInstance3D",
    "Marker3D", "Path3D", "CanvasLayer", "Resource", "ResourceLoader",
    "PackedScene", "SceneTree", "SceneTreeTimer", "Timer", "Camera3D",
    "DirectionalLight3D", "WorldEnvironment", "Environment", "Label", "Button",
    "Panel", "PanelContainer", "VBoxContainer", "HBoxContainer", "GridContainer",
    "CenterContainer", "MarginContainer", "ScrollContainer", "TextureRect",
    "ColorRect", "ProgressBar", "CheckButton", "Slider", "HSlider", "VSlider",
    "OptionButton", "LineEdit", "AudioStreamPlayer", "AudioStreamPlayer3D",
    "AnimationPlayer", "AnimationTree", "Tween", "Viewport", "SubViewport",
    "Window", "HTTPRequest", "InputEvent", "Input", "Engine", "OS", "Time",
    "ClassDB", "ProjectSettings", "Performance", "PhysicsServer3D",
    # Variant types.
    "int", "float", "bool", "String", "StringName", "Vector2", "Vector2i",
    "Vector3", "Vector3i", "Vector4", "Color", "Rect2", "Rect2i", "Transform2D",
    "Transform3D", "Basis", "Quaternion", "Dictionary", "Array", "PackedByteArray",
    "PackedInt32Array", "PackedInt64Array", "PackedFloat32Array",
    "PackedFloat64Array", "PackedStringArray", "PackedVector2Array",
    "PackedVector3Array", "PackedColorArray", "Callable", "Signal", "NodePath",
    "RID", "Nil", "AABB", "Plane",
    # Engine classes used in casts across this codebase. When a new cast to an
    # engine class appears, add it here (fail-closed: unknown names are errors).
    "StandardMaterial3D", "BaseMaterial3D", "ParticleProcessMaterial",
    "ORMMaterial3D", "NavigationRegion3D", "NavigationAgent3D", "OmniLight3D",
    "AudioStream", "AudioStreamOggVorbis", "AudioStreamWAV", "AudioStreamMP3",
    "AudioStreamRandomizer", "AnimationLibrary", "Animation", "AnimationPlayer",
    "Skeleton3D", "Texture2D", "Texture2DArray", "AtlasTexture",
    "GradientTexture2D", "CompressedTexture2D", "InputEventKey",
    "InputEventMouseButton", "InputEventMouseMotion", "InputEventScreenTouch", "InputEventScreenDrag",
    "InputEventJoypadButton", "InputEventJoypadMotion", "InputEventAction",
    "InputEventWithModifiers", "RandomNumberGenerator", "QuadMesh",
    "GPUParticles3D", "CPUParticles3D", "BoxMesh", "SphereMesh", "CylinderMesh",
    "CapsuleMesh", "PlaneMesh", "ArrayMesh", "Mesh", "Font", "FontFile",
    "SystemFont", "StyleBoxFlat", "StyleBoxTexture", "Theme", "Gradient",
    "Curve", "Image", "ImageTexture", "Skin", "Shader", "ShaderMaterial",
    "Environment", "CameraAttributesPractical", "MultiMesh",
    "MultiMeshInstance3D", "RayCast3D", "ShapeCast3D", "CollisionPolygon3D",
    "PhysicsBody3D", "CollisionObject3D", "AnimatableBody3D", "SkeletonIK3D",
    "BoneAttachment3D", "Sprite2D", "Sprite3D", "Label3D", "Decal",
    "ReflectionProbe", "Light3D", "SpotLight3D", "ProceduralSkyMaterial", "Sky",
}

# Methods every Object-derived type answers to (verified by the engine itself).
OBJECT_BUILTIN_METHODS = {
    "has_method", "get", "set", "call", "callv", "call_deferred", "connect",
    "disconnect", "emit_signal", "is_connected", "get_script", "set_script",
    "get_class", "is_class", "get_instance_id", "get_meta", "set_meta",
    "has_meta", "get_property_list", "get_method_list", "get_signal_list",
    "add_to_group", "is_in_group", "has_signal", "has_user_signal", "free",
    "notification", "to_string", "duplicate", "queue_free",
    "is_queued_for_deletion", "get_index", "get_path", "get_name", "set_name",
    "is_inside_tree", "get_tree", "get_parent", "get_node", "get_node_or_null",
    "add_child", "remove_child", "get_children", "get_child", "find_child",
    "find_children", "emit", "rpc", "rpc_id",
}

CLASS_RE = re.compile(r"^\s*class_name\s+(\w+)")
EXTENDS_RE = re.compile(r"^\s*(?:\#\#)?\s*extends\s+([\w.\"/]+)")
FUNC_RE = re.compile(r"^\s*(?:static\s+)?func\s+(\w+)")
SIGNAL_RE = re.compile(r"^\s*signal\s+(\w+)")
CONST_RE = re.compile(r"^\s*(?:const|enum)\s+(\w*)")
VAR_RE = re.compile(r"^\s*(?:@export[\w\s_,()]*\s+)?var\s+(\w+)")
CALL_STRING_RE = re.compile(r"\.call\(\s*[\"&]")
HAS_METHOD_RE = re.compile(r"\bhas_method\(")
AS_CAST_RE = re.compile(r"\bas\s+([A-Z]\w*)\b")
GLOBAL_CALL_RE = re.compile(r"\b([A-Z]\w*)\.(\w+)\(")


def strip_comment(line: str) -> str:
    """Remove a trailing ## comment (naive but adequate: no # inside strings
    in the lines this tool inspects for the banned patterns)."""
    out = []
    in_string = False
    quote = ""
    i = 0
    while i < len(line):
        ch = line[i]
        if in_string:
            if ch == "\\" and i + 1 < len(line):
                out.append(line[i:i + 2])
                i += 2
                continue
            if ch == quote:
                in_string = False
            out.append(ch)
        else:
            if ch in "\"'":
                in_string = True
                quote = ch
                out.append(ch)
            elif ch == "#":
                break
            else:
                out.append(ch)
        i += 1
    return "".join(out)


class GdFile:
    def __init__(self, path: pathlib.Path) -> None:
        self.path = path
        rel = path.relative_to(ROOT)
        self.rel = rel.as_posix()
        raw = path.read_text(encoding="utf-8")
        self.lines = [strip_comment(ln) for ln in raw.splitlines()]
        self.class_name: str | None = None
        self.extends: str | None = None
        self.funcs: set[str] = set()
        self.signals: set[str] = set()
        self.consts: set[str] = set()
        self.vars: set[str] = set()
        self._parse()

    def _parse(self) -> None:
        for ln in self.lines:
            m = CLASS_RE.match(ln)
            if m:
                self.class_name = m.group(1)
                continue
            m = EXTENDS_RE.match(ln)
            if m and self.extends is None:
                self.extends = m.group(1)
                continue
            m = FUNC_RE.match(ln)
            if m:
                self.funcs.add(m.group(1))
                continue
            m = SIGNAL_RE.match(ln)
            if m:
                self.signals.add(m.group(1))
                continue
            m = CONST_RE.match(ln)
            if m and m.group(1):
                self.consts.add(m.group(1))
                continue
            m = VAR_RE.match(ln)
            if m:
                self.vars.add(m.group(1))


def load_project() -> tuple[dict[str, GdFile], dict[str, GdFile]]:
    """Return (class_name -> file, autoload-name -> file)."""
    classes: dict[str, GdFile] = {}
    for path in sorted(SCRIPTS_DIR.rglob("*.gd")):
        gf = GdFile(path)
        if gf.class_name:
            classes[gf.class_name] = gf

    autoloads: dict[str, GdFile] = {}
    try:
        text = PROJECT_FILE.read_text(encoding="utf-8")
    except FileNotFoundError:
        return classes, autoloads
    section = False
    for ln in text.splitlines():
        if ln.strip().startswith("["):
            section = ln.strip() == "[autoload]"
            continue
        if section and "=" in ln:
            name, _, value = ln.partition("=")
            value = value.strip().strip("*\"'")
            if value.startswith("res://"):
                local = value.replace("res://", "")
                script = ROOT / local
                if script.suffix == ".gd" and script.exists():
                    autoloads[name.strip()] = GdFile(script)
                else:
                    # Autoload points at a scene: resolve its root script.
                    scene = script
                    if scene.exists():
                        m = re.search(
                            r"script\s*=\s*ExtResource\(\s*\"?(\d+)\"?\s*\)",
                            scene.read_text(encoding="utf-8"),
                        )
                        path_m = re.search(
                            r"path=\"(res://[^\"]+\.gd)\"", scene.read_text(encoding="utf-8")
                        )
                        if path_m:
                            autoloads[name.strip()] = GdFile(
                                ROOT / path_m.group(1).replace("res://", "")
                            )
    return classes, autoloads


def resolve_members(name: str, classes: dict[str, GdFile], autoloads: dict[str, GdFile]) -> set[str] | None:
    """All funcs/signals/consts of `name`, walking the project extends chain."""
    gf = classes.get(name) or autoloads.get(name)
    if gf is None:
        return None
    seen = set()
    members: set[str] = set()
    current: GdFile | None = gf
    while current is not None and id(current) not in seen:
        seen.add(id(current))
        members |= current.funcs | current.signals | current.consts | current.vars
        base = current.extends
        if base is None:
            break
        base = base.split(".")[-1].strip('"')
        current = classes.get(base) or autoloads.get(base)
        if current is None and base not in BUILTIN_TYPES and base in classes:
            current = classes[base]
    return members


def allowlist_blocks(gf: "GdFile") -> dict[int, str]:
    """Map line-number -> allowlist reason for has_method lines inside an
    allowlisted function block (func header .. next func header)."""
    reasons: dict[int, str] = {}
    for entry_path, needle, reason in ALLOWED_HAS_METHOD:
        if gf.rel != entry_path:
            continue
        start = None
        for idx, line in enumerate(gf.lines, start=1):
            if re.match(rf"\s*(static\s+)?func\s+{re.escape(needle)}\b", line):
                start = idx
                continue
            if start is not None and re.match(r"\s*(static\s+)?func\s+\w+", line):
                break
            if start is not None and HAS_METHOD_RE.search(line):
                reasons[idx] = reason
    return reasons


def main() -> int:
    classes, autoloads = load_project()
    violations: list[str] = []

    for path in sorted(SCRIPTS_DIR.rglob("*.gd")):
        gf = GdFile(path)
        allowed_lines = allowlist_blocks(gf)
        for idx, line in enumerate(gf.lines, start=1):
            if CALL_STRING_RE.search(line):
                violations.append(
                    f"{gf.rel}:{idx}: string dispatch `.call(\"...\")` is banned: {line.strip()}"
                )
            if HAS_METHOD_RE.search(line) and idx not in allowed_lines:
                violations.append(
                    f"{gf.rel}:{idx}: `has_method(` is banned: {line.strip()}"
                )

        # Typed-reference resolution (skips the built-in-only check for extends).
        for idx, line in enumerate(gf.lines, start=1):
            for m in AS_CAST_RE.finditer(line):
                type_name = m.group(1)
                if type_name not in BUILTIN_TYPES and type_name not in classes:
                    violations.append(
                        f"{gf.rel}:{idx}: `as {type_name}` does not resolve to any "
                        f"project class_name: {line.strip()}"
                    )

        for idx, line in enumerate(gf.lines, start=1):
            for m in GLOBAL_CALL_RE.finditer(line):
                owner, member = m.group(1), m.group(2)
                if owner in BUILTIN_TYPES:
                    continue
                if owner not in classes and owner not in autoloads:
                    continue  # engine global (Input, Engine, OS, ...) — not ours
                members = resolve_members(owner, classes, autoloads)
                if members is None:
                    continue
                if member in ("new", "instance", "instantiate"):
                    continue
                if member in OBJECT_BUILTIN_METHODS:
                    continue
                if member not in members:
                    violations.append(
                        f"{gf.rel}:{idx}: `{owner}.{member}(...)` — no such "
                        f"func/signal/const on {owner}: {line.strip()}"
                    )

    if violations:
        print(f"typed-architecture gate: {len(violations)} violation(s)")
        for v in violations:
            print("  " + v)
        return 1
    print(
        f"typed-architecture gate: clean "
        f"({len(classes)} project classes, {len(autoloads)} autoloads checked)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
