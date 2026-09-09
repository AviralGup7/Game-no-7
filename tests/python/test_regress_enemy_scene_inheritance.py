"""Regression: every enemy archetype scene inherits enemy_base.tscn.

Found by the QA/release audit ("Architecture findings"): basic/fast/heavy properly
instanced `enemy_base.tscn`, while dasher/exploder/ranged/splitter/warlord were
hand-copied 16-17-node trees. Any edit to the base scene silently missed 5 of the
8 enemies — the most likely source of "works for some enemies" bugs.

Fix: all 8 archetype scenes are now child scenes that instance the base and override
only their unique bits (collision/material/marker overrides + added EnemyAnimator /
BossController nodes). The engine-side counterpart is
`tests/unit/test_enemy_scene_inheritance.gd` (instantiates all 8 scenes and checks
the same contract against live nodes); this guard checks the scene *files* so the
structural invariant fails fast even in the no-Godot CI stage.

Guards:
  1. each archetype scene roots on `instance=ExtResource("...enemy_base.tscn")`;
  2. no archetype scene re-declares a shared base node with `type=` (the copy-rot
     signature) — only scene-unique nodes may be added, and only under the root;
  3. resolving base + child overrides yields the exact shared wiring for all 8
     (HealthComponent/EnemyFeedback/EnemyAudio/EnemyStateMachine/StatusManager/
     NavigationAgent3D/ModifierReceiver...) and the pinned per-archetype overrides
     from the pre-refactor scenes.
"""
from __future__ import annotations
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
ENEMY_DIR = ROOT / "scenes" / "enemies"
BASE_SCENE = "res://scenes/enemies/enemy_base.tscn"
ARCHETYPES = [
    "basic", "fast", "heavy", "dasher", "exploder", "ranged", "splitter", "warlord",
]
# Shared nodes every archetype must carry (path -> expected type).
SHARED_NODES = {
    "CollisionShape3D": "CollisionShape3D",
    "VisualRoot": "Node3D",
    "VisualRoot/CharacterModel": "Node3D",
    "VisualRoot/CharacterModel/Body": "MeshInstance3D",
    "VisualRoot/AnimationPlayer": "AnimationPlayer",
    "TargetingOrigin": "Marker3D",
    "AttackOrigin": "Marker3D",
    "HealthComponent": "Node",
    "EnemyFeedback": "Node",
    "EnemyAudio": "Node",
    "EnemyStateMachine": "Node",
    "StatusManager": "Node",
    "NavigationAgent3D": "NavigationAgent3D",
    "ModifierReceiver": "Node",
}
# Shared nodes that must run exactly this script (path -> script res:// path).
SHARED_SCRIPTS = {
    "HealthComponent": "res://scripts/player/health_component.gd",
    "EnemyFeedback": "res://scripts/enemies/enemy_feedback.gd",
    "EnemyAudio": "res://scripts/enemies/enemy_audio.gd",
    "EnemyStateMachine": "res://scripts/enemies/enemy_state_machine.gd",
    "StatusManager": "res://scripts/status/status_manager.gd",
}
# Nodes an archetype may ADD (child-scene-unique); everything else must override-only.
ALLOWED_ADDED = {"EnemyAnimator", "BossController"}


# --------------------------------------------------------------------------
# Minimal .tscn section parser (sections + properties + Sub/Ext resource refs)
# --------------------------------------------------------------------------
SECTION_RE = re.compile(r"^\[(\w+)(.*)\]\s*$")


def _attrs(clause: str) -> dict:
    out = {}
    for m in re.finditer(r'(\w+)=(?:"([^"]*)"|(ExtResource\("[^"]*"\)))', clause):
        out[m.group(1)] = m.group(2) if m.group(2) is not None else m.group(3)
    return out


