"""The scene-path contract gate: the game's own node tree, pinned offline.

`tool/check_scene_paths.py` exists because the tree navigates its scenes
through string-literal lookups — `get_tree().current_scene.get_node
("WorldRoot")`, `player.get_node("WeaponManager")`, `shot.get_node
("Visual/Mesh") as MeshInstance3D` — and the pinned engine's own docs
(4.4.1-stable `Node.get_node`) say a missing path "generates an error and
returns null". Nothing before this gate could see a renamed or removed node
offline: gdparse/gdlint have no scene awareness, and the headless suites only
exercise the paths their flows happen to touch.

These tests pin the gate the same way test_regress_engine_api_contract.py
pins the ClassDB gate: the tree stays clean, and every error class the gate
claims to catch is proven catchable on synthetic content — phantom node
paths (hard and soft), structurally broken scenes, instance-subtree
attachments (the enemy-variant pattern), dead scene-authored NodePath
properties, impossible `as` casts, and `%UniqueName` references with no
unique-flagged node.
"""

from __future__ import annotations

import importlib.util
import pathlib
import subprocess
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))


def load_gate_module():
    spec = importlib.util.spec_from_file_location(
        "check_scene_paths", ROOT / "tool" / "check_scene_paths.py"
    )
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


AUTOLOAD_TEXT = '[autoload]\n\nEventBus="*res://scripts/core/event_bus.gd"\n'


class GateFixture:
    """Build a gate from synthetic scenes/scripts without touching the repo."""

    def __init__(self, mod, scenes=(), scripts=(), autoload_text=AUTOLOAD_TEXT):
        self.mod = mod
        self.gate = mod.ScenePathGate()
        for rel, text in scenes:
            # gate.add_scene (not scenes.add_scene): it also feeds the
            # scene-declared names into the provenance universe
            self.gate.add_scene(rel, text)
        self.gate.add_autoloads(autoload_text)
        for rel, text in scripts:
            self.gate.facts.add(rel, text)
            self.gate.ingest_script_names(text)
        for rel, text in scenes:
            self.gate.check_unique_flags(rel, text)
        self.gate.finalize_scene_integrity()
        for rel, text in scripts:
            self.gate.check_script(rel, text)


SIMPLE_SCENE = """[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/thing.gd" id="1_thing"]

[node name="Root" type="Node3D"]

[node name="Child" type="Node3D" parent="."]

[node name="Leaf" type="MeshInstance3D" parent="Child"]

[node name="Scripted" type="Node" parent="."]
script = ExtResource("1_thing")
"""

SCRIPT_FACTS = ("scripts/thing.gd", "class_name Thing\nextends Node\n")


class RepoGateTests(unittest.TestCase):
    """The checked-in tree runs the gate clean and is fully indexed."""

    def test_gate_is_clean_on_the_tree(self) -> None:
        r = subprocess.run(
            [sys.executable, str(ROOT / "tool" / "check_scene_paths.py")],
            cwd=ROOT, capture_output=True, text=True, timeout=600,
        )
        self.assertEqual(r.returncode, 0,
                         "scene-path gate failed:\n" + r.stdout[-4000:])
        self.assertIn("scene-path contract: clean", r.stdout)

    def test_gate_indexes_the_real_scenes_and_lookups(self) -> None:
        mod = load_gate_module()
        gate = mod.ScenePathGate()
        gate.load_repo()
        self.assertGreaterEqual(len(gate.scenes.paths), 18)
        self.assertIn("scenes/main/main.tscn", gate.scenes.paths)
        self.assertIn("scenes/player/player.tscn", gate.scenes.paths)
        # the contract the handoff-era flows depend on is indexed
        self.assertIn("WorldRoot", gate.scenes.paths["scenes/main/main.tscn"])
        self.assertIn("UIRoot/UI", gate.scenes.paths["scenes/main/main.tscn"])
        self.assertIn("WeaponManager", gate.scenes.paths["scenes/player/player.tscn"])
        # runtime-named managers and autoloads are in the provenance universe
        universe = gate.universe()
        for name in ("EnemyContainer", "ProjectilePool", "MusicManager",
                     "PerformanceMonitor", "CameraRig", "EventBus", "SaveManager"):
            self.assertIn(name, universe, f"{name} fell out of the universe")
        # no phantoms slipped through
        self.assertEqual(gate.errors, [])

    def test_cast_compatibility_uses_the_checked_in_manifest(self) -> None:
        mod = load_gate_module()
        self.assertTrue(mod.MANIFEST_PATH.exists(),
                        "tool/godot_api_manifest.json missing — the cast "
                        "compatibility walk needs the ClassDB inheritance chain")


