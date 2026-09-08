"""Static regression guards; runtime/GPU validation lives in the opt-in Godot probe.

These checks do not claim that a GDScript program has executed or an APK was built.
"""
from pathlib import Path
import json
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


def read(path):
    return (ROOT / path).read_text(encoding="utf-8")


class AndroidPerformanceTests(unittest.TestCase):
    def test_shipped_audio_precedes_fallback_without_second_registration(self):
        registry = read("scripts/core/content_registry.gd")
        self.assertLess(registry.index('_register_audio_cues(loaded["audio"])'),
                        registry.index("AudioAssetIntegrator.new().register()"))
        self.assertLess(registry.index("AudioAssetIntegrator.new().register()"),
                        registry.index("ProceduralSfx.ensure_registered()"))
        self.assertNotIn("AudioAssetIntegrator.new()", read("scripts/main/main.gd"))

    def test_all_shipped_cues_can_skip_synthesis(self):
        source = read("scripts/audio/procedural_sfx.gd")
        section = source.split("const SFX_CUES:")[1].split("const MUSIC_CUES:")[0]
        required = set(re.findall(r'&"([^"]+)"', section))
        catalog = json.loads(read("assets/catalog.json"))["audio_cues"]
        data = {p.stem for p in (ROOT / "data/audio").iterdir()
                if p.suffix in (".tres", ".wav", ".ogg", ".mp3")}
        self.assertFalse(required - data - set(catalog))
        for metadata in catalog.values():
            for filename in metadata["files"]:
                self.assertTrue((ROOT / filename).is_file(), filename)
        # Five 6s, 22050Hz, mono 8-bit loops previously generated then replaced.
        self.assertIn("const MIX_RATE := 22050", source)
        self.assertIn("const MUSIC_LOOP_SECONDS := 6.0", source)
        self.assertEqual(5 * 6 * 22050, 661500)

    def test_rig_bounds_accept_non_spatial_children(self):
        source = read("scripts/visuals/character_visuals.gd")
        self.assertIn("static func _bounds(node: Node,", source)
        self.assertIn("if node is Node3D:", source)

    def test_enemy_feedback_uses_real_3d_properties_and_bounded_tween(self):
        source = read("scripts/enemies/enemy_feedback.gd")
        self.assertNotIn("_visual.modulate", source)
        self.assertNotIn('tween_property(_visual, "modulate"', source)
        self.assertIn("_feedback_tween.kill()", source)
        self.assertIn("mesh.material_overlay = _flash_material if color.a > 0.0 else null", source)
        self.assertIn("if _scaling_feedback:", source)

    def test_particle_pool_has_no_detached_node_template(self):
        source = read("scripts/visuals/effect_director.gd")
        self.assertNotRegex(source, r"var _burst_template:")
        claim = source.split("func _claim_burst(")[1].split("func _claim_ring(")[0]
        self.assertIn("add_child(b)", claim)
        self.assertIn("_bursts.append(b)", claim)
        self.assertIn("_bursts.size() < MAX_BURSTS", claim)

    def test_invalid_projectile_scene_is_freed(self):
        source = read("scripts/weapons/projectile_pool.gd")
        make = source.split("func _make_projectile()")[1].split("func _make_fallback_projectile()")[0]
        self.assertRegex(make, r"elif inst != null:\s*#[^\n]+\s*inst\.free\(\)")

    def test_tint_materials_allocated_only_once_per_pooled_object(self):
        for path in ("scripts/weapons/projectile.gd", "scripts/pickups/pickup.gd"):
            source = read(path)
            self.assertIn("if _tint_material == null:\n\t\t_tint_material = StandardMaterial3D.new()", source)
            self.assertIn("var mat := _tint_material", source)
            self.assertNotIn("var mat := StandardMaterial3D.new()", source)

    def test_damage_text_does_not_copy_active_array_each_frame(self):
        source = read("scripts/ui/damage_number_layer.gd")
        self.assertIn("range(_live.size() - 1, -1, -1)", source)
        self.assertIn("_live.remove_at(index)", source)
        self.assertNotIn("_live.duplicate()", source)
        self.assertNotIn("_live.erase(entry)", source)

    def test_android_cap_preserves_physics_and_survives_tier_changes(self):
        project = read("project.godot")
        self.assertIn("run/max_fps.android=60", project)
        self.assertIn("common/physics_ticks_per_second=60", project)
        self.assertIn("common/max_physics_steps_per_frame=6", project)
        monitor = read("scripts/utilities/performance_monitor.gd")
        self.assertIn('get_setting_with_override("application/run/max_fps")', monitor)
        self.assertNotIn("Engine.max_fps = 0", monitor)
        self.assertIn("func _exit_tree() -> void:", monitor)

    def test_android_exports_omit_test_resources_not_runtime_content(self):
        for path in ("export_presets.cfg", "export_presets.cfg.example"):
            source = read(path)
            self.assertIn('exclude_filter="tests/*,tool/*"', source)
            self.assertIn('export_filter="all_resources"', source)
            self.assertIn("assets/*.json", source)
            self.assertIn("ASSET_LICENSES/*.txt", source)

    def test_probe_is_isolated_and_not_shipped(self):
        script = read("tool/profile_android.sh")
        self.assertIn("XDG_DATA_HOME", script)
        self.assertIn("mktemp -d", script)
        self.assertIn("timeout 180s", script)
        self.assertIn("SCRIPT ERROR:", script)
        self.assertIn("PERF TESTS:", script)
        runtime = read("tests/integration/android_performance.gd")
        self.assertIn("--isolated-performance-tests", runtime)
        self.assertIn("OBJECT_ORPHAN_NODE_COUNT", runtime)
        self.assertIn("range(12)", runtime)
        self.assertNotIn("android_performance", read("project.godot"))


if __name__ == "__main__":
    unittest.main()