def parse_tscn(path: pathlib.Path) -> dict:
    scene = {"ext": {}, "sub": {}, "nodes": []}
    cur = None
    pending = 0
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if pending == 0 and SECTION_RE.match(line):
            m = SECTION_RE.match(line)
            kind, attrs = m.group(1), _attrs(m.group(2))
            if kind == "ext_resource":
                scene["ext"][attrs["id"]] = attrs
                cur = None
            elif kind == "sub_resource":
                cur = {"__type__": attrs.get("type"), "id": attrs.get("id"), "__props__": {}}
                scene["sub"][attrs["id"]] = cur
            elif kind == "node":
                cur = dict(attrs)
                cur["__props__"] = {}
                scene["nodes"].append(cur)
            else:
                cur = None
            continue
        if cur is None or not line:
            continue
        if "=" in line and not line.startswith("\t") and pending == 0 and cur is not None:
            key, _, val = line.partition("=")
            target = cur["__props__"] if "__props__" in cur else cur
            target[key.strip()] = val.strip()
            depth = val.count("{") + val.count("[") - val.count("}") - val.count("]")
            if depth > 0:
                pending = depth
            continue
        if pending > 0:
            target = cur["__props__"] if "__props__" in cur else cur
            last = list(target)[-1]
            target[last] += " " + line
            pending += line.count("{") + line.count("[") - line.count("}") - line.count("]")
    return scene


def ext_path(scene: dict, value: str) -> str | None:
    m = re.fullmatch(r'ExtResource\("([^"]+)"\)', value or "")
    if not m:
        return None
    return scene["ext"].get(m.group(1), {}).get("path")


def sub_props(scene: dict, value: str) -> dict | None:
    m = re.fullmatch(r'SubResource\("([^"]+)"\)', value or "")
    if not m:
        return None
    sub = scene["sub"].get(m.group(1))
    return sub


def resolve_scene(path: pathlib.Path) -> dict:
    """Effective tree of (possibly inherited) scene: node path -> {type, props}.

    Props values keep raw SubResource/ExtResource ids; helpers resolve them."""
    scene = parse_tscn(path)
    root = scene["nodes"][0] if scene["nodes"] else {}
    base_ref = ext_path(scene, root.get("instance", "")) if root else None
    tree: dict = {}
    if base_ref:
        tree, _base_scene = resolve_scene(ROOT / base_ref.replace("res://", ""))
        tree = {k: {"type": v["type"], "props": dict(v["props"])} for k, v in tree.items()}
    for node in scene["nodes"]:
        name = node.get("name", "?")
        parent = node.get("parent")
        full = "" if parent is None else (name if parent == "." else f"{parent}/{name}")
        props = dict(node.get("__props__", {}))
        if full in tree:
            tree[full]["props"].update(props)
            if node.get("type"):
                tree[full]["type"] = node["type"]
        else:
            tree[full] = {"type": node.get("type"), "props": props}
    if base_ref:
        for node in scene["nodes"]:
            name = node.get("name", "?")
            parent = node.get("parent")
            full = "" if parent is None else (name if parent == "." else f"{parent}/{name}")
            tree.setdefault(full, {"type": node.get("type"), "props": {}})
    return tree, scene


