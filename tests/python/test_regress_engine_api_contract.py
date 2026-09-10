"""The engine-API contract gate: the ClassDB of the pinned engine, offline.

Every phantom-member defect this project ever shipped survived gdparse/gdlint
because those are syntax checks with no ClassDB — the same hole documented in
CHANGELOG.md and GODOT_HANDOFF_RESOLUTION.md:

  * `AABB.has_area()` — the engine name is `has_volume()` (parse error: the
    arena scene died);
  * `fposmodf(...)` — the global is `fposmod` (script unloadable);
  * `MeshInstance3D.get_surface_material_override_count()` — real name
    `get_surface_override_material_count` (runtime abort silently skipped the
    rest of its test checks);
  * `NavigationAgent3D.path_height_tolerance` — real name `path_height_offset`
    (authored in `scenes/enemies/enemy_base.tscn`);
  * `PanoramaSkyMaterial.energy` — property does not exist (SCRIPT ERROR on
    every themed-arena load; the script-side copy was fixed, the .tscn copy
    was not, until tool/check_engine_api.py surfaced it);
  * `AudioStreamRandomizer.randomization_type` — the Godot-4 property is
    `playback_mode` (authored intent dropped in all nine data/audio/*.tres);
  * `Environment.background_sky` — the Godot-4 property is `sky` (answered
    only by a Godot-3 compat path; arena.tscn and arena.gd both carried it).

`tool/check_engine_api.py` pins the contract to `tool/godot_api_manifest.json`
(the 4.4.1-stable ClassDB reduced from the official source tag by
`tool/build_api_manifest.py`), and these tests pin the gate itself: the tree
stays clean, and every historical defect above is still caught if reintroduced
in any of its shapes (typed receiver, implicit self call, bare global, .tscn
property, .tres property).
"""

from __future__ import annotations

import importlib.util
import pathlib
import re
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")


def load_gate_module():
    spec = importlib.util.spec_from_file_location(
        "check_engine_api", ROOT / "tool" / "check_engine_api.py"
    )
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


class ManifestPinTests(unittest.TestCase):
    """The manifest is the pinned engine's own ClassDB — not a stale copy."""

    def test_manifest_exists_and_names_the_pinned_engine(self) -> None:
        mod = load_gate_module()
        manifest = mod.MANIFEST_PATH
        self.assertTrue(manifest.exists(), "tool/godot_api_manifest.json missing — "
                        "run `python3 tool/build_api_manifest.py`")
        raw = manifest.read_text(encoding="utf-8")
        self.assertIn('"engine_version":"4.4.1-stable"', raw)

    def test_manifest_matches_the_ci_engine_pin(self) -> None:
        workflow = read(".github/workflows/android.yml")
        m = re.search(r'GODOT_VERSION:\s*"([^"]+)"', workflow)
        self.assertIsNotNone(m, "GODOT_VERSION vanished from the CI workflow")
        mod = load_gate_module()
        manifest_version = mod.Manifest().engine_version
        self.assertEqual(manifest_version, m.group(1),
                         "the gate's manifest must be regenerated when the "
                         "engine pin moves (tool/build_api_manifest.py)")

    def test_manifest_covers_the_classes_the_history_broke(self) -> None:
        mod = load_gate_module()
        m = mod.Manifest()
        # corrected names are present ...
        self.assertIn("has_volume", m.members("AABB"))
        self.assertIn("get_surface_override_material_count", m.members("MeshInstance3D"))
        self.assertIn("path_height_offset", m.members("NavigationAgent3D"))
        self.assertIn("playback_mode", m.members("AudioStreamRandomizer"))
        self.assertIn("sky", m.members("Environment"))
        self.assertIn("fposmod", m.global_functions)
        # ... phantom names are absent (they would defeat the gate).
        self.assertNotIn("has_area", m.members("AABB"))
        self.assertNotIn("get_surface_material_override_count", m.members("MeshInstance3D"))
        self.assertNotIn("path_height_tolerance", m.members("NavigationAgent3D"))
        self.assertNotIn("randomization_type", m.members("AudioStreamRandomizer"))
        self.assertNotIn("fposmodf", m.global_functions)


class GateFixture:
    """One Gate + helpers to run synthetic snippets through it."""

    def __init__(self) -> None:
        self.mod = load_gate_module()
        self.gate = self.mod.Gate()

    def gd_errors(self, source: str) -> list[str]:
        with tempfile.NamedTemporaryFile(
            "w", suffix=".gd", delete=False, encoding="utf-8"
        ) as fh:
            fh.write(source)
            path = pathlib.Path(fh.name)
        try:
            gf = self.mod.GdClass(path)
            gf.collect()
            before = len(self.gate.errors)
            self.gate.check_gd(gf)
            return self.gate.errors[before:]
        finally:
            path.unlink(missing_ok=True)

    def tscn_errors(self, text: str) -> list[str]:
        sg = self.mod.SceneGate(self.gate)
        before = len(self.gate.errors)
        sg._check_tscn("synthetic.tscn", text)
        return self.gate.errors[before:]

    def tres_errors(self, text: str) -> list[str]:
        sg = self.mod.SceneGate(self.gate)
        before = len(self.gate.errors)
        sg._check_tres("synthetic.tres", text)
        return self.gate.errors[before:]


