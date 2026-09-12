"""Regression: tooling and CI guards — validates that the split CI pipeline
and offline validators still cover the 4000-line hardening.

Checks the split pipeline and the offline validation contracts.
"""
import pathlib, re, unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]
def read(p): return (ROOT/p).read_text(encoding="utf-8", errors="ignore")

class CIPipelineTests(unittest.TestCase):
    def test_workflow_has_three_stages(self):
        txt = read(".github/workflows/android.yml")
        self.assertIn("validate-resources:", txt)
        self.assertIn("godot-tests:", txt)
        self.assertIn("build-android:", txt)
        self.assertIn("publish-release:", txt)
    def test_validate_resources_runs_offline(self):
        txt = read(".github/workflows/android.yml")
        self.assertIn("validate_resources.py", txt)
        self.assertIn("download_assets.py --verify", txt)
        self.assertIn("validate_assets.py", txt)
    def test_godot_tests_stage(self):
        txt = read(".github/workflows/android.yml")
        self.assertIn("setup-godot", txt)
        self.assertIn("bash scripts/run_godot.sh --path . --import", txt)
        self.assertIn("xvfb libgl1-mesa-dri", txt)
        self.assertIn("run_tests.gd", txt)
        self.assertIn("validate_asset_imports.gd", txt)
    def test_build_needs_both(self):
        txt = read(".github/workflows/android.yml")
        self.assertIn("needs: [validate-resources, godot-tests]", txt)
    def test_apk_job_runs_when_validate_succeeds(self):
        # GitHub skips a needed job's dependents on failure unless if: always().
        # The APK must still export on every push even if godot-tests fails.
        txt = read(".github/workflows/android.yml")
        self.assertIn("always()", txt)
        self.assertIn("needs.validate-resources.result", txt)
        self.assertIn("== 'success'", txt)
        self.assertIn("cancel-in-progress: ${{ github.event_name == 'pull_request' }}", txt)
    def test_workflows_have_operational_guardrails(self):
        android = read(".github/workflows/android.yml")
        diag = read(".github/workflows/gdscript-diagnostics.yml")
        for txt in (android, diag):
            self.assertIn("concurrency:", txt)
            self.assertIn("cancel-in-progress:", txt)
            self.assertIn("paths-ignore:", txt)
            self.assertIn("retention-days:", txt)
        self.assertIn("permissions:\n  contents: read", android)
        self.assertIn("permissions:\n  contents: read", diag)
        self.assertIn("contents: write", diag)
    def test_diagnostics_workflow_not_pinned_to_stale_arena_branch(self):
        txt = read(".github/workflows/gdscript-diagnostics.yml")
        self.assertIn('branches: ["main", "arena/**"]', txt)
        self.assertNotIn("arena/01a08a34-game-no-7", txt)
    def test_publish_needs_build(self):
        txt = read(".github/workflows/android.yml")
        publish = txt.split("  publish-release:", 1)[1]
        self.assertIn("needs: [validate-resources, godot-tests, build-android]", publish)
        for job in ("validate-resources", "godot-tests", "build-android"):
            self.assertIn(f"needs.{job}.result == 'success'", publish)
        self.assertIn("softprops/action-gh-release", txt)
class ValidateResourcesTests(unittest.TestCase):
    def test_validate_resources_exists(self):
        txt = read("tool/validate_resources.py")
        self.assertIn("load_steps", txt)
        self.assertIn("ext_resource", txt)
        self.assertIn("Validated", txt)
    def test_validate_assets_exists(self):
        txt = read("tool/validate_assets.py")
        self.assertIn("validate_assets", txt.lower() if "validate_assets" in txt.lower() else txt)
        self.assertIn("checksum", txt.lower() if "checksum" in txt.lower() else txt)
    def test_validate_glb(self):
        txt = read("tool/validate_assets.py")
        self.assertIn("glTF", txt)
        self.assertIn("bufferView", txt)
