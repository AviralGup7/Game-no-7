#!/usr/bin/env python3
"""Engine-API contract gate for Last Stand: Arena (offline, no Godot binary).

Why this exists
---------------
GDScript resolves typed member access at compile time against the engine's
ClassDB. `gdparse`/`gdlint` are syntax checks with no ClassDB, so a reference
to a member the pinned engine does not have slips through every static pass
and only surfaces when a real Godot runtime touches the line — as a parse
error that kills the script (`arena.gd` asking `AABB.has_area()`, engine name
`has_volume()`), a `SCRIPT ERROR` on every load (`PanoramaSkyMaterial.energy`),
a runtime abort that silently skips the rest of its function
(`get_surface_material_override_count()`, `NavigationAgent3D.path_height_tolerance`,
`World3D.intersect_shape`), or an unloadable script (`fposmodf` for `fposmod`).
Five shipped defects of one class — each one documented in CHANGELOG.md and
GODOT_HANDOFF_RESOLUTION.md.

This gate pins that contract to the exact engine CI runs (the `GODOT_VERSION`
tag): `tool/godot_api_manifest.json` is the 4.4.1-stable ClassDB itself
(methods + static-ness + return types, properties, signals, constants, plus
`@GlobalScope`), reduced from the official source tag by
`tool/build_api_manifest.py` and checked in, so the gate is hermetic.

What it checks
--------------
1. Every `.gd` under `scripts/` and `tests/`, with a small typed-dataflow walk:
   - attribute access on statically-known receivers (annotations, `:=` from
     constructors/casts/literals/typed calls, typed parameters, typed `for`,
     autoloads, `self`/`super`, chained return types from the manifest and
     project `-> Ret` annotations) is checked against the class's real members
     walking the inheritance chain — engine classes from the manifest, project
     classes from this tree;
   - calling a property, assigning to a method/const, calling a signal
     directly, and static-calling an instance method are all flagged;
   - bare global calls (`fposmodf(...)`) must exist in `@GlobalScope`;
   - bare uppercase constants (`PI`, error enums) must resolve;
   - type names in annotations/casts/`extends` must exist.
2. Every `.tscn`/`.tres`: property assignments on `[node type=...]`,
   `[sub_resource type=...]` and `[gd_resource type=...]` blocks must exist on
   that type (script-authored vars are merged for scripted nodes), and scene
   `[connection]` signal/method names must resolve — the class of bug that
   shipped as `path_height_tolerance` in `enemy_base.tscn`.

Untyped receivers (`$Path`, untyped `load()`, `get_node`, lambdas, Variants)
are not checked: GDScript allows anything on them, so flagging would be noise.
The gate is strict where the compiler is strict and silent where it is not.

Exit code 0 = contract clean; 1 = violations listed on stdout.
Run: python3 tool/check_engine_api.py
"""

from __future__ import annotations

import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
MANIFEST_PATH = ROOT / "tool" / "godot_api_manifest.json"
PROJECT_FILE = ROOT / "project.godot"
GD_DIRS = ("scripts", "tests")

# Deliberate exceptions. Each entry: (path-from-repo-root, unique needle that
# appears on the offending line, reason). Keep this list empty if at all
# possible — an entry here means the engine contract is being worked around.
ALLOWED: list[tuple[str, str, str]] = []

# Identifiers that behave like autoload singletons but come from the engine.
ENGINE_SINGLETONS = {
    "Engine": "Engine",
    "OS": "OS",
    "Input": "Input",
    "InputMap": "InputMap",
    "Time": "Time",
    "ClassDB": "ClassDB",
    "ProjectSettings": "ProjectSettings",
    "Performance": "Performance",
    "ResourceLoader": "ResourceLoader",
    "ResourceSaver": "ResourceSaver",
    "Geometry2D": "Geometry2D",
    "Geometry3D": "Geometry3D",
    "NavigationServer3D": "NavigationServer3D",
    "PhysicsServer3D": "PhysicsServer3D",
    "RenderingServer": "RenderingServer",
    "AudioServer": "AudioServer",
    "DisplayServer": "DisplayServer",
    "ThemeDB": "ThemeDB",
    "TranslationServer": "TranslationServer",
    "Marshalls": "Marshalls",
    "JSON": "JSON",
    "FileAccess": "FileAccess",
    "DirAccess": "DirAccess",
    "WorkerThreadPool": "WorkerThreadPool",
}

# Return types for a few @GlobalScope functions worth propagating (the manifest
# does not carry them). Widening inference only; never a source of errors.
GLOBAL_RETURNS = {
    "absf": "float", "absi": "int", "ceilf": "float", "ceili": "int",
    "clampf": "float", "clampi": "int", "floorf": "float", "floori": "int",
    "fmodf": "float", "fmodi": "int", "lerpf": "float", "maxf": "float",
    "maxi": "int", "minf": "float", "mini": "int", "roundf": "float",
    "roundi": "int", "signf": "float", "signi": "int", "snappedf": "float",
    "snappedi": "int", "str": "String", "typeof": "int", "len": "int",
    "hash": "int", "range": "Array", "deg_to_rad": "float", "rad_to_deg": "float",
    "db_to_linear": "float", "linear_to_db": "float", "sqrt": "float",
    "pow": "float", "log": "float", "exp": "float", "move_toward": "float",
    "lerp": "float", "lerp_angle": "float", "inverse_lerp": "float",
    "remap": "float", "smoothstep": "float", "wrapf": "float", "wrapi": "int",
    "posmod": "int", "nearest_po2": "int", "instance_from_id": "Object",
}

# Globals that are GDScript language features rather than @GlobalScope entries.
LANGUAGE_GLOBALS = {"load", "preload", "assert", "get_stack", "print_debug", "push_error", "push_warning"}

# Constants the GDScript language itself defines (they are not in the ClassDB
# doc XMLs at all, so the manifest cannot know them).
GDSCRIPT_CONSTANTS = {"PI", "TAU", "INF", "NAN"}

# Real native classes the doc XMLs do not describe (script-host types).
UNDOCUMENTED_CLASSES = {"GDScript", "CSharpScript", "Script", "ScriptExtension"}