class HistoricalDefectTests(unittest.TestCase):
    """Each shipped phantom-member bug must be caught if reintroduced."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.fx = GateFixture()

    # --- GDScript-side ------------------------------------------------------
    def test_aabb_has_area_is_caught(self) -> None:
        errs = self.fx.gd_errors(
            "extends Node3D\n"
            "func f() -> bool:\n"
            "\tvar b := AABB()\n"
            "\treturn b.has_area()\n"
        )
        self.assertTrue(any("has_area" in e for e in errs), errs)

    def test_aabb_has_volume_is_accepted(self) -> None:
        errs = self.fx.gd_errors(
            "extends Node3D\n"
            "func f() -> bool:\n"
            "\tvar b := AABB()\n"
            "\treturn b.has_volume()\n"
        )
        self.assertEqual(errs, [])

    def test_fposmodf_global_is_caught(self) -> None:
        errs = self.fx.gd_errors(
            "extends RefCounted\n"
            "func f() -> float:\n"
            "\treturn fposmodf(1.5, 1.0)\n"
        )
        self.assertTrue(any("fposmodf" in e for e in errs), errs)

    def test_fposmod_global_is_accepted(self) -> None:
        errs = self.fx.gd_errors(
            "extends RefCounted\n"
            "func f() -> float:\n"
            "\treturn fposmod(1.5, 1.0)\n"
        )
        self.assertEqual(errs, [])

    def test_mesh_surface_override_typo_is_caught(self) -> None:
        # implicit-self call on an engine-typed script base
        errs = self.fx.gd_errors(
            "extends MeshInstance3D\n"
            "func f() -> int:\n"
            "\treturn get_surface_material_override_count()\n"
        )
        self.assertTrue(any("get_surface_material_override_count" in e for e in errs), errs)

    def test_mesh_surface_override_correct_name_is_accepted(self) -> None:
        errs = self.fx.gd_errors(
            "extends MeshInstance3D\n"
            "func f() -> int:\n"
            "\treturn get_surface_override_material_count()\n"
        )
        self.assertEqual(errs, [])

    def test_unknown_member_on_builtin_receiver_is_error(self) -> None:
        errs = self.fx.gd_errors(
            "extends Node3D\n"
            "func f() -> float:\n"
            "\tvar v := Vector3(1.0, 2.0, 3.0)\n"
            "\treturn v.lenght()\n"
        )
        self.assertTrue(any("lenght" in e for e in errs), errs)

    # --- .tscn-side ---------------------------------------------------------
    def test_nav_agent_path_height_tolerance_is_caught(self) -> None:
        errs = self.fx.tscn_errors(
            "[gd_scene format=3]\n\n"
            '[node name="Nav" type="NavigationAgent3D"]\n'
            "path_height_tolerance = 0.6\n"
        )
        self.assertTrue(any("path_height_tolerance" in e for e in errs), errs)

    def test_nav_agent_path_height_offset_is_accepted(self) -> None:
        errs = self.fx.tscn_errors(
            "[gd_scene format=3]\n\n"
            '[node name="Nav" type="NavigationAgent3D"]\n'
            "path_height_offset = 0.6\n"
        )
        self.assertEqual(errs, [])

    def test_panorama_energy_is_caught(self) -> None:
        errs = self.fx.tscn_errors(
            "[gd_scene format=3]\n\n"
            '[sub_resource type="PanoramaSkyMaterial" id="m"]\n'
            "energy = 0.9\n"
        )
        self.assertTrue(any("energy" in e for e in errs), errs)

    # --- .tres-side ----------------------------------------------------------
    def test_randomizer_randomization_type_is_caught(self) -> None:
        errs = self.fx.tres_errors(
            '[gd_resource type="AudioStreamRandomizer" format=3]\n\n'
            "[resource]\n"
            "randomization_type = 2\n"
        )
        self.assertTrue(any("randomization_type" in e for e in errs), errs)

    def test_randomizer_playback_mode_is_accepted(self) -> None:
        errs = self.fx.tres_errors(
            '[gd_resource type="AudioStreamRandomizer" format=3]\n\n'
            "[resource]\n"
            "playback_mode = 2\n"
        )
        self.assertEqual(errs, [])

    def test_script_class_properties_are_accepted(self) -> None:
        # project Resource subclasses author their own keys via script_class
        errs = self.fx.tres_errors(
            '[gd_resource type="Resource" script_class="EnemyConfig" format=3]\n\n'
            "[resource]\n"
            "archetype_id = &\"basic\"\n"
        )
        self.assertEqual(errs, [])


class RepoGateTests(unittest.TestCase):
    """The checked-in tree runs the gate clean."""

    def test_gate_is_clean_on_the_tree(self) -> None:
        r = subprocess.run(
            [sys.executable, str(ROOT / "tool" / "check_engine_api.py")],
            cwd=ROOT, capture_output=True, text=True, timeout=600,
        )
        self.assertEqual(r.returncode, 0,
                         "engine-api gate failed:\n" + r.stdout[-3000:])
        self.assertIn("engine-api contract: clean", r.stdout)

    def test_gate_covers_scripts_and_tests(self) -> None:
        mod = load_gate_module()
        gate = mod.Gate()
        rels = {gf.rel for gf in gate.project.files}
        self.assertIn("scripts/arena/arena.gd", rels)
        self.assertIn("tests/run_tests.gd", rels)
        self.assertGreater(len(rels), 200)


if __name__ == "__main__":
    unittest.main()
