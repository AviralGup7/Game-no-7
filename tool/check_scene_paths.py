#!/usr/bin/env python3
"""Scene-path contract gate: the game's own node tree, checked offline.

WHY THIS GATE EXISTS
--------------------
The engine-api gate (check_engine_api.py) pins *engine* members against the
ClassDB. This gate pins the game's *own* tree contract: the node paths the
scripts hard-require at runtime. The tree navigates its scenes almost
exclusively through string-literal lookups — `get_tree().current_scene
.get_node("WorldRoot")`, `player.get_node("WeaponManager")`,
`shot.get_node("Visual/Mesh") as MeshInstance3D` — and per the pinned
engine's own docs (4.4.1-stable `Node.get_node`): "If `path` does not point
to a valid node, generates an error and returns null." A renamed or removed
node is therefore a runtime crash (or, for `get_node_or_null`, a permanently
dead lookup that silently returns null), and before this gate nothing offline
could see it: gdparse/gdlint have no scene awareness, and the headless suites
only exercise the paths their flows happen to touch. Existing ecosystem tools
that validate scenes (e.g. godot_doctor, the engine's own regression project)
all require a Godot binary, which this environment and its CI deliberately do
not depend on — so the contract is checked the same way the ClassDB one is:
with a hermetic, stdlib-only gate over the checked-in sources.

WHAT IS INDEXED (the provenance universe)
-----------------------------------------
1. Every `.tscn` in the project (excluding hidden/cache/build or `.gdignore` trees): each `[node ...]` entry contributes its name,
   its full relative path (built from `parent="..."`), its declared
   `type="..."`, its attached `script = ExtResource(...)`, and instantiated
   sub-scenes (`instance=ExtResource(...)`), resolved recursively.
2. Every `.gd` under `scripts/` and `tests/`: a `.name = "X"` assignment is
   a runtime-created node's name (the tree builds most managers this way —
   `container.name = "EnemyContainer"` in `main.gd`), so those names are
   first-class provenance too.
3. The `[autoload]` names in `project.godot` (children of the root viewport,
   addressable as `"/root/EventBus"` or `root.get_node("EventBus")`).

WHAT IS CHECKED (severity mirrors the engine gate's phantom model)
------------------------------------------------------------------
* Every string-literal `get_node(...)` in `scripts/` and `tests/` must
  resolve: the full path is declared in some scene, OR the longest
  scene-declared prefix leaves only segments that exist somewhere in the
  provenance universe (a runtime-attached chain like
  `VisualRoot/CharacterModel/CharacterVisual`, where the prefix is declared
  in `player.tscn` and the tail is named by `character_visuals.gd`).
  A path whose segments exist *nowhere* is a phantom -> ERROR. Hard
  `get_node` phantoms are the crash class; `get_node_or_null` phantoms are
  dead lookups — both fail the build, because a name that exists nowhere is
  wrong either way.
* Cast compatibility: `x.get_node("P") as T` where "P" fully resolves inside
  one or more scenes is checked against the node's effective class (script
  `class_name` if a script is attached, else the declared `type`, following
  `instance=` into the sub-scene's root). `as` returns *null* on a mismatch
  rather than erroring, so a drift here is a silent null; the gate fails when
  the node's class cannot be the cast target (walking the script `extends`
  chain and the ClassDB inheritance from tool/godot_api_manifest.json).
* Scene integrity, instance-aware: every `[node ... parent="P"]` must attach
  to a node the same file declares *or that an `instance=` brings in* — this
  is exactly the enemy-variant pattern (`dasher_enemy.tscn` instances
  `enemy_base.tscn` and overrides nodes inside its subtree), which a naive
  per-file check mis-reports. Godot refuses structurally broken files at
  load; this surfaces them without Godot.
* Scene-authored `NodePath(...)` properties (`light = NodePath("Light")` on
  the arena torches) must resolve relative to the node that carries them —
  the script side runs `get_node(light)` on them, so a dead one is the same
  runtime-error class as a phantom `get_node` literal.
* `%UniqueName` references (none today) would be checked against
  `unique_name_in_owner = true` nodes — the gate already understands the
  syntax so the first use is covered from day one.

Lookups whose argument is not a string literal (variables, format strings)
are counted and reported as dynamic — they are exactly the ones the
runtime-only suites can see, and the gate says so instead of pretending.

Exit status: 1 on any error, 0 otherwise. Hermetic: stdlib-only, no network,
no Godot binary. Run from anywhere: `python3 tool/check_scene_paths.py`.
"""