# Variant builtin types: per the 4.4.1 GDScript analyzer
# (`reduce_identifier_from_base`), an unknown member on a HARD-typed builtin
# receiver is a compile error, while the same access on an Object-derived
# receiver is only UNSAFE_PROPERTY_ACCESS (resolved at runtime). Dictionary is
# the exception among builtins: any `.key` is legal and yields Variant.
BUILTIN_HARD_TYPES = {
    "int", "float", "bool", "String", "StringName", "NodePath", "RID",
    "Vector2", "Vector2i", "Vector3", "Vector3i", "Vector4", "Vector4i",
    "Rect2", "Rect2i", "Transform2D", "Transform3D", "Plane", "Quaternion",
    "AABB", "Basis", "Projection", "Color", "Callable", "Signal",
    "Array", "PackedByteArray", "PackedInt32Array", "PackedInt64Array",
    "PackedFloat32Array", "PackedFloat64Array", "PackedStringArray",
    "PackedVector2Array", "PackedVector3Array", "PackedVector4Array",
    "PackedColorArray",
}

# Members allowed on any Object-derived receiver regardless of ClassDB. These
# are the engine's script-introspection hatches that typed code legally uses.
OBJECT_UNIVERSAL = {"set", "get", "call", "call_deferred", "callv", "has_method",
                    "has_signal", "connect", "disconnect", "is_connected",
                    "emit_signal", "get_meta", "set_meta", "has_meta", "remove_meta",
                    "get_class", "is_class", "get_script", "set_script",
                    "get_instance_id", "to_string", "notification", "free",
                    "get_property_list", "get_method_list", "get_signal_list",
                    "is_queued_for_deletion", "queue_free"}

UNKNOWN = ""          # type we know nothing about -> never checked
OPAQUE = "?"          # type known to exist but not inspectable (inner class)


# ---------------------------------------------------------------------------
# Manifest
# ---------------------------------------------------------------------------

class Manifest:
    def __init__(self) -> None:
        raw = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
        self.engine_version: str = raw["engine_version"]
        self.classes: dict = raw["classes"]
        self.global_functions: set[str] = set(raw["global_functions"])
        self.global_constants: set[str] = set(raw["global_constants"])
        self._inherit_cache: dict[str, dict] = {}

    def has_class(self, name: str) -> bool:
        return name in self.classes

    def members(self, cls: str) -> dict:
        """name -> {'method': kind-or-None, 'property': bool, 'signal': bool,
        'constant': bool}, walking the engine inheritance chain."""
        cached = self._inherit_cache.get(cls)
        if cached is not None:
            return cached
        out: dict[str, dict] = {}
        chain = []
        cur = cls
        seen = set()
        while cur and cur in self.classes and cur not in seen:
            seen.add(cur)
            chain.append(cur)
            cur = self.classes[cur].get("inherits")
        for klass in reversed(chain):  # derived overrides base
            entry = self.classes[klass]
            for mname, kind in entry.get("methods", {}).items():
                out[mname] = {**out.get(mname, {}), "method": kind}
            for p in entry.get("properties", []):
                out[p] = {**out.get(p, {}), "property": True}
            for s in entry.get("signals", []):
                out[s] = {**out.get(s, {}), "signal": True}
            for c in entry.get("constants", []):
                out[c] = {**out.get(c, {}), "constant": True}
        self._inherit_cache[cls] = out
        return out


# ---------------------------------------------------------------------------
# Project class table
# ---------------------------------------------------------------------------

class GdClass:
    """Symbols one .gd file declares, enough to type-check accesses to it."""

    def __init__(self, path: pathlib.Path) -> None:
        self.path = path
        try:
            self.rel = path.relative_to(ROOT).as_posix()
        except ValueError:  # synthetic files from tests
            self.rel = path.name
        self.text = path.read_text(encoding="utf-8")
        self.lines = [strip_code_comment(ln) for ln in self.text.splitlines()]
        self.class_name: str | None = None
        self.extends: str | None = None
        self.funcs: dict[str, str] = {}        # name -> return type ('' unknown)
        self.static_funcs: set[str] = set()
        self.func_params: dict[str, dict[str, str]] = {}  # func -> {param: type}
        self.vars: dict[str, str] = {}         # name -> type ('' unknown)
        self.consts: set[str] = set()
        self.enum_values: set[str] = set()
        self.signals: set[str] = set()
        self.inner_classes: set[str] = set()

    # -- symbol collection -------------------------------------------------
    def collect(self) -> None:
        # work on comment-stripped lines so `# class Foo:` never registers
        text = "\n".join(self.lines)
        m = re.search(r"^class_name\s+(\w+)", text, re.M)
        if m:
            self.class_name = m.group(1)
        m = re.search(r"^extends\s+([\w.\"]+)", text, re.M)
        if m:
            self.extends = m.group(1).split(".")[-1].strip('"')
        # signals (any indent: inner classes can declare them too)
        for m in re.finditer(r"^\s*signal\s+(\w+)", text, re.M):
            self.signals.add(m.group(1))
        # functions with return types + typed params; parameter lists may span
        # lines, so walk to the matching paren instead of one regex.
        for m in re.finditer(r"^\s*(static\s+)?func\s+(\w+)\s*\(", text, re.M):
            name = m.group(2)
            if m.group(1):
                self.static_funcs.add(name)
            depth = 1
            j = m.end()
            pstart = j
            while j < len(text) and depth > 0:
                if text[j] == "(":
                    depth += 1
                elif text[j] == ")":
                    depth -= 1
                j += 1
            params_src = text[pstart:j - 1]
            tail = text[j:j + 80].lstrip()
            rm = re.match(r"->\s*([\w.\[\]]+)", tail)
            self.funcs[name] = generic_base(rm.group(1)) if rm else ""
            params: dict[str, str] = {}
            for p in split_params(params_src):
                pm = re.match(r"(\w+)\s*:\s*([\w.\[\]]+)", p.strip())
                if pm:
                    params[pm.group(1)] = generic_base(pm.group(2))
            self.func_params[name] = params
        # top-level vars/consts — every one is a member, annotated or not,
        # `static var` included.
        for m in re.finditer(
            r"^(?:@\w+(?:\([^)]*\))?\s+)*(?:static\s+)?var\s+(\w+)\s*(?::\s*([\w.\[\]]+))?",
            text, re.M,
        ):
            self.vars[m.group(1)] = generic_base(m.group(2) or "")
        for m in re.finditer(
            r"^(?:static\s+)?const\s+(\w+)\s*:\s*([\w.\[\]]+)", text, re.M
        ):
            self.vars[m.group(1)] = generic_base(m.group(2))
            self.consts.add(m.group(1))
        for m in re.finditer(r"^(?:static\s+)?const\s+(\w+)\s*:=", text, re.M):
            self.consts.add(m.group(1))
        # enums: `enum Name { ... }` and bare `enum { ... }`
        for m in re.finditer(r"^\s*enum\s+(\w+)?\s*\{([^}]*)\}", text, re.M | re.S):
            if m.group(1):
                self.consts.add(m.group(1))
            for part in m.group(2).split(","):
                ev = part.split("=")[0].strip()
                if re.match(r"^\w+$", ev):
                    self.enum_values.add(ev)
        # inner classes (indented inside a class, or column-0 in test suites)
        for m in re.finditer(r"^\s*class\s+(\w+)\s*(?:extends\s+\w+\s*)?:", text, re.M):
            self.inner_classes.add(m.group(1))


