"""Regression and verification tests for the 3D wall model and PBR assets."""
from __future__ import annotations

import json
from pathlib import Path
import struct
import unittest

ROOT = Path(__file__).resolve().parents[2]

from tool.validate_assets import check_model, gltf_document
from tool.validate_resources import check_file


class WallModelTests(unittest.TestCase):
    def test_wall_glb_exists_and_validates(self):
        glb_path = ROOT / "data/models/wall/wall.glb"
        self.assertTrue(glb_path.is_file(), "data/models/wall/wall.glb missing")
        doc = check_model(glb_path, {glb_path})
        self.assertEqual(doc["asset"]["version"], "2.0")
        self.assertTrue(len(doc["meshes"]) > 0)
        self.assertTrue(len(doc["materials"]) > 0)
        primitive = doc["meshes"][0]["primitives"][0]
        attrs = primitive["attributes"]
        for required_attr in ("POSITION", "NORMAL", "TANGENT", "TEXCOORD_0"):
            self.assertIn(required_attr, attrs, f"Missing {required_attr} attribute in wall mesh")
        self.assertIn("indices", primitive)

    def test_wall_gltf_and_bin_exist_and_validate(self):
        gltf_path = ROOT / "data/models/wall/scene.gltf"
        bin_path = ROOT / "data/models/wall/scene.bin"
        self.assertTrue(gltf_path.is_file(), "scene.gltf missing")
        self.assertTrue(bin_path.is_file(), "scene.bin missing")
        tex_dir = ROOT / "data/models/wall/textures"
        approved = {
            gltf_path.resolve(),
            bin_path.resolve(),
            (tex_dir / "Wall_albedo.png").resolve(),
            (tex_dir / "Wall_normal.png").resolve(),
            (tex_dir / "Wall_ORM.png").resolve(),
            (tex_dir / "Wall_emission.png").resolve(),
        }
        doc = check_model(gltf_path, approved)
        self.assertEqual(doc["asset"]["version"], "2.0")

    def test_pbr_textures_are_valid_pngs(self):
        tex_dir = ROOT / "data/models/wall/textures"
        for name in ("Wall_albedo.png", "Wall_normal.png", "Wall_ORM.png", "Wall_emission.png"):
            p = tex_dir / name
            self.assertTrue(p.is_file(), f"Missing texture {name}")
            data = p.read_bytes()
            self.assertTrue(data.startswith(b"\x89PNG\r\n\x1a\n"), f"{name} is not a valid PNG")

    def test_godot_wall_scene_is_valid(self):
        scene_path = ROOT / "scenes/environment/wall.tscn"
        self.assertTrue(scene_path.is_file(), "scenes/environment/wall.tscn missing")
        problems = []
        check_file(str(scene_path), problems)
        self.assertEqual(problems, [], f"wall.tscn resource problems: {problems}")

    def test_wall_materials_are_valid(self):
        problems = []
        for mat in ("assets/materials/arena_wall_brick.tres", "assets/materials/arena_wall_stone.tres"):
            p = ROOT / mat
            self.assertTrue(p.is_file(), f"{mat} missing")
            check_file(str(p), problems)
            content = p.read_text(encoding="utf-8")
            self.assertIn("Wall_albedo.png", content)
            self.assertIn("Wall_normal.png", content)
        self.assertEqual(problems, [], f"Material resource problems: {problems}")

    def test_wall_mesh_vertex_bounds(self):
        doc, binary = gltf_document(ROOT / "data/models/wall/wall.glb")
        pos_accessor_idx = doc["meshes"][0]["primitives"][0]["attributes"]["POSITION"]
        pos_accessor = doc["accessors"][pos_accessor_idx]
        self.assertEqual(pos_accessor["count"], 11857)
        self.assertAlmostEqual(pos_accessor["min"][0], -0.5004, delta=0.01)
        self.assertAlmostEqual(pos_accessor["max"][0], 0.5004, delta=0.01)


if __name__ == "__main__":
    unittest.main()