from __future__ import annotations

import json
import pathlib
import re
import os
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
MANIFEST_PATH = ROOT / "tool" / "godot_api_manifest.json"
GD_DIRS = ("scripts", "tests")

MAX_INSTANCE_DEPTH = 16


# --------------------------------------------------------------------------
# Script facts: class_name, extends — for cast compatibility
# --------------------------------------------------------------------------


def project_scene_paths(root: pathlib.Path) -> list[pathlib.Path]:
    """Prune generated trees before walking; cached third-party scenes are not
    runtime provenance and must not make a phantom project path appear valid.
    """
    scenes: list[pathlib.Path] = []
    for directory, names, files in os.walk(root):
        if ".gdignore" in files:
            names[:] = []
            continue
        names[:] = [name for name in names if not name.startswith(".")
                    and name not in {"build", "dist", "node_modules"}]
        scenes.extend(pathlib.Path(directory) / name for name in files if name.endswith(".tscn"))
    return sorted(scenes)


class ScriptFacts:
    """class_name / extends for every project script."""

    CN = re.compile(r"^class_name\s+(\w+)", re.M)
    EXT = re.compile(r"^extends\s+([A-Za-z_][\w./]*|\"[^\"]+\"|'[^']+')", re.M)

    def __init__(self) -> None:
        self.class_name: dict[str, str | None] = {}
        self.extends: dict[str, str] = {}
        self.cn_to_file: dict[str, str] = {}

    def add(self, rel: str, text: str) -> None:
        cn = self.CN.search(text)
        ex = self.EXT.search(text)
        self.class_name[rel] = cn.group(1) if cn else None
        if ex:
            tok = ex.group(1).strip("'\"")
        else:
            tok = "RefCounted"  # GDScript default base
        self.extends[rel] = tok
        if cn:
            self.cn_to_file[cn.group(1)] = rel

    def chain(self, rel: str) -> list[tuple[str, str]]:
        """Identity chain of a script: ('cn', name) entries then ('eng', base)."""
        out: list[tuple[str, str]] = []
        cur: str | None = rel
        seen: set[str] = set()
        while cur and cur not in seen:
            seen.add(cur)
            if cur not in self.class_name:
                return out
            if self.class_name[cur]:
                out.append(("cn", self.class_name[cur]))  # type: ignore[arg-type]
            tok = self.extends.get(cur, "RefCounted")
            if tok.endswith(".gd"):
                cur = tok[len("res://"):] if tok.startswith("res://") else tok
            else:
                out.append(("eng", tok))
                return out
        return out


# --------------------------------------------------------------------------
# Scene index
# --------------------------------------------------------------------------