def generic_base(t: str) -> str:
    """`Array[StringName]` -> `Array`; strips nesting whitespace."""
    t = t.strip()
    idx = t.find("[")
    return t[:idx].strip() if idx >= 0 else t


def split_params(s: str) -> list[str]:
    out, depth, cur = [], 0, []
    for ch in s:
        if ch in "(<[":
            depth += 1
        elif ch in ")>]":
            depth -= 1
        if ch == "," and depth == 0:
            out.append("".join(cur))
            cur = []
        else:
            cur.append(ch)
    if cur:
        out.append("".join(cur))
    return [p for p in out if p.strip()]


def strip_code_comment(line: str) -> str:
    """Remove a trailing # comment, respecting string literals."""
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


class Project:
    def __init__(self, manifest: Manifest) -> None:
        self.manifest = manifest
        self.files: list[GdClass] = []
        self.by_class: dict[str, GdClass] = {}
        self.autoloads: dict[str, GdClass] = {}
        for d in GD_DIRS:
            base = ROOT / d
            for path in sorted(base.rglob("*.gd")):
                gf = GdClass(path)
                gf.collect()
                self.files.append(gf)
                if gf.class_name:
                    self.by_class[gf.class_name] = gf
        self._load_autoloads()

    def _load_autoloads(self) -> None:
        try:
            text = PROJECT_FILE.read_text(encoding="utf-8")
        except FileNotFoundError:
            return
        section = False
        for ln in text.splitlines():
            if ln.strip().startswith("["):
                section = ln.strip() == "[autoload]"
                continue
            if section and "=" in ln:
                name, _, value = ln.partition("=")
                value = value.strip().strip("*\"'")
                if value.startswith("res://") and value.endswith(".gd"):
                    local = ROOT / value.replace("res://", "")
                    if local.exists():
                        gf = GdClass(local)
                        gf.collect()
                        self.autoloads[name.strip()] = gf

    def class_by_name(self, name: str) -> GdClass | None:
        return self.by_class.get(name) or self.autoloads.get(name)

    def extends_chain(self, gf: GdClass) -> list[GdClass]:
        out, seen, cur = [], set(), gf
        while cur is not None and id(cur) not in seen:
            seen.add(id(cur))
            out.append(cur)
            base = cur.extends
            if not base:
                break
            cur = self.class_by_name(base)
        return out

    def project_base_engine(self, gf: GdClass) -> str | None:
        """The first engine class in `gf`'s extends chain (None if untyped)."""
        for klass in self.extends_chain(gf):
            base = klass.extends
            if base and self.manifest.has_class(base) and base not in self.by_class:
                return base
        return None

    def project_members(self, name: str) -> dict[str, dict] | None:
        """All members of a project class incl. its chain; engine tail merged
        from the manifest. Returns the same shape as Manifest.members."""
        gf = self.class_by_name(name)
        if gf is None:
            return None
        out: dict[str, dict] = {}
        engine_root: str | None = None
        for klass in reversed(self.extends_chain(gf)):
            for fn, ret in klass.funcs.items():
                kind = ("s" if fn in klass.static_funcs else "m") + (";" + ret if ret else "")
                out[fn] = {**out.get(fn, {}), "method": kind}
            for v, t in klass.vars.items():
                out[v] = {**out.get(v, {}), "property": True, "vartype": t}
            for c in klass.consts:
                out[c] = {**out.get(c, {}), "constant": True}
            for ev in klass.enum_values:
                out[ev] = {**out.get(ev, {}), "constant": True}
            for s in klass.signals:
                out[s] = {**out.get(s, {}), "signal": True}
            for ic in klass.inner_classes:
                out[ic] = {**out.get(ic, {}), "inner": True}
            if klass.extends and self.manifest.has_class(klass.extends) \
                    and klass.extends not in self.by_class:
                engine_root = klass.extends
        if engine_root:
            for mname, info in self.manifest.members(engine_root).items():
                out.setdefault(mname, info)
        return out


# ---------------------------------------------------------------------------
# Tokenizer (strings-aware)
# ---------------------------------------------------------------------------

TOKEN_RE = re.compile(
    r"""
    (?P<string>&?"(?:\\.|[^"\\])*"|&?'(?:\\.|[^'\\])*'|\^"(?:\\.|[^"\\])*")
    | (?P<number>\d[\d_]*(?:\.[\d_]+)?(?:[eE][+-]?\d+)?|0[xX][\da-fA-F_]+)
    | (?P<ident>[A-Za-z_]\w*)
    | (?P<op>==|!=|<=|>=|&&|\|\||->|\+=|-=|\*=|/=|%=|\*\*|<<|>>|[.,()\[\]{}:=+\-*/%<>!&|~^])
    """,
    re.X,
)

KEYWORDS = {"if", "elif", "else", "for", "while", "match", "break", "continue",
            "pass", "return", "class", "class_name", "extends", "is", "in", "as",
            "and", "or", "not", "true", "false", "null", "self", "super",
            "await", "yield", "signal", "func", "static", "const", "enum", "var",
            "void", "when", "breakpoint"}


class Tok:
    __slots__ = ("kind", "text", "pos")

    def __init__(self, kind: str, text: str, pos: int) -> None:
        self.kind = kind
        self.text = text
        self.pos = pos

    def __repr__(self) -> str:  # pragma: no cover
        return f"{self.kind}:{self.text}"


def tokenize(line: str) -> list[Tok]:
    toks = []
    for m in TOKEN_RE.finditer(line):
        kind = m.lastgroup or "op"
        text = m.group()
        if kind == "ident" and text in KEYWORDS:
            kind = "kw"
        toks.append(Tok(kind, text, m.start()))
    return toks


# ---------------------------------------------------------------------------
# The gate
# ---------------------------------------------------------------------------