class PhantomPathTests(unittest.TestCase):
    """A lookup naming a node that exists nowhere is an error, hard or soft."""

    def setUp(self) -> None:
        self.mod = load_gate_module()

    def errors_for(self, script_body: str, scenes=(("scenes/s.tscn", SIMPLE_SCENE),)):
        fx = GateFixture(
            self.mod,
            scenes=scenes,
            scripts=[SCRIPT_FACTS, ("scripts/user.gd", script_body)],
        )
        return fx.gate.errors

    def test_hard_get_node_phantom_is_caught(self) -> None:
        errs = self.errors_for(
            "extends Node\n"
            "func f() -> void:\n"
            "\tvar n := get_node(\"DefinitelyNotANode\")\n"
        )
        self.assertTrue(any("DefinitelyNotANode" in e for e in errs), errs)

    def test_soft_get_node_or_null_phantom_is_caught(self) -> None:
        errs = self.errors_for(
            "extends Node\n"
            "func f() -> void:\n"
            "\tvar n := get_node_or_null(\"Ghost/Branch\")\n"
        )
        self.assertTrue(any("Ghost/Branch" in e for e in errs), errs)

    def test_declared_scene_path_is_accepted(self) -> None:
        errs = self.errors_for(
            "extends Node\n"
            "func f() -> void:\n"
            "\tvar n := get_node(\"Child/Leaf\")\n"
        )
        self.assertEqual(errs, [])

    def test_runtime_assigned_name_is_accepted(self) -> None:
        errs = self.errors_for(
            "extends Node\n"
            "func f() -> void:\n"
            "\tvar holder := Node.new()\n"
            "\tholder.name = \"RuntimeManager\"\n"
            "\tvar n := get_tree().current_scene.get_node(\"RuntimeManager\")\n"
        )
        self.assertEqual(errs, [])

    def test_autoload_absolute_path_is_accepted(self) -> None:
        errs = self.errors_for(
            "extends Node\n"
            "func f() -> void:\n"
            "\tvar n := get_node(\"/root/EventBus\")\n"
        )
        self.assertEqual(errs, [])

    def test_scene_prefix_plus_runtime_tail_is_accepted(self) -> None:
        # VisualRoot/CharacterModel is declared; the tail is runtime-attached
        scene = SIMPLE_SCENE + '\n[node name="VisualRoot" type="Node3D" parent="."]\n' \
                               '\n[node name="CharacterModel" type="Node3D" parent="VisualRoot"]\n'
        errs = self.errors_for(
            "extends Node\n"
            "func f() -> void:\n"
            "\tvar w := Node3D.new()\n"
            "\tw.name = &\"Mounted\"\n"
            "\tvar n := get_node(\"VisualRoot/CharacterModel/Mounted\")\n",
            scenes=(("scenes/s.tscn", scene),),
        )
        self.assertEqual(errs, [])

    def test_parent_navigation_is_tolerated(self) -> None:
        errs = self.errors_for(
            "extends Node\n"
            "func f() -> void:\n"
            "\tvar n := get_node(\"../Child\")\n"
        )
        self.assertEqual(errs, [])

    def test_stringname_literal_is_checked_too(self) -> None:
        errs = self.errors_for(
            "extends Node\n"
            "func f() -> void:\n"
            "\tvar n := get_node(&\"PhantomName\")\n"
        )
        self.assertTrue(any("PhantomName" in e for e in errs), errs)