class SceneIndex:
    """All .tscn files: node paths, types, scripts, instances, root classes."""

    NODE_HDR = re.compile(r"^\[node\s+([^\]]*)\]\s*$")
    EXT_HDR = re.compile(r"^\[ext_resource\s+([^\]]*)\]\s*$")
    KV = re.compile(r'(\w+)="([^"]*)"')
    INST = re.compile(r'instance=ExtResource\("([^"]+)"\)')
    SCRIPT_LINE = re.compile(r'^script = ExtResource\("([^"]+)"\)')
    NODEPATH_PROP = re.compile(r'^(\w+) = NodePath\("([^"]*)"\)')

    def __init__(self) -> None:
        self.ext: dict[str, dict[str, str]] = {}     # scene -> id -> res path
        self.paths: dict[str, set[str]] = {}          # scene -> relative paths
        self.node_type: dict[str, dict[str, str | None]] = {}
        self.node_script: dict[str, dict[str, str | None]] = {}
        self.node_instance: dict[str, dict[str, str | None]] = {}
        self.root_name: dict[str, str | None] = {}
        # scene -> [(node_path, prop_name, relative NodePath target)]
        self.nodepath_props: dict[str, list[tuple[str, str, str]]] = {}

    def add_scene(self, rel: str, text: str) -> None:
        ext: dict[str, str] = {}
        paths: set[str] = set()
        types: dict[str, str | None] = {}
        scripts: dict[str, str | None] = {}
        instances: dict[str, str | None] = {}
        nodepath_props: list[tuple[str, str, str]] = []
        root_name: str | None = None
        cur_path: str | None = None

        for line in text.splitlines():
            m = self.EXT_HDR.match(line)
            if m:
                d = dict(self.KV.findall(m.group(1)))
                if "id" in d and "path" in d:
                    ext[d["id"]] = d["path"]
                continue
            m = self.NODE_HDR.match(line)
            if m:
                d = dict(self.KV.findall(m.group(1)))
                im = self.INST.search(m.group(1))
                name = d.get("name")
                if not name:
                    continue
                parent = d.get("parent")
                if parent is None:
                    path = "."
                    root_name = name
                elif parent == ".":
                    path = name
                else:
                    path = f"{parent}/{name}"
                cur_path = path
                paths.add(path)
                types[path] = d.get("type")
                scripts[path] = None
                instances[path] = im.group(1) if im else None
                continue
            m = self.SCRIPT_LINE.match(line)
            if m and cur_path is not None:
                scripts[cur_path] = m.group(1)
                continue
            m = self.NODEPATH_PROP.match(line)
            if m and cur_path is not None:
                nodepath_props.append((cur_path, m.group(1), m.group(2)))

        self.ext[rel] = ext
        self.paths[rel] = paths
        self.node_type[rel] = types
        self.node_script[rel] = scripts
        self.node_instance[rel] = instances
        self.root_name[rel] = root_name
        self.nodepath_props[rel] = nodepath_props

    # -- structural integrity (instance-aware) --------------------------
    def instance_scene(self, rel: str, node_path: str) -> str | None:
        inst_id = self.node_instance.get(rel, {}).get(node_path)
        if not inst_id:
            return None
        tgt = self.ext.get(rel, {}).get(inst_id, "")
        tgt_rel = tgt[len("res://"):] if tgt.startswith("res://") else tgt
        return tgt_rel if tgt_rel in self.paths else None

    def node_exists(self, rel: str, path: str, depth: int = 0) -> bool:
        """Does `path` name a node of scene `rel` — locally declared, or inside
        a subtree brought in by an `instance=` (recursively)?"""
        if depth > MAX_INSTANCE_DEPTH:
            return False
        if path == "." or path in self.paths.get(rel, ()):
            return True
        for npath in self.paths.get(rel, ()):
            if npath == ".":
                sub = path
            elif path.startswith(npath + "/"):
                sub = path[len(npath) + 1:]
            else:
                continue
            tgt = self.instance_scene(rel, npath)
            if tgt and self.node_exists(tgt, sub, depth + 1):
                return True
        return False

    def parent_resolves(self, rel: str, parent: str, depth: int = 0) -> bool:
        """A parent= reference may point into an instantiated subtree."""
        return self.node_exists(rel, parent, depth)

    def integrity_errors(self) -> list[str]:
        out: list[str] = []
        for rel, ps in self.paths.items():
            for path in sorted(ps):
                if path == ".":
                    continue
                parent = path.rsplit("/", 1)[0] if "/" in path else "."
                if not self.parent_resolves(rel, parent):
                    name = path.rsplit("/", 1)[-1]
                    out.append(
                        f"{rel}: node \"{name}\" attaches to parent=\"{parent}\", "
                        f"which that scene declares neither locally nor inside any "
                        f"instantiated subtree (scene will not load)"
                    )
            # scene-authored NodePath properties resolve relative to the node
            # that carries them; a dead one is a runtime get_node error
            for node_path, prop, target in self.nodepath_props.get(rel, ()):
                if target in ("", ".", ".."):
                    continue
                base = node_path
                if target.startswith("../"):
                    continue  # parent-relative: context-dependent, left to runtime
                abs_path = target if base == "." else f"{base}/{target}"
                if not self.node_exists(rel, abs_path):
                    out.append(
                        f"{rel}: node \"{base.lstrip('./')}\" authors "
                        f"{prop} = NodePath(\"{target}\") but no node exists at "
                        f"\"{abs_path}\" in that scene or its instantiated subtrees "
                        f"(the script-side get_node will error)"
                    )
        return out

    # -- effective class ------------------------------------------------
    def node_class(self, rel: str, path: str, facts: ScriptFacts,
                   depth: int = 0) -> tuple[str, str] | None:
        """('cn', class_name) or ('eng', TypeName) for a declared node."""
        if depth > MAX_INSTANCE_DEPTH or rel not in self.paths or path not in self.paths[rel]:
            return None
        script_id = self.node_script[rel].get(path)
        if script_id:
            sp = self.ext[rel].get(script_id, "")
            sp_rel = sp[len("res://"):] if sp.startswith("res://") else sp
            cn = facts.class_name.get(sp_rel)
            if cn:
                return ("cn", cn)
        inst_id = self.node_instance[rel].get(path)
        if inst_id:
            tgt = self.ext[rel].get(inst_id, "")
            tgt_rel = tgt[len("res://"):] if tgt.startswith("res://") else tgt
            if tgt_rel in self.paths and self.root_name[tgt_rel]:
                return self.node_class(tgt_rel, ".", facts, depth + 1)
            return None
        typ = self.node_type[rel].get(path)
        if typ:
            return ("eng", typ)
        return None

    def owners_of(self, path: str) -> list[str]:
        return [rel for rel, ps in self.paths.items() if path in ps]