class Gate:
    def __init__(self) -> None:
        self.manifest = Manifest()
        self.project = Project(self.manifest)
        self.errors: list[str] = []
        self.warnings: list[str] = []
        # every member name known anywhere in engine + project: a miss that is
        # not even a name in the whole world is a typo/phantom, not a duck-typed
        # access to something that exists on the runtime type.
        self._all_names: set[str] | None = None

    def exists_anywhere(self, name: str) -> bool:
        if self._all_names is None:
            names: set[str] = set()
            for entry in self.manifest.classes.values():
                names.update(entry.get("methods", {}))
                names.update(entry.get("properties", []))
                names.update(entry.get("signals", []))
                names.update(entry.get("constants", []))
            for gf in self.project.files:
                names.update(gf.funcs)
                names.update(gf.vars)
                names.update(gf.consts)
                names.update(gf.signals)
            self._all_names = names
        return name in self._all_names

    # -- reporting ---------------------------------------------------------
    def error(self, rel: str, line_no: int, msg: str) -> None:
        for path, needle, _reason in ALLOWED:
            if rel == path and needle in msg:
                return
        self.errors.append(f"{rel}:{line_no}: {msg}")

    def warning(self, rel: str, line_no: int, msg: str) -> None:
        self.warnings.append(f"{rel}:{line_no}: {msg}")

    # -- member resolution --------------------------------------------------
    def engine_members(self, cls: str) -> dict[str, dict]:
        return self.manifest.members(cls)

    def members_of(self, type_name: str) -> dict[str, dict] | None:
        """Member table for a type name (engine or project), else None."""
        if type_name in (UNKNOWN, OPAQUE):
            return None
        if self.manifest.has_class(type_name):
            return self.engine_members(type_name)
        if self.project.class_by_name(type_name) is not None:
            return self.project.project_members(type_name)
        return None

    def type_exists(self, name: str) -> bool:
        base = generic_base(name)
        if base in ("", "Variant", "void"):
            return True
        if base in UNDOCUMENTED_CLASSES:
            return True
        return (self.manifest.has_class(base)
                or self.project.class_by_name(base) is not None)

    def _type_exists_in_file(self, name: str, gf: GdClass) -> bool:
        """Annotation/cast target: engine class, project class, or this file's
        own enum/inner class (all legal GDScript annotation targets)."""
        base = generic_base(name)
        if base in gf.inner_classes or base in gf.consts:
            return True
        return self.type_exists(name)

    # -- per-file check ------------------------------------------------------
    def check_gd(self, gf: GdClass) -> None:
        self_type = gf.class_name or ""
        extends = gf.extends
        # extends must resolve
        if extends and not self.type_exists(extends) and extends not in self.project.by_class:
            self.error(gf.rel, 1, f"extends unknown type `{extends}`")

        locals_typed: dict[str, str] = {}
        in_enum = 0

        # Physical lines -> logical statements (join `\` continuations and
        # bracket-open expressions so one statement is one check).
        logical: list[tuple[int, str]] = []
        buf = ""
        start = 0
        depth = 0
        for lno, rawline in enumerate(gf.lines, start=1):
            stripped0 = rawline.strip()
            if not stripped0:
                if depth > 0 or buf.endswith("\\"):
                    continue  # blank line inside an open bracket list
                continue
            if not buf:
                start = lno
            for ch in stripped0:
                if ch in "([{":
                    depth += 1
                elif ch in ")]}":
                    depth -= 1
            piece = stripped0
            cont = depth > 0 or piece.endswith("\\") or piece.endswith(",")
            buf = (buf + " " + piece.rstrip("\\")) if buf else piece.rstrip("\\")
            if not cont:
                logical.append((start, buf.strip()))
                buf = ""
                depth = max(depth, 0)
        if buf:
            logical.append((start, buf.strip()))

        for idx, raw in logical:
            line = raw.rstrip()
            stripped = line.strip()
            if not stripped:
                continue

            # --- declarations ------------------------------------------
            m = re.match(r"(?:static\s+)?func\s+(\w+)\s*\(([^)]*)\)", stripped)
            if m:
                locals_typed = {}
                for p in split_params(m.group(2)):
                    pm = re.match(r"(\w+)\s*:\s*([\w.\[\]]+)", p.strip())
                    if pm:
                        locals_typed[pm.group(1)] = generic_base(pm.group(2))
                continue
            if re.match(r"(class_name|extends|signal|@tool|@icon)\b", stripped):
                continue
            if re.match(r"class\s+\w+\s*:", stripped):
                continue
            em = re.match(r"enum\s+(\w+)?\s*\{", stripped)
            if em:
                if "}" not in stripped:
                    in_enum = 1
                continue
            if in_enum:
                if "}" in stripped:
                    in_enum = 0
                continue

            if re.match(r"^@\w+(\(.*\))?$", stripped):
                # annotation-only line (@export_group("..."), @tool, @icon ...);
                # annotation arguments may contain parens inside strings.
                continue
            vm = re.match(r"(?:@\w+(?:\([^)]*\))?\s+)*(?:var|const)\s+(\w+)(.*)$", stripped)
            if vm:
                name, rest = vm.group(1), vm.group(2)
                t = ""
                am = re.match(r"\s*:\s*([\w.\[\]]+)", rest)
                if am:
                    t = generic_base(am.group(1))
                    if not self._type_exists_in_file(am.group(1), gf):
                        self.error(gf.rel, idx,
                                   f"annotation/cast type `{generic_base(am.group(1))}` does not exist "
                                   f"(engine 4.4.1 ClassDB, project class_name or file-local type)")
                else:
                    im = re.match(r"\s*:=\s*(.*)$", rest)
                    if im:
                        t = self.infer_expr_type(im.group(1), gf, locals_typed, self_type, idx)
                locals_typed[name] = t
                # the RHS itself must be checked too
                if ":=" in rest:
                    self.check_expr(rest.split(":=", 1)[1], gf, locals_typed, self_type, idx)
                elif "=" in rest:
                    self.check_expr(rest.split("=", 1)[1], gf, locals_typed, self_type, idx)
                continue

            fm = re.match(r"for\s+(\w+)\s*(?::\s*([\w.\[\]]+))?\s+in\s+(.*)$", stripped)
            if fm:
                if fm.group(2):
                    locals_typed[fm.group(1)] = generic_base(fm.group(2))
                    if not self._type_exists_in_file(fm.group(2), gf):
                        self.error(gf.rel, idx,
                                   f"for-loop type `{generic_base(fm.group(2))}` does not exist")
                else:
                    locals_typed[fm.group(1)] = UNKNOWN
                self.check_expr(fm.group(3), gf, locals_typed, self_type, idx)
                continue

            # --- plain expressions --------------------------------------
            self.check_expr(stripped, gf, locals_typed, self_type, idx)

    # -- expression checking -------------------------------------------------
    def check_expr(self, expr: str, gf: GdClass, locals_typed: dict[str, str],
                   self_type: str, idx: int) -> None:
        self.expr_type(expr, gf, locals_typed, self_type, idx)

    def expr_type(self, expr: str, gf: GdClass, locals_typed: dict[str, str],
                  self_type: str, idx: int) -> str:
        toks = tokenize(expr)
        val = self._scan(toks, 0, len(toks), gf, locals_typed, self_type, idx)
        return val

    def _scan(self, toks: list[Tok], i: int, end: int, gf: GdClass,
              locals_typed: dict[str, str], self_type: str, idx: int) -> str:
        """Linear scan of a token range; checks every postfix chain and bare
        global; returns the type of the LAST primary chain seen (enough for
        `:=` inference)."""
        last_type = UNKNOWN
        saw_arith = False
        saw_cmp = False
        while i < end:
            t = toks[i]
            if t.kind == "kw" and t.text == "as":
                # `expr as Type`
                if i + 1 < end and toks[i + 1].kind == "ident":
                    tname = toks[i + 1].text
                    if not self._type_exists_in_file(tname, gf):
                        self.error(gf.rel, idx, f"cast to unknown type `{tname}`")
                    else:
                        last_type = generic_base(tname)
                    i += 2
                    continue
                i += 1
                continue
            if t.kind == "op":
                if t.text in "([{":
                    j = self._match(toks, i, end)
                    if t.text == "(" and i > 0 and toks[i - 1].kind == "ident":
                        # call args: the chain logic already consumed them
                        pass
                    elif t.text == "(":
                        last_type = self._scan(toks, i + 1, j, gf, locals_typed,
                                                 self_type, idx)
                        i = j + 1
                        last_type, i = self._run_postfix(last_type, "instance",
                                                         toks, i, end, gf,
                                                         locals_typed, self_type, idx)
                        continue
                    elif t.text == "{":
                        self._scan_dict(toks, i + 1, j, gf, locals_typed,
                                        self_type, idx)
                        last_type = "Dictionary"
                    else:
                        self._scan(toks, i + 1, j, gf, locals_typed, self_type, idx)
                        last_type = "Array"
                    i = j + 1
                    # `[...]` / `{...}` literals can be receivers too:
                    # `[&"a"].find(x)`, `{"k": v}.keys()`.
                    last_type, i = self._run_postfix(last_type, "instance",
                                                     toks, i, end, gf,
                                                     locals_typed, self_type, idx)
                    continue
                if t.text in ("==", "!=", "<", ">", "<=", ">="):
                    saw_cmp = True
                elif t.text in ("+", "-", "*", "/", "%", "**"):
                    saw_arith = True
                i += 1
                continue
            if t.kind == "kw":
                if t.text in ("await", "not", "if", "else", "elif", "in", "is",
                              "return", "while", "match", "when", "break",
                              "continue", "pass", "and", "or"):
                    if t.text in ("and", "or"):
                        saw_cmp = True
                    i += 1
                    continue
                if t.text in ("true", "false"):
                    last_type = "bool"
                elif t.text == "null":
                    last_type = UNKNOWN
                elif t.text == "self":
                    last_type = self_type or self._self_base(gf)
                elif t.text == "super":
                    last_type = self._super_type(gf)
                i += 1
                continue
            if t.kind == "string":
                if t.text.startswith("&"):
                    last_type = "StringName"
                elif t.text.startswith("^"):
                    last_type = "NodePath"
                else:
                    last_type = "String"
                i += 1
                last_type, i = self._run_postfix(last_type, "instance", toks, i,
                                                 end, gf, locals_typed, self_type, idx)
                continue
            if t.kind == "number":
                low = t.text.lower()
                is_hex = low.startswith("0x")
                last_type = "int" if (is_hex or "." not in t.text
                                      and "e" not in low) else "float"
                i += 1
                last_type, i = self._run_postfix(last_type, "instance", toks, i,
                                                 end, gf, locals_typed, self_type, idx)
                continue
            if t.kind == "ident":
                last_type, i = self._ident_chain(toks, i, end, gf, locals_typed,
                                                 self_type, idx)
                continue
            i += 1
        if saw_arith or saw_cmp:
            # a binary operator ran: the last primary is not the value
            return UNKNOWN
        return last_type

    def _scan_dict(self, toks: list[Tok], i: int, end: int, gf: GdClass,
                   locals_typed: dict[str, str], self_type: str, idx: int) -> None:
        """Scan a `{...}` dictionary literal. Keys are not expressions — each
        entry's VALUE gets a full `_scan` (so `(x as T).m()` inside a value is
        followed exactly like anywhere else)."""
        # pass 1: at bracket depth 0, split into entries and locate each
        # entry's key (a bare token followed by ':' or '=').
        entries: list[tuple[int, int]] = []   # (value_start, value_end)
        depth = 0
        expect_key = True
        value_start: int | None = None
        k = i
        while k < end:
            t = toks[k]
            if depth == 0:
                if expect_key and t.kind in ("ident", "kw", "string", "number") \
                        and k + 1 < end and toks[k + 1].text in (":", "="):
                    value_start = k + 2       # after key + separator
                    expect_key = False
                    k += 2
                    continue
                if t.text == ",":
                    if value_start is not None:
                        entries.append((value_start, k))
                    value_start = None
                    expect_key = True
                    k += 1
                    continue
            if t.text in "([{":
                depth += 1
            elif t.text in ")]}":
                depth -= 1
            k += 1
        if value_start is not None:
            entries.append((value_start, end))
        # pass 2: full-scan every value range.
        for vstart, vend in entries:
            self._scan(toks, vstart, vend, gf, locals_typed, self_type, idx)

    def _match(self, toks: list[Tok], i: int, end: int) -> int:
        """Index of the bracket closing toks[i]."""
        open_ch = toks[i].text
        close_ch = {"(": ")", "[": "]", "{": "}"}[open_ch]
        depth = 0
        j = i
        while j < end:
            if toks[j].text == open_ch:
                depth += 1
            elif toks[j].text == close_ch:
                depth -= 1
                if depth == 0:
                    return j
            j += 1
        return end - 1

    def _self_base(self, gf: GdClass) -> str:
        return self.project.project_base_engine(gf) or UNKNOWN

    def _super_type(self, gf: GdClass) -> str:
        base = gf.extends
        if not base:
            return UNKNOWN
        if self.project.class_by_name(base):
            return base
        if self.manifest.has_class(base):
            return base
        return UNKNOWN

    def _ident_chain(self, toks: list[Tok], i: int, end: int, gf: GdClass,
                     locals_typed: dict[str, str], self_type: str, idx: int) -> tuple[str, int]:
        """Resolve an identifier and any `.member`/`(args)` postfix chain."""
        name = toks[i].text
        i += 1

        # -- resolve the base ------------------------------------------------
        base_type = UNKNOWN
        context = "instance"

        if name in locals_typed:
            base_type = locals_typed[name]
        elif name == "self":
            base_type = self_type or self._self_base(gf)
        elif name == "super":
            base_type = self._super_type(gf)
        elif name in ENGINE_SINGLETONS:
            base_type = ENGINE_SINGLETONS[name]
        elif name in self.project.autoloads:
            base_type = name
        elif self.project.class_by_name(name) is not None:
            base_type = name
            context = "static"
        elif self.manifest.has_class(name):
            base_type = name
            context = "static"
        elif name in gf.inner_classes or name in gf.consts or name in gf.enum_values:
            base_type = OPAQUE if name in gf.inner_classes else UNKNOWN
        else:
            is_call = i < end and toks[i].text == "("
            selft = self_type or self._self_base(gf)
            self_members = self.members_of(selft) if selft else None
            if self_members is not None and self_members.get(name, {}).get("method"):
                # implicit self call: typed through the self chain's return type
                kind = self_members[name]["method"]
                base_type = kind.split(";", 1)[1] if ";" in kind else UNKNOWN
            elif is_call:
                self._check_global_call(name, toks, i, end, gf, locals_typed,
                                        self_type, idx)
            elif re.match(r"^[A-Z][A-Z0-9_]*$", name):
                ok = (name in self.manifest.global_constants
                      or name in GDSCRIPT_CONSTANTS
                      or name in ENGINE_SINGLETONS
                      or self.manifest.has_class(name)
                      or self.project.class_by_name(name) is not None
                      or (self_members is not None and name in self_members))
                if not ok:
                    self.error(gf.rel, idx,
                               f"bare constant `{name}` is not a @GlobalScope constant, "
                               f"engine class or project symbol")

        # -- postfix chain: `.member` and `(args)` in any alternation ----------
        base_type, i = self._run_postfix(base_type, context, toks, i, end,
                                         gf, locals_typed, self_type, idx)
        return base_type, i

    def _run_postfix(self, base_type: str, context: str, toks: list[Tok], i: int,
                     end: int, gf: GdClass, locals_typed: dict[str, str],
                     self_type: str, idx: int) -> tuple[str, int]:
        while i < end:
            if toks[i].text == ".":
                if i + 1 >= end or toks[i + 1].kind != "ident":
                    break
                member = toks[i + 1].text
                i += 2
                called = i < end and toks[i].text == "("
                if called:
                    j = self._match(toks, i, end)
                    self._scan(toks, i + 1, j, gf, locals_typed, self_type, idx)
                    i = j + 1
                base_type = self._check_member(base_type, context, member, called,
                                               gf, idx)
                context = "instance"
            elif toks[i].text == "(":
                j = self._match(toks, i, end)
                self._scan(toks, i + 1, j, gf, locals_typed, self_type, idx)
                i = j + 1
                if context == "static" and self.manifest.has_class(base_type):
                    pass  # native-struct constructor: type unchanged
                elif context == "static":
                    base_type = UNKNOWN
                else:
                    base_type = UNKNOWN
                context = "instance"
            elif toks[i].text == "[":
                j = self._match(toks, i, end)
                self._scan(toks, i + 1, j, gf, locals_typed, self_type, idx)
                i = j + 1
                base_type = UNKNOWN  # element type not tracked
                context = "instance"
            else:
                break
        return base_type, i

    def _check_global_call(self, name: str, toks: list[Tok], i: int, end: int,
                           gf: GdClass, locals_typed: dict[str, str],
                           self_type: str, idx: int) -> None:
        if name in gf.funcs:
            return
        if name in gf.inner_classes:
            return
        if name in LANGUAGE_GLOBALS:
            return
        if name in GLOBAL_RETURNS:
            return
        if name in self.manifest.global_functions:
            return
        # Bare `foo(...)` inside a method is implicit `self.foo(...)` — legal
        # whenever the self chain (project + engine base) knows the member.
        selft = self_type or self._self_base(gf)
        if selft:
            members = self.members_of(selft)
            if members is not None and name in members:
                return
        self.error(gf.rel, idx,
                   f"call to unknown global function `{name}(...)` — not in "
                   f"@GlobalScope (engine {self.manifest.engine_version}) nor "
                   f"on the implicit self chain")

    def _check_member(self, base_type: str, context: str, member: str,
                      called: bool, gf: GdClass, idx: int) -> str:
        """Validate one `base.member` access; return the access's type."""
        if base_type in (UNKNOWN, OPAQUE, "Variant"):
            return UNKNOWN
        # universal constructor: every Object-derived class + every project
        # class answers `.new()` (never documented per-class in the ClassDB).
        if member == "new" and self._is_object_derived(base_type):
            return base_type
        members = self.members_of(base_type)
        if members is None:
            return UNKNOWN
        info = members.get(member)
        display = base_type

        if member in OBJECT_UNIVERSAL and self._is_object_derived(base_type):
            return UNKNOWN

        if info is None:
            # Severity follows the 4.4.1 GDScript analyzer itself
            # (`gdscript_analyzer.cpp::reduce_identifier_from_base`): an unknown
            # member on a HARD builtin receiver is a compile error, while on an
            # Object-derived receiver it is UNSAFE_PROPERTY_ACCESS — resolved at
            # runtime, a warning at compile. Dictionary answers any `.key`.
            if base_type == "Dictionary":
                return UNKNOWN
            if base_type in BUILTIN_HARD_TYPES:
                near = self._nearest_member(member, members)
                self.error(gf.rel, idx,
                           f"`{display}` has no member `{member}` in engine "
                           f"{self.manifest.engine_version} — this is a compile "
                           f"error on a typed builtin receiver"
                           + (f" (nearest: `{near}`)" if near else ""))
            elif self.exists_anywhere(member):
                near = self._nearest_member(member, members)
                self.warning(gf.rel, idx,
                             f"`{display}` has no member `{member}` — dynamic/unsafe "
                             f"access; the name exists elsewhere"
                             + (f" (nearest on {display}: `{near}`)" if near else ""))
            else:
                self.error(gf.rel, idx,
                           f"`{display}` has no member `{member}` in engine "
                           f"{self.manifest.engine_version}, and no engine or "
                           f"project class has any such member — phantom reference")
            return UNKNOWN

        if info.get("signal"):
            if called:
                self.error(gf.rel, idx,
                           f"`{display}.{member}` is a signal and cannot be called; "
                           f"use `.emit(...)`")
                return UNKNOWN
            return "Signal"
        if info.get("inner"):
            return OPAQUE
        method_kind = info.get("method")
        if method_kind:
            static = method_kind.startswith("s")
            ret = method_kind.split(";", 1)[1] if ";" in method_kind else ""
            if context == "static" and not static:
                # `Class.instance_method` as a Callable reference is legal;
                # only a direct call is an error.
                if called:
                    self.error(gf.rel, idx,
                               f"`{display}.{member}(...)` called statically but is "
                               f"an instance method")
                    return ret
                return "Callable"
            if not called and not static and context == "instance":
                return "Callable"  # method reference
            if info.get("property") is None and info.get("constant") is None and not called \
                    and context == "static" and static:
                return ret
            return ret if ret else UNKNOWN
        if info.get("constant"):
            if called:
                self.error(gf.rel, idx,
                           f"`{display}.{member}` is a constant and cannot be called")
                return UNKNOWN
            return UNKNOWN
        if info.get("property"):
            if called:
                self.error(gf.rel, idx,
                           f"`{display}.{member}` is a property and cannot be called")
                return UNKNOWN
            return info.get("vartype", UNKNOWN) if not self.manifest.has_class(base_type) else UNKNOWN
        return UNKNOWN

    def _nearest_member(self, member: str, members: dict[str, dict]) -> str:
        best, best_d = "", 3
        for name in members:
            if abs(len(name) - len(member)) > 3:
                continue
            d = _edit_distance(member, name)
            if d < best_d:
                best, best_d = name, d
        return best

    def _is_object_derived(self, type_name: str) -> bool:
        cur = type_name
        seen = set()
        while cur and cur not in seen:
            seen.add(cur)
            if cur == "Object":
                return True
            entry = self.manifest.classes.get(cur)
            if entry is None:
                # project class: walk its chain
                gf = self.project.class_by_name(cur)
                if gf is None:
                    return False
                cur = gf.extends or ""
                continue
            cur = entry.get("inherits", "")
        return False

    # -- inference for `:=` ---------------------------------------------------
    def infer_expr_type(self, expr: str, gf: GdClass, locals_typed: dict[str, str],
                        self_type: str, idx: int) -> str:
        # Strip string bodies so literals are seen as tokens.
        return self.expr_type(expr, gf, locals_typed, self_type, idx)


