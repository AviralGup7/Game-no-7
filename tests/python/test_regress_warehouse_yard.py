"""Regression: the Pit is an expanded warehouse yard, not random clutter."""
from __future__ import annotations

import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8", errors="ignore")


def func_body(rel: str, name: str) -> str:
    text = read(rel)
    m = re.search(r"\nfunc %s\(.*?(?=\nfunc |\Z)" % re.escape(name), text, re.S)
    if m is None:
        raise AssertionError("func %s() not found in %s" % (name, rel))
    return m.group(0)


class WarehouseYardTests(unittest.TestCase):
    def test_floor_and_half_match_the_expanded_pit(self):
        scene = read("scenes/arena/arena.tscn")
        self.assertIn("size = Vector2(38, 38)", scene)
        self.assertIn("interior_half = 18.0", scene)
        self.assertIn("0, 0, -16", scene)
        self.assertIn("16, 0, 0", scene)

    def test_default_composition_is_authored_not_scattered(self):
        body = func_body("scripts/arena/arena_decorator.gd", "_compose_default")
        self.assertIn("_build_warehouse_compound()", body)
        self.assertNotIn("_scatter(", body)
        self.assertNotIn("_place_structural(", body)
        self.assertNotIn("_open_spot(", body)

    def test_warehouse_shell_is_solid_architecture(self):
        src = read("scripts/arena/arena_decorator.gd")
        self.assertIn("func _place_structure(", src)
        self.assertIn("func _place_column_at(", src)
        self.assertIn("func _mount_warehouse_model(", src)
        self.assertIn("res://data/models/warehouse/scene.gltf", src)
        struct = func_body("scripts/arena/arena_decorator.gd", "_place_structure")
        self.assertIn("CollisionLayers.WORLD_BODY_LAYER", struct)
        self.assertIn("_blockers.append(", struct)
        self.assertNotIn("MAX_PROP_HALF_XZ", struct)
        self.assertTrue((ROOT / "data" / "models" / "warehouse" / "scene.gltf").is_file())
        self.assertTrue((ROOT / "ASSET_LICENSES" / "nicholas3d-warehouse.txt").is_file())

    def test_warehouse_model_is_mounted_and_fitted(self):
        compound = func_body("scripts/arena/arena_decorator.gd", "_build_warehouse_compound")
        self.assertIn("_mount_warehouse_model()", compound)
        self.assertIn("show_shell", compound)
        self.assertEqual(compound.count("const MAT_"), 0)
        mount = func_body("scripts/arena/arena_decorator.gd", "_mount_warehouse_model")
        self.assertIn("_instantiate_warehouse()", mount)
        self.assertIn("_fit_warehouse_to_compound(", mount)
        self.assertNotIn("HdMaterials.polish", mount)
        self.assertNotIn("0.7", mount)
        load = func_body("scripts/arena/arena_decorator.gd", "_instantiate_warehouse")
        self.assertIn("PackedScene", load)
        self.assertIn("GLTFDocument.new()", load)
        self.assertIn("append_from_file", load)
        self.assertIn("generate_scene", load)
        fit = func_body("scripts/arena/arena_decorator.gd", "_fit_warehouse_to_compound")
        self.assertIn("_combined_local_aabb", fit)
        self.assertIn("WAREHOUSE_TARGET", fit)
        self.assertIn("WAREHOUSE_CENTER", fit)
        src = read("scripts/arena/arena_decorator.gd")
        self.assertEqual(src.count('const MAT_METAL :='), 1)
        self.assertEqual(src.count('const MAT_BRICK :='), 1)
        self.assertEqual(src.count('const MAT_WOOD :='), 1)
        gltf = read("data/models/warehouse/scene.gltf")
        self.assertIn('"version": "2.0"', gltf)
        self.assertIn("scene.bin", gltf)
        self.assertTrue((ROOT / "data" / "models" / "warehouse" / "scene.bin").is_file())
        self.assertTrue(
            (ROOT / "data" / "models" / "warehouse" / "textures" / "WetConcrete_baseColor.png").is_file()
        )


if __name__ == "__main__":
    unittest.main()
