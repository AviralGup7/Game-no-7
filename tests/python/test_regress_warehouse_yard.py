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


if __name__ == "__main__":
    unittest.main()