# ---------------------------------------------------------------------------
# Scene / resource property checks
# ---------------------------------------------------------------------------

class SceneGate:
    def __init__(self, gate: Gate) -> None:
        self.gate = gate

    def run(self) -> None:
        paths: list[pathlib.Path] = []
        for d in ("scenes", "data", "tests"):
            base = ROOT / d
            if base.exists():
                paths.extend(sorted(base.rglob("*.tscn")))
                paths.extend(sorted(base.rglob("*.tres")))
        for path in paths:
            rel = path.relative_to(ROOT).as_posix()
            text = path.read_text(encoding="utf-8")
            if path.suffix == ".tres":
                self._check_tres(rel, text)
            else:
                self._check_tscn(rel, text)

    def _script_props(self, script_path: str) -> set[str]:
        """All vars authored by a script class (walks the project chain)."""
        local = ROOT / script_path.replace("res://", "")
        if not local.exists():
            return set()
        gf = self.gate.project.class_by_path(local)
        if gf is None:
            return set()
        out: set[str] = set()
        for klass in self.gate.project.extends_chain(gf):
            out |= set(klass.vars)
        return out

    def _check_props(self, rel: str, line_no: int, type_name: str, key: str,
                     extra_ok: set[str]) -> None:
        if key.startswith("metadata/"):
            return
        # Indexed/array properties the ClassDB cannot enumerate: the
        # AudioStreamRandomizer stream list and MeshInstance3D's per-surface
        # material overrides are serialized as `name_N/sub` pairs.
        if type_name == "AudioStreamRandomizer" and re.match(r"^stream_\d+/(stream|weight)$", key):
            return
        if type_name == "MeshInstance3D" and re.match(r"^surface_material_override/\d+$", key):
            return
        # Editor-authored layout memory, written into .tscn by the editor but
        # never a ClassDB property on runtime builds.
        if key in ("anchors_preset", "layout_mode", "layout_direction",
                   "editor_description"):
            return
        if key in extra_ok:
            return
        members = self.gate.members_of(type_name)
        if members is None:
            return
        info = members.get(key)
        if info is None or not info.get("property"):
            near = self._nearest(key, [k for k, v in members.items() if v.get("property")])
            self.gate.error(rel, line_no,
                            f"`{type_name}` has no property `{key}` in engine "
                            f"{self.gate.manifest.engine_version}"
                            + (f" (nearest: `{near}`)" if near else ""))

    @staticmethod
    def _nearest(key: str, candidates: list[str]) -> str:
        best, best_d = "", 3
        for c in candidates:
            d = _edit_distance(key, c)
            if d < best_d:
                best, best_d = c, d
        return best

    def _check_tres(self, rel: str, text: str) -> None:
        ext = self._ext_resources(text)
        # `script_class` names the project Resource subclass that owns the
        # authored properties — the engine type alone would know none of them.
        hm = re.search(r"\[gd_resource\s+type=\"(\w+)\"[^\]]*script_class=\"(\w+)\"", text)
        plain = re.search(r"\[gd_resource\s+type=\"(\w+)\"", text)
        resource_type: str | None = None
        if hm:
            resource_type = hm.group(2)
            if self.gate.project.class_by_name(hm.group(2)) is None:
                resource_type = hm.group(1)
        elif plain:
            resource_type = plain.group(1)
            if not self.gate.manifest.has_class(resource_type):
                self.gate.error(rel, 1,
                                f"gd_resource type `{resource_type}` not in engine ClassDB")

        cur_type: str | None = None
        cur_extra: set[str] = {"script", "resource_name", "resource_local_to_scene"}
        for line_no, line in enumerate(text.splitlines(), start=1):
            s = line.strip()
            sm = re.match(r"\[sub_resource\s+type=\"(\w+)\"", s)
            if sm:
                cur_type = sm.group(1)
                cur_extra = {"script", "resource_name", "resource_local_to_scene"}
                if not self.gate.manifest.has_class(cur_type):
                    self.gate.error(rel, line_no,
                                    f"sub_resource type `{cur_type}` not in engine ClassDB")
                continue
            if s.startswith("["):
                cur_type = resource_type if s == "[resource]" else None
                cur_extra = {"script", "resource_name", "resource_local_to_scene"}
                continue
            if not cur_type or "=" not in s or s.startswith(";"):
                continue
            key, _, value = s.partition("=")
            key = key.strip()
            if not re.match(r"^[\w/]+$", key):
                continue
            if key == "script":
                em = re.search(r'ExtResource\(\s*"?([\w-]+)"?\s*\)', value)
                if em and em.group(1) in ext:
                    cur_extra |= self._script_props(ext[em.group(1)])
                continue
            self._check_props(rel, line_no, cur_type, key, cur_extra)

    @staticmethod
    def _ext_resources(text: str) -> dict[str, str]:
        ext: dict[str, str] = {}
        for m in re.finditer(r"\[ext_resource\s+([^\]]*)\]", text):
            attrs = m.group(1)
            pm = re.search(r'path="([^"]+)"', attrs)
            im = re.search(r'id="([^"]+)"', attrs)
            if pm and im:
                ext[im.group(1)] = pm.group(1)
        return ext

    def _check_tscn(self, rel: str, text: str) -> None:
        lines = text.splitlines()
        ext = self._ext_resources(text)

        cur_type: str | None = None
        cur_extra: set[str] = set()
        cur_script: str | None = None
        node_block = False
        for line_no, line in enumerate(lines, start=1):
            s = line.strip()
            hm = re.match(r"\[node[^\]]*\btype=\"(\w+)\"[^\]]*\]", s)
            sm = re.match(r"\[sub_resource\s+type=\"(\w+)\"", s)
            if s.startswith("[node"):
                cur_type = hm.group(1) if hm else None
                cur_extra = {"name", "parent", "index", "owner", "groups",
                             "instance", "instance_placeholder", "type"}
                cur_script = None
                node_block = True
                if cur_type and not self.gate.manifest.has_class(cur_type):
                    self.gate.error(rel, line_no,
                                    f"node type `{cur_type}` not in engine ClassDB")
                continue
            if sm:
                cur_type = sm.group(1)
                cur_extra = {"script", "resource_name", "resource_local_to_scene"}
                cur_script = None
                node_block = False
                if not self.gate.manifest.has_class(cur_type):
                    self.gate.error(rel, line_no,
                                    f"sub_resource type `{cur_type}` not in engine ClassDB")
                continue
            if s.startswith("["):
                cur_type = None
                cur_extra = set()
                cur_script = None
                node_block = False
                continue
            if not cur_type or "=" not in s or s.startswith(";"):
                continue
            key, _, value = s.partition("=")
            key = key.strip()
            value = value.strip()
            if key == "script":
                em = re.search(r'ExtResource\(\s*"?([\w-]+)"?\s*\)', value)
                if em and em.group(1) in ext:
                    cur_script = ext[em.group(1)]
                    cur_extra |= self._script_props(cur_script)
                continue
            if node_block and key in cur_extra:
                continue
            self._check_props(rel, line_no, cur_type, key, cur_extra | {"script"})

        # [connection] blocks: signal on `from`, method on `to`
        nodes = self._node_types(lines)
        for line_no, line in enumerate(lines, start=1):
            m = re.match(r'\[connection\s+signal="([^"]+)".*from="([^"]+)".*to="([^"]+)".*method="([^"]+)"', line.strip())
            if not m:
                continue
            sig, src, dst, method = m.groups()
            src_type = nodes.get("." if src == "." else src) or nodes.get(src)
            if src_type:
                members = self.gate.members_of(src_type)
                if members is not None and not members.get(sig, {}).get("signal"):
                    self.gate.error(rel, line_no,
                                    f"scene connection: `{src_type}` has no signal `{sig}`")
            dst_type = nodes.get("." if dst == "." else dst) or nodes.get(dst)
            if dst_type:
                members = self.gate.members_of(dst_type)
                if members is not None and members.get(method) is None:
                    self.gate.error(rel, line_no,
                                    f"scene connection: `{dst_type}` has no method `{method}`")

    def _node_types(self, lines: list[str]) -> dict[str, str]:
        """node path -> type for nodes whose type is authored in this scene."""
        out: dict[str, str] = {}
        root_name: str | None = None
        for line in lines:
            m = re.match(r'\[node\s+name="([^"]+)"(?:\s+type="(\w+)")?([^\]]*)\]', line.strip())
            if not m:
                continue
            name, ntype, rest = m.groups()
            pm = re.search(r'parent="([^"]*)"', rest)
            parent = pm.group(1) if pm else None
            if parent is None:
                root_name = name
                path = "."
            else:
                path = name if parent == "." else f"{parent}/{name}"
            if ntype:
                out[path] = ntype
            elif root_name and path == ".":
                pass
        return out