class SceneIntegrityTests(unittest.TestCase):
    """parent= must attach somewhere real — including instantiated subtrees."""

    def setUp(self) -> None:
        self.mod = load_gate_module()

    def test_orphan_parent_is_caught(self) -> None:
        broken = SIMPLE_SCENE + '\n[node name="Orphan" type="Node3D" parent="No/Such/Path"]\n'
        fx = GateFixture(self.mod, scenes=(("scenes/s.tscn", broken),))
        self.assertTrue(any("Orphan" in e for e in fx.gate.errors), fx.gate.errors)

    def test_instance_subtree_attachment_is_accepted(self) -> None:
        # the enemy-variant pattern: instance a base scene as root, then
        # attach/override nodes inside the base's declared subtree
        fx = GateFixture(self.mod, scenes=(
            ("scenes/base.tscn", SIMPLE_SCENE),
            ("scenes/variant.tscn",
             '[gd_scene load_steps=2 format=3]\n\n'
             '[ext_resource type="PackedScene" path="res://scenes/base.tscn" id="1_b"]\n\n'
             '[node name="Variant" instance=ExtResource("1_b")]\n\n'
             '[node name="Extra" type="Node3D" parent="Child"]\n\n'
             '[node name="Override" parent="Child/Leaf"]\n'),
        ))
        self.assertEqual(fx.gate.errors, [])

    def test_instance_subtree_does_not_excuse_phantom_parents(self) -> None:
        fx = GateFixture(self.mod, scenes=(
            ("scenes/base.tscn", SIMPLE_SCENE),
            ("scenes/variant.tscn",
             '[gd_scene load_steps=2 format=3]\n\n'
             '[ext_resource type="PackedScene" path="res://scenes/base.tscn" id="1_b"]\n\n'
             '[node name="Variant" instance=ExtResource("1_b")]\n\n'
             '[node name="Bad" type="Node3D" parent="Child/Nowhere"]\n'),
        ))
        self.assertTrue(any("Bad" in e for e in fx.gate.errors), fx.gate.errors)


class NodePathPropertyTests(unittest.TestCase):
    """Scene-authored NodePath props are get_node targets in disguise."""

    def setUp(self) -> None:
        self.mod = load_gate_module()

    def test_live_nodepath_property_is_accepted(self) -> None:
        scene = (
            '[gd_scene format=3]\n\n'
            '[node name="Root" type="Node3D"]\n\n'
            '[node name="Torch" type="Node3D" parent="."]\n'
            'light = NodePath("Light")\n\n'
            '[node name="Light" type="OmniLight3D" parent="Torch"]\n'
        )
        fx = GateFixture(self.mod, scenes=(("scenes/s.tscn", scene),))
        self.assertEqual(fx.gate.errors, [])

    def test_dead_nodepath_property_is_caught(self) -> None:
        scene = (
            '[gd_scene format=3]\n\n'
            '[node name="Root" type="Node3D"]\n\n'
            '[node name="Torch" type="Node3D" parent="."]\n'
            'light = NodePath("Lght")\n'
        )
        fx = GateFixture(self.mod, scenes=(("scenes/s.tscn", scene),))
        self.assertTrue(any("Lght" in e for e in fx.gate.errors), fx.gate.errors)


