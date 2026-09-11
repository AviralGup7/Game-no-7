"""Regression: HD realism pass — arena scene, sky/materials, renderer settings and
the per-actor material pass stay wired to the locked HD assets."""
from __future__ import annotations
import json
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8", errors="ignore")


class HdVisualsTests(unittest.TestCase):
    def test_arena_scene_is_hd_rebuild(self):
        txt = read("scenes/arena/arena.tscn")
        self.assertIn("ProceduralSkyMaterial", txt)
        self.assertNotIn(".hdr", txt)
        self.assertIn("arena_floor_rock.tres", txt)
        self.assertIn("arena_wall_brick.tres", txt)
        self.assertIn("torch_flicker.gd", txt)
        # Gameplay nodes preserved: collisions, markers, player start, lighting.
        for name in ("Collision", "SpawnPoints", "PlayerStart", "PickupSpawnPoints",
                     "Environment", "NavigationRegion3D"):
            self.assertIn(name, txt)
        self.assertIn('[node name="Sun" type="DirectionalLight3D" parent="Lighting"]', txt)
        # Structural: load_steps must match declared resources.
        first = txt.splitlines()[0]
        m = re.search(r"load_steps=(\d+)", first)
        self.assertIsNotNone(m)
        ext = len(re.findall(r"\[ext_resource", txt))
        sub = len(re.findall(r"\[sub_resource", txt))
        self.assertEqual(ext + sub + 1, int(m.group(1)))

    def test_renderer_settings_have_hd_quality_with_mobile_renderer(self):
        txt = read("project.godot")
        self.assertIn('renderer/rendering_method="mobile"', txt)
        self.assertIn("anti_aliasing/quality/msaa_3d=2", txt)
        self.assertIn("anisotropic_filtering_level=8", txt)
        self.assertIn("soft_shadow_filter_quality=3", txt)

    def test_station_themes_use_zero_bitmap_skies(self):
        txt = read("scripts/arena/arena.gd")
        self.assertIn("ProceduralSkyMaterial", txt)
        self.assertIn("theme.panorama_path", txt)
        skies = set()
        for arena_id in ("default_arena",):
            theme = read(f"data/arena_themes/{arena_id}.tres")
            self.assertIn('panorama_path = ""', theme)
            skies.add(re.search(r'^sky_top = (.+)$', theme, re.M).group(1))
        self.assertEqual(len(skies), 1)

    def test_hd_materials_polish_wired_on_all_mount_paths(self):
        hd = read("scripts/visuals/hd_materials.gd")
        self.assertIn("class_name HdMaterials", hd)
        self.assertIn("TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC", hd)
        for path in ("scripts/visuals/character_visuals.gd",
                     "scripts/enemies/enemy_animator.gd",
                     "scripts/arena/arena_decorator.gd"):
            self.assertIn("HdMaterials.polish", read(path))

    def test_manifest_locks_hd_downloads(self):
        manifest = json.loads((ROOT / "assets/manifest.json").read_text())
        sources = manifest["sources"]
        self.assertIn("threejs-pbr", sources)
        self.assertIn("godot-hd-materials", sources)
        paths = {entry["path"] for entry in manifest["files"]}
        for rel in ("assets/textures/panorama/spruit_sunrise_1k.hdr",
                    "assets/textures/rock/rock_albedo.png",
                    "assets/textures/brick/brick_albedo.jpg",
                    "ASSET_LICENSES/threejs-pbr.txt",
                    "ASSET_LICENSES/godot-hd-materials.txt"):
            self.assertIn(rel, paths)

    def test_arena_torch_flicker_is_deterministic(self):
        txt = read("scripts/arena/torch_flicker.gd")
        self.assertIn("class_name TorchFlicker", txt)
        self.assertIn("seed_value", txt)
        # Never uses a global/random RNG: phase comes from the seed only.
        self.assertNotIn("RandomNumberGenerator", txt)
        self.assertNotIn("randf", txt)


if __name__ == "__main__":
    unittest.main()