def class_by_path_patch(self, path: pathlib.Path) -> GdClass | None:
    rel = path.relative_to(ROOT).as_posix() if path.is_absolute() else path.as_posix()
    for gf in self.files:
        if gf.rel == rel:
            return gf
    gf = GdClass(path)
    if not path.exists():
        return None
    gf.collect()
    self.files.append(gf)
    if gf.class_name:
        self.by_class.setdefault(gf.class_name, gf)
    return gf


Project.class_by_path = class_by_path_patch  # type: ignore[attr-defined]


def _edit_distance(a: str, b: str) -> int:
    if abs(len(a) - len(b)) > 3:
        return 99
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, start=1):
        cur = [i]
        for j, cb in enumerate(b, start=1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (ca != cb)))
        prev = cur
    return prev[-1]


# ---------------------------------------------------------------------------

def main() -> int:
    if not MANIFEST_PATH.exists():
        print(f"missing {MANIFEST_PATH.relative_to(ROOT)} — run "
              f"python3 tool/build_api_manifest.py", file=sys.stderr)
        return 1
    gate = Gate()
    for gf in gate.project.files:
        gate.check_gd(gf)
    SceneGate(gate).run()
    for w in sorted(set(gate.warnings)):
        print("  [unsafe] " + w)
    if gate.errors:
        print(f"engine-api contract: {len(gate.errors)} violation(s) "
              f"against Godot {gate.manifest.engine_version}"
              f" (+{len(set(gate.warnings))} unsafe-access warnings)")
        for e in sorted(set(gate.errors)):
            print("  " + e)
        return 1
    n = len(gate.project.files)
    print(f"engine-api contract: clean ({n} GDScripts + scenes/resources checked "
          f"against Godot {gate.manifest.engine_version} ClassDB, "
          f"{len(gate.manifest.classes)} classes; "
          f"{len(set(gate.warnings))} unsafe-access warnings reported)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