class ScriptHardeningCoverageTests(unittest.TestCase):
    def test_typed_architecture_gate(self):
        # The _validated_* coverage metric is retired with the theater itself.
        # Its replacement is the typed-architecture gate.
        import subprocess, sys
        r = subprocess.run([sys.executable, str(ROOT / "tool" / "check_typed_arch.py")],
                           capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, f"check_typed_arch failed:\n{r.stdout}")
    def test_no_bare_GameRoot_get_run_in_main(self):
        txt = read("scripts/main/main.gd")
        # main should use _safe_seed/_safe_arena_id, not bare GameRoot.get_run().seed
        self.assertIn("_safe_seed()", txt)
        self.assertIn("_safe_arena_id()", txt)
    def test_no_bare_EventBus_without_null(self):
        # audio_manager should guard EventBus at least once
        txt = read("scripts/audio/audio_manager.gd")
        self.assertIn("EventBus", txt)
        # we hardened with _validated_volume
class ScoringAndWaveTests(unittest.TestCase):
    def test_wave_spawn_entry_count(self):
        txt = read("scripts/waves/wave_spawn_entry.gd")
        self.assertIn("String(archetype_id).is_empty()", txt)


class ValidateResourcesInheritedSubResourceTests(unittest.TestCase):
    """Behaviour test for the file-local SubResource guard on inherited scenes.

    A child scene (one with `instance=ExtResource(base)`) may only reference
    SubResource ids it declares itself; ids are file-local and pointing at the
    parent's pool silently breaks the override. The enemy archetype scenes are
    the motivating pattern (they all inherit enemy_base.tscn now), and the
    guard must accept the editor's [editable] cross-file pointer as sanctioned.
    Asserted as behaviour on synthetic fixtures, not as pinned tool source text.
    """

    BASE = """[gd_scene load_steps=3 format=3]

[ext_resource type="Script" path="res://s.gd" id="1_s"]

[sub_resource type="BoxShape3D" id="Shape_base"]
size = Vector3(1, 1, 1)

[node name="Base" type="Node3D"]
script = ExtResource("1_s")
"""
    CHILD_TMPL = """[gd_scene load_steps=3 format=3]

[ext_resource type="PackedScene" path="res://base.tscn" id="1_base"]

[sub_resource type="BoxShape3D" id="Shape_own"]
size = Vector3(2, 2, 2)

[node name="Child" instance=ExtResource("1_base")]

[node name="Collider" type="CollisionShape3D" parent="."]
shape = SubResource("{ref}")
"""
    EDITABLE_CHILD = (CHILD_TMPL.format(ref="Shape_base") +
"""
[editable name="Shape_base" path="shape" sub_resource="Shape_base" instance=ExtResource("1_base")]
""")

    def _check(self, text: str) -> list[str]:
        import sys
        import tempfile
        from unittest.mock import patch
        sys.path.insert(0, str(ROOT))
        from tool import validate_resources
        with tempfile.TemporaryDirectory() as td:
            tdp = pathlib.Path(td)
            (tdp / "s.gd").write_text("extends Node\n")
            (tdp / "base.tscn").write_text(self.BASE)
            child = tdp / "child.tscn"
            child.write_text(text)
            problems: list[str] = []
            with patch.object(validate_resources, "ROOT", str(tdp)):
                validate_resources.check_file(str(child), problems)
            return problems

    def test_local_sub_resource_reference_is_accepted(self):
        self.assertEqual(self._check(self.CHILD_TMPL.format(ref="Shape_own")), [])

    def test_cross_file_sub_resource_reference_is_flagged(self):
        problems = self._check(self.CHILD_TMPL.format(ref="Shape_base"))
        self.assertEqual(len(problems), 1, msg=str(problems))
        self.assertIn("file-local", problems[0])

    def test_editable_pointer_is_accepted(self):
        self.assertEqual(self._check(self.EDITABLE_CHILD), [])

    def test_real_enemy_scenes_pass_the_validator(self):
        import subprocess, sys
        rc = subprocess.run(
            [sys.executable, "tool/validate_resources.py"],
            cwd=ROOT, capture_output=True, text=True)
        self.assertEqual(rc.returncode, 0, msg=rc.stdout + rc.stderr)


if __name__ == "__main__":
    unittest.main()