class EnemySceneInheritance(unittest.TestCase):
    def resolved_for(self, archetype: str):
        p = ENEMY_DIR / f"{archetype}_enemy.tscn"
        self.assertTrue(p.exists(), msg=f"missing scene for {archetype}")
        tree, scene = resolve_scene(p)
        return p, tree, scene

    def test_all_archetypes_instance_enemy_base(self):
        """Root of every archetype scene must instance enemy_base.tscn — the single
        shared definition. A hand-copied tree (root declared with type=) fails here."""
        for a in ARCHETYPES:
            p, tree, scene = self.resolved_for(a)
            root = scene["nodes"][0]
            self.assertIsNotNone(
                ext_path(scene, root.get("instance", "")),
                msg=f"{p.name}: root must be [node name=\"...\" instance=ExtResource(base)]",
            )
            self.assertEqual(
                ext_path(scene, root.get("instance", "")), BASE_SCENE,
                msg=f"{p.name}: root must instance {BASE_SCENE}, not a copy",
            )
            self.assertIsNone(
                root.get("type"),
                msg=f"{p.name}: instanced root must not re-declare a node type",
            )

    def test_no_redeclaration_of_shared_nodes(self):
        """Child scenes may override shared nodes (no type=) but never re-declare
        them as new typed nodes — that is the hand-copied-tree signature."""
        for a in ARCHETYPES:
            p, _tree, scene = self.resolved_for(a)
            for node in scene["nodes"][1:]:
                if node.get("type") is not None:
                    self.assertIn(
                        node.get("name"), ALLOWED_ADDED,
                        msg=(f"{p.name}: node '{node.get('name')}' is declared with type= "
                             f"{node['type']!r}; shared nodes must come from {BASE_SCENE}, "
                             f"only {sorted(ALLOWED_ADDED)} may be added by an archetype"),
                    )
                    self.assertEqual(
                        node.get("parent"), ".",
                        msg=f"{p.name}: added node '{node.get('name')}' must be a direct child of the root",
                    )

    def test_shared_wiring_resolves_identically_for_all_eight(self):
        """After resolving inheritance, every archetype carries the full shared
        node set with the base scripts — 8/8, not 3/8."""
        for a in ARCHETYPES:
            p, tree, scene = self.resolved_for(a)
            for path, expected_type in SHARED_NODES.items():
                self.assertIn(path, tree, msg=f"{p.name}: shared node {path} missing after inheritance")
                self.assertEqual(
                    tree[path]["type"], expected_type,
                    msg=f"{p.name}: shared node {path} type mismatch",
                )
            base_scene = parse_tscn(ENEMY_DIR / "enemy_base.tscn")
            for path, script in SHARED_SCRIPTS.items():
                # The script = ExtResource("id") value is usually inherited verbatim
                # from the base, so its id resolves against the base pool; a child
                # that re-wires the node (the copy-rot pattern) resolves against its own.
                props = tree[path]["props"]
                self.assertIn("script", props, msg=f"{p.name}: {path} lost its script wiring")
                ref = ext_path(scene, props["script"]) or ext_path(base_scene, props["script"])
                self.assertEqual(ref, script, msg=f"{p.name}: {path} script resolved to {ref}")

    def test_archetype_overrides_pinned(self):
        """Per-archetype override values from the pre-refactor hand-copied scenes,
        re-checked on the resolved tree: a lost or typo'd override fails here."""
        # (collision shape type, radius, height, nav path/target, animator extent)
        GOLD = {
            "basic":   ("CapsuleShape3D", "0.5", "1.6", "1.5", "1.2", None),
            "fast":    ("CapsuleShape3D", "0.5", "1.6", "1.5", "1.2", None),
            "heavy":   ("CapsuleShape3D", "0.5", "1.6", "1.5", "1.2", None),
            "dasher":  ("CapsuleShape3D", "0.4", "1.3", "1.5", "1.2", "0.85"),
            "exploder": ("SphereShape3D", "0.55", None, "1.5", "1.2", "1.9"),
            "ranged":  ("CapsuleShape3D", "0.45", "1.5", "1.5", "1.2", "1.7"),
            "splitter": ("CapsuleShape3D", "0.6", "1.5", "1.5", "1.2", "1.3"),
            "warlord": ("CapsuleShape3D", "0.9", "2.6", "2.0", "1.8", "2.6"),
        }
        for a, (stype, radius, height, nav_path, nav_target, extent) in GOLD.items():
            p, tree, scene = self.resolved_for(a)
            shape = sub_props(scene, tree["CollisionShape3D"]["props"].get("shape", ""))
            # Shared (base-owned) shapes live in the base scene's sub_resource pool.
            if shape is None:
                base_scene = parse_tscn(ENEMY_DIR / "enemy_base.tscn")
                shape = sub_props(base_scene, tree["CollisionShape3D"]["props"].get("shape", ""))
            self.assertIsNotNone(shape, msg=f"{p.name}: CollisionShape3D has no resolvable shape")
            self.assertEqual(shape["__type__"], stype, msg=f"{p.name}: collision shape type")
            self.assertEqual(shape["__props__"].get("radius"), radius, msg=f"{p.name}: collision radius")
            if height is not None:
                self.assertEqual(shape["__props__"].get("height"), height, msg=f"{p.name}: collision height")
            self.assertEqual(
                tree["NavigationAgent3D"]["props"].get("path_desired_distance"), nav_path,
                msg=f"{p.name}: nav path_desired_distance",
            )
            self.assertEqual(
                tree["NavigationAgent3D"]["props"].get("target_desired_distance"), nav_target,
                msg=f"{p.name}: nav target_desired_distance",
            )
            if extent is not None:
                anim = tree["EnemyAnimator"]["props"]
                self.assertEqual(anim.get("model_extent"), extent, msg=f"{p.name}: animator extent")
                self.assertEqual(anim.get("yaw_offset_degrees"), "180.0", msg=f"{p.name}: animator yaw")
                self.assertIn('"attack"', anim.get("animation_map", ""),
                              msg=f"{p.name}: animator lost its attack mapping")
                self.assertIn('"idle"', anim.get("animation_map", ""),
                              msg=f"{p.name}: animator lost its idle mapping")

    def test_warlord_boss_phases(self):
        """Warlord is the only archetype with a BossController; the three-phase plan
        must survive inheritance intact (thresholds drive the enrage contract).
        Sub-resource ids are resolved through the phase_plan reference itself, not
        pinned textually — the editor is free to regenerate local ids."""
        p, tree, scene = self.resolved_for("warlord")
        self.assertIn("BossController", tree, msg=f"{p.name}: BossController node missing")
        props = tree["BossController"]["props"]
        plan = props.get("phase_plan", "")
        ids = re.findall(r'SubResource\("([^"]+)"\)', plan)
        self.assertEqual(len(ids), 3, msg=f"{p.name}: phase plan must reference 3 sub-resources")
        thresholds = [scene["sub"][pid]["__props__"].get("threshold") for pid in ids]
        self.assertEqual(thresholds, ["1.0", "0.66", "0.33"], msg=f"{p.name}: phase thresholds drifted")
        for pid in ids:
            sub_script = ext_path(scene, scene["sub"][pid]["__props__"].get("script", ""))
            self.assertEqual(sub_script, "res://scripts/enemies/boss_phase_config.gd",
                             msg=f"{p.name}: phase {pid} not a BossPhaseConfig")
        # BossController must NOT leak into other archetypes.
        for a in ARCHETYPES:
            if a == "warlord":
                continue
            _p2, tree2, _s2 = self.resolved_for(a)
            self.assertNotIn("BossController", tree2, msg=f"{a}: unexpectedly has BossController")

    def test_base_scene_owns_shared_wiring(self):
        """enemy_base.tscn itself must keep the full shared contract (so 'edit the
        base' remains the single source of truth for all 8 children)."""
        tree, _ = resolve_scene(ENEMY_DIR / "enemy_base.tscn")
        for path, expected_type in SHARED_NODES.items():
            self.assertIn(path, tree, msg=f"enemy_base.tscn lost shared node {path}")
            self.assertEqual(tree[path]["type"], expected_type)
        for path, script in SHARED_SCRIPTS.items():
            props = tree[path]["props"]
            ref = ext_path(parse_tscn(ENEMY_DIR / "enemy_base.tscn"), props.get("script", ""))
            self.assertEqual(ref, script, msg=f"enemy_base.tscn {path} script wiring changed")


if __name__ == "__main__":
    unittest.main()
