"""Regression and verification tests for the 3D modular wall and ground models and PBR assets."""
from __future__ import annotations

import json
from pathlib import Path
import struct
import unittest

ROOT = Path(__file__).resolve().parents[2]

from tool.validate_assets import check_model, gltf_document
from tool.validate_resources import check_file


class WallAndGroundModelTests(unittest.TestCase):
    def test_wall_models_exist_and_validate(self):
        wall_models = [
            "data/models/wall/wall.glb",
            "data/models/wall_hazard/wall_hazard.glb",
            "data/models/wall_tech/wall_tech.glb",
            "data/models/wall_rusted/wall_rusted.glb",
        ]
        for rel_path in wall_models:
            glb_path = ROOT / rel_path
            self.assertTrue(glb_path.is_file(), f"{rel_path} missing")
            doc = check_model(glb_path, {glb_path.resolve()})
            self.assertEqual(doc["asset"]["version"], "2.0")
            self.assertTrue(len(doc["meshes"]) > 0)
            self.assertTrue(len(doc["materials"]) > 0)
            primitive = doc["meshes"][0]["primitives"][0]
            attrs = primitive["attributes"]
            for required_attr in ("POSITION", "NORMAL", "TANGENT", "TEXCOORD_0"):
                self.assertIn(required_attr, attrs, f"Missing {required_attr} in {rel_path}")
            self.assertIn("indices", primitive)

    def test_ground_models_exist_and_validate(self):
        ground_models = [
            "data/models/ground/ground.glb",
            "data/models/ground_hazard/ground_hazard.glb",
            "data/models/ground_tech/ground_tech.glb",
        ]
        for rel_path in ground_models:
            glb_path = ROOT / rel_path
            self.assertTrue(glb_path.is_file(), f"{rel_path} missing")
            doc = check_model(glb_path, {glb_path.resolve()})
            self.assertEqual(doc["asset"]["version"], "2.0")
            self.assertTrue(len(doc["meshes"]) > 0)
            self.assertTrue(len(doc["materials"]) > 0)
            primitive = doc["meshes"][0]["primitives"][0]
            attrs = primitive["attributes"]
            for required_attr in ("POSITION", "NORMAL", "TANGENT", "TEXCOORD_0"):
                self.assertIn(required_attr, attrs, f"Missing {required_attr} in {rel_path}")
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
        dirs = [
            ROOT / "data/models/wall/textures",
            ROOT / "data/models/wall_hazard/textures",
            ROOT / "data/models/wall_tech/textures",
            ROOT / "data/models/wall_rusted/textures",
            ROOT / "data/models/ground/textures",
            ROOT / "data/models/ground_hazard/textures",
            ROOT / "data/models/ground_tech/textures",
        ]
        for d in dirs:
            self.assertTrue(d.is_dir(), f"Missing texture directory {d}")
            pngs = list(d.glob("*.png"))
            self.assertGreaterEqual(len(pngs), 4, f"Expected at least 4 PBR maps in {d}")
            for p in pngs:
                data = p.read_bytes()
                self.assertTrue(data.startswith(b"\x89PNG\r\n\x1a\n"), f"{p} is not a valid PNG")

    def test_godot_environment_scenes_are_valid(self):
        scenes = [
            "scenes/environment/wall.tscn",
            "scenes/environment/wall_hazard.tscn",
            "scenes/environment/wall_tech.tscn",
            "scenes/environment/wall_rusted.tscn",
            "scenes/environment/ground.tscn",
            "scenes/environment/ground_hazard.tscn",
            "scenes/environment/ground_tech.tscn",
        ]
        for rel_scene in scenes:
            scene_path = ROOT / rel_scene
            self.assertTrue(scene_path.is_file(), f"{rel_scene} missing")
            problems = []
            check_file(str(scene_path), problems)
            self.assertEqual(problems, [], f"{rel_scene} resource problems: {problems}")

    def test_verification_renders_exist(self):
        renders = [
            ROOT / "data/models/wall/wall_render.png",
            ROOT / "data/models/wall/wall_variants_render.png",
            ROOT / "data/models/ground/ground_render.png",
            ROOT / "data/models/environment_showcase.png",
        ]
        for r in renders:
            self.assertTrue(r.is_file(), f"Verification render {r} missing")
            data = r.read_bytes()
            self.assertTrue(data.startswith(b"\x89PNG\r\n\x1a\n"), f"{r} is not a valid PNG")


if __name__ == "__main__":
    unittest.main()