# --------------------------------------------------------------------------
# Compatibility (cast targets)
# --------------------------------------------------------------------------

class Compat:
    def __init__(self) -> None:
        self.classes: dict[str, dict] = {}
        if MANIFEST_PATH.exists():
            self.classes = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))["classes"]

    def engine_subclass(self, cls: str, anc: str) -> bool:
        cur: str | None = cls
        seen: set[str] = set()
        while cur and cur not in seen:
            if cur == anc:
                return True
            seen.add(cur)
            cur = self.classes.get(cur, {}).get("inherits") if cur in self.classes else None
        return False

    def cast_ok(self, effective: tuple[str, str], target: str,
                facts: ScriptFacts) -> bool | None:
        """True: node can be the target. False: provably not. None: unknown."""
        kind, name = effective
        if kind == "eng":
            if target in self.classes:
                return self.engine_subclass(name, target)
            if target in facts.cn_to_file:
                return False  # an engine-typed node is never a script class
            return None
        # script class: walk its identity chain
        rel = facts.cn_to_file.get(name)
        if not rel:
            return None
        chain = facts.chain(rel)
        for _kind, nm in chain:
            if nm == target:
                return True
        for kind2, nm in chain:
            if kind2 == "eng":
                if target in self.classes:
                    return self.engine_subclass(nm, target)
                if target in facts.cn_to_file:
                    return False
                return None
        return None


# --------------------------------------------------------------------------
# The gate
# --------------------------------------------------------------------------

LITERAL = r'(?:&|\^)?"([^"]+)"'
# (?<!\w) so a bare `get_node(...)` on implicit self and any `x.get_node(...)`
# both match, while a longer identifier ending in "get_node"
# (e.g. `safe_get_node`) never does.
GET_NODE_CALL = re.compile(r"(?<!\w)get_node(_or_null)?\(")
GET_NODE_CAST = re.compile(rf"(?<!\w)get_node\(\s*{LITERAL}\s*\)\s*as\s+(\w+)")
NAME_ASSIGN = re.compile(r"\.name\s*=\s*(?:&\"([^\"]+)\"|&'([^']+)'|\"([^\"]+)\")")