class CastCompatTests(unittest.TestCase):
    """`as T` after a scene-resolved get_node must be possible."""

    def setUp(self) -> None:
        self.mod = load_gate_module()

    def errors_for_cast(self, cast: str):
        script = (
            "extends Node\n"
            "func f(root: Node) -> void:\n"
            f"\tvar n := root.get_node(\"Child/Leaf\") as {cast}\n"
        )
        fx = GateFixture(self.mod,
                         scenes=(("scenes/s.tscn", SIMPLE_SCENE),),
                         scripts=[SCRIPT_FACTS, ("scripts/user.gd", script)])
        return fx.gate.errors

    def test_matching_engine_cast_is_accepted(self) -> None:
        self.assertEqual(self.errors_for_cast("MeshInstance3D"), [])

    def test_ancestor_cast_is_accepted(self) -> None:
        self.assertEqual(self.errors_for_cast("Node3D"), [])
        self.assertEqual(self.errors_for_cast("Node"), [])

    def test_impossible_engine_cast_is_caught(self) -> None:
        # Leaf is a MeshInstance3D; it can never be an AudioStreamPlayer
        errs = self.errors_for_cast("AudioStreamPlayer")
        self.assertTrue(any("as AudioStreamPlayer" in e for e in errs), errs)

    def test_script_class_on_engine_typed_node_is_caught(self) -> None:
        # Child is type="Node3D" with no script -> never a Thing
        script = (
            "extends Node\n"
            "func f(root: Node) -> void:\n"
            "\tvar n := root.get_node(\"Child\") as Thing\n"
        )
        fx = GateFixture(self.mod,
                         scenes=(("scenes/s.tscn", SIMPLE_SCENE),),
                         scripts=[SCRIPT_FACTS, ("scripts/user.gd", script)])
        self.assertTrue(any("as Thing" in e for e in fx.gate.errors), fx.gate.errors)

    def test_script_attached_cast_is_accepted(self) -> None:
        script = (
            "extends Node\n"
            "func f(root: Node) -> void:\n"
            "\tvar n := root.get_node(\"Scripted\") as Thing\n"
        )
        fx = GateFixture(self.mod,
                         scenes=(("scenes/s.tscn", SIMPLE_SCENE),),
                         scripts=[SCRIPT_FACTS, ("scripts/user.gd", script)])
        self.assertEqual(fx.gate.errors, [])

    def test_runtime_chain_cast_is_not_falsely_flagged(self) -> None:
        # path only resolves through runtime names -> effective class unknown
        script = (
            "extends Node\n"
            "func f(root: Node) -> void:\n"
            "\tvar w := Node.new()\n"
            "\tw.name = \"Mounted\"\n"
            "\tvar n := root.get_node(\"Mounted\") as Node3D\n"
        )
        fx = GateFixture(self.mod,
                         scenes=(("scenes/s.tscn", SIMPLE_SCENE),),
                         scripts=[SCRIPT_FACTS, ("scripts/user.gd", script)])
        self.assertEqual(fx.gate.errors, [])


class UniqueNameTests(unittest.TestCase):
    """%Name requires a unique_name_in_owner node somewhere."""

    def setUp(self) -> None:
        self.mod = load_gate_module()

    def test_unflagged_unique_ref_is_caught(self) -> None:
        script = (
            "extends Node\n"
            "func f() -> void:\n"
            "\tvar n := get_node(%SaveSlot)\n"
        )
        fx = GateFixture(self.mod,
                         scenes=(("scenes/s.tscn", SIMPLE_SCENE),),
                         scripts=[SCRIPT_FACTS, ("scripts/user.gd", script)])
        self.assertTrue(any("%SaveSlot" in e for e in fx.gate.errors), fx.gate.errors)

    def test_flagged_unique_ref_is_accepted(self) -> None:
        scene = SIMPLE_SCENE + (
            '\n[node name="SaveSlot" type="Node" parent="."]\n'
            'unique_name_in_owner = true\n'
        )
        script = (
            "extends Node\n"
            "func f() -> void:\n"
            "\tvar n := get_node(%SaveSlot)\n"
        )
        fx = GateFixture(self.mod,
                         scenes=(("scenes/s.tscn", scene),),
                         scripts=[SCRIPT_FACTS, ("scripts/user.gd", script)])
        self.assertEqual(fx.gate.errors, [])


if __name__ == "__main__":
    unittest.main()