class ScenePathGate:
    def __init__(self) -> None:
        self.scenes = SceneIndex()
        self.facts = ScriptFacts()
        self.compat = Compat()
        self.scene_names: set[str] = set()
        self.runtime_names: set[str] = set()
        self.autoloads: set[str] = set()
        self.errors: list[str] = []
        self.warnings: list[str] = []
        self.hard_lookups = 0
        self.soft_lookups = 0
        self.dynamic_lookups = 0
        self.unique_refs = 0
        self.unique_nodes: set[str] = set()  # names with unique_name_in_owner

    # -- ingestion ------------------------------------------------------
    def add_scene(self, rel: str, text: str) -> None:
        self.scenes.add_scene(rel, text)
        for path in self.scenes.paths.get(rel, ()):  # type: ignore[arg-type]
            if path == ".":
                continue
            for seg in path.split("/"):
                self.scene_names.add(seg)

    def add_autoloads(self, project_godot_text: str) -> None:
        m = re.search(r"\[autoload\](.*?)(\n\[|\Z)", project_godot_text, re.S)
        if m:
            for am in re.finditer(r"^(\w+)=", m.group(1), re.M):
                self.autoloads.add(am.group(1))

    def ingest_script_names(self, text: str) -> None:
        for m in NAME_ASSIGN.finditer(text):
            self.runtime_names.add(m.group(1) or m.group(2) or m.group(3))

    def universe(self) -> set[str]:
        return self.scene_names | self.runtime_names | self.autoloads

    # -- resolution -----------------------------------------------------
    def resolve(self, path: str) -> tuple[bool, str]:
        """(resolved, how)."""
        p = path
        if p.startswith("/root/"):
            p = p[len("/root/"):]
        segs = [s for s in p.split("/") if s not in ("", ".")]
        if not segs:
            return True, "self"
        universe = self.universe()
        # full path declared in some scene
        for ps in self.scenes.paths.values():
            if p in ps or ("/".join(segs)) in ps:
                return True, "scene-full"
        # longest scene-declared prefix + union tail
        best = 0
        for ps in self.scenes.paths.values():
            for k in range(len(segs), 0, -1):
                if "/".join(segs[:k]) in ps:
                    best = max(best, k)
                    break
        tail = segs[best:]
        if best > 0 and all(s in universe or s == ".." for s in tail):
            return True, "scene-prefix+runtime"
        if all(s in universe or s == ".." for s in segs):
            return True, "runtime-chain"
        return False, "phantom"

    # -- checking -------------------------------------------------------
    @staticmethod
    def code_only(text: str) -> str:
        """Comment-free, string-content-free view; line structure preserved."""
        out: list[str] = []
        for line in text.splitlines():
            buf: list[str] = []
            i, n = 0, len(line)
            while i < n:
                c = line[i]
                if c == "#":
                    # pad, don't truncate: offsets must stay identical to the
                    # original so matches in this view map back to it
                    buf.append(" " * (n - i))
                    break
                if c in "\"'":
                    buf.append(c)
                    i += 1
                    while i < n:
                        if line[i] == "\\":
                            buf.append("  ")
                            i += 2
                            continue
                        if line[i] == c:
                            buf.append(c)
                            i += 1
                            break
                        buf.append(" ")
                        i += 1
                    continue
                buf.append(c)
                i += 1
            out.append("".join(buf))
        return "\n".join(out)

    def check_script(self, rel: str, text: str) -> None:
        uni = self.universe()
        # positions come from the comment/string-free view (same offsets as
        # the original up to any comment cutoff); literals from the original.
        clean = self.code_only(text)

        for m in GET_NODE_CALL.finditer(clean):
            line = clean[:m.start()].count("\n") + 1
            after = text[m.end():]
            lm = re.match(rf"\s*{LITERAL}", after)
            if not lm:
                self.dynamic_lookups += 1
                continue
            path = lm.group(1)
            if "*" in path or "?" in path:
                continue  # pattern lookups are find_child territory
            hard = m.group(1) is None
            if hard:
                self.hard_lookups += 1
            else:
                self.soft_lookups += 1
            ok, how = self.resolve(path)
            if not ok:
                missing = [s for s in path.split("/") if s not in uni and s not in ("..", "")]
                self.errors.append(
                    f"{rel}:{line}: {'get_node' if hard else 'get_node_or_null'}"
                    f"(\"{path}\") — no such node path exists in any scene or runtime "
                    f"name assignment (unresolvable segment(s): {', '.join(missing)}). "
                    f"A hard get_node errors at runtime; an or_null one is a dead lookup."
                )

        # cast compatibility on scene-resolved lookups
        for m in GET_NODE_CAST.finditer(clean):
            # re-extract from the original text: the clean view blanks the
            # string content, offsets are identical
            om = GET_NODE_CAST.match(text, m.start())
            if not om:
                continue
            path, target = om.group(1), om.group(2)
            owners = self.scenes.owners_of(path)
            if not owners:
                continue  # runtime-chain lookup: effective class unknowable
            line = clean[:m.start()].count("\n") + 1
            verdicts: list[bool | None] = []
            for o in owners:
                eff = self.scenes.node_class(o, path, self.facts)
                if eff is None:
                    verdicts.append(None)
                else:
                    verdicts.append(self.compat.cast_ok(eff, target, self.facts))
            if verdicts and all(v is False for v in verdicts):
                detail = []
                for o in owners:
                    eff = self.scenes.node_class(o, path, self.facts)
                    detail.append(f"{o}: {eff}")
                self.errors.append(
                    f"{rel}:{line}: get_node(\"{path}\") as {target} — the node's "
                    f"class cannot be {target} in any scene that declares the path; "
                    f"`as` would silently yield null. Declared as: {'; '.join(detail)}"
                )

        # %UniqueName references — the string-stripped view above keeps "%s"
        # format strings from posing as unique-name lookups (an `x % y` modulo
        # written without spaces could still match; the message is explicit
        # enough to review).
        for m in re.finditer(r"%([A-Za-z_]\w*)", clean):
            name = m.group(1)
            self.unique_refs += 1
            if name not in self.unique_nodes:
                self.errors.append(
                    f"{rel}: %{name} — no scene marks a node named \"{name}\" with "
                    f"unique_name_in_owner = true"
                )

    def check_unique_flags(self, rel: str, text: str) -> None:
        """Record node names that set unique_name_in_owner = true."""
        cur: str | None = None
        for line in text.splitlines():
            m = SceneIndex.NODE_HDR.match(line)
            if m:
                d = dict(SceneIndex.KV.findall(m.group(1)))
                cur = d.get("name")
                continue
            if cur and re.match(r"^\s*unique_name_in_owner\s*=\s*true", line):
                self.unique_nodes.add(cur)

    def finalize_scene_integrity(self) -> None:
        self.errors.extend(self.scenes.integrity_errors())

    # -- repo walk ------------------------------------------------------
    def load_repo(self) -> None:
        for p in project_scene_paths(ROOT):
            rel = p.relative_to(ROOT).as_posix()
            text = p.read_text(encoding="utf-8")
            self.add_scene(rel, text)
            self.check_unique_flags(rel, text)
        pg = ROOT / "project.godot"
        if pg.exists():
            self.add_autoloads(pg.read_text(encoding="utf-8"))
        for d in GD_DIRS:
            for p in sorted((ROOT / d).rglob("*.gd")):
                rel = p.relative_to(ROOT).as_posix()
                text = p.read_text(encoding="utf-8")
                self.facts.add(rel, text)
                self.ingest_script_names(text)
        self.finalize_scene_integrity()
        for d in GD_DIRS:
            for p in sorted((ROOT / d).rglob("*.gd")):
                rel = p.relative_to(ROOT).as_posix()
                self.check_script(rel, p.read_text(encoding="utf-8"))


def main() -> int:
    gate = ScenePathGate()
    gate.load_repo()
    for e in sorted(set(gate.errors)):
        print(f"  [error] {e}")
    n_scenes = len(gate.scenes.paths)
    n_paths = sum(len(ps) for ps in gate.scenes.paths.values())
    n_nodepaths = sum(len(v) for v in gate.scenes.nodepath_props.values())
    if gate.errors:
        print(f"\nscene-path contract: FAILED — {len(set(gate.errors))} error(s) "
              f"({n_scenes} scenes, {n_paths} node paths indexed; "
              f"{gate.hard_lookups} hard + {gate.soft_lookups} soft lookups checked, "
              f"{n_nodepaths} scene-authored NodePath props, "
              f"{gate.dynamic_lookups} dynamic skipped)")
        return 1
    print(f"scene-path contract: clean ({n_scenes} scenes, {n_paths} node paths; "
          f"{gate.hard_lookups} hard get_node + {gate.soft_lookups} get_node_or_null "
          f"literals resolved, {n_nodepaths} scene-authored NodePath props verified, "
          f"{gate.dynamic_lookups} dynamic arguments skipped, cast compatibility "
          f"checked against {MANIFEST_PATH.name})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
