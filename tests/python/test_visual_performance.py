#!/usr/bin/env python3
"""Wrapper that runs the offline visual/performance validator as a unittest suite."""
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TOOL = ROOT / "tool" / "validate_visual_performance.py"


class VisualPerformanceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            cls.json_path = Path(tmp.name)
        result = subprocess.run(
            [sys.executable, str(TOOL), "--json", str(cls.json_path)],
            capture_output=True, text=True, cwd=str(ROOT),
        )
        cls.proc = result
        try:
            cls.report = json.loads(cls.json_path.read_text())
        except Exception:
            cls.report = {"errors": -1, "warnings": -1, "issues": [], "categories": []}

    @classmethod
    def tearDownClass(cls):
        try:
            cls.json_path.unlink(missing_ok=True)
        except Exception:
            pass

    def _issues(self, cat):
        return [it for it in self.report.get("issues", []) if it.get("category") == cat]

    def _errors(self, cat):
        return [it for it in self._issues(cat) if it.get("severity") == "error"]

    def test_validator_exits_zero(self):
        self.assertEqual(self.proc.returncode, 0, f"validator failed: {self.proc.stdout}\n{self.proc.stderr}")

    def test_companions_clean(self):
        for tool in ["validate_geometry.py", "validate_level_flow.py", "validate_shooter_readiness.py", "validate_campaign.py"]:
            r = subprocess.run([sys.executable, str(ROOT / "tool" / tool)], capture_output=True, text=True, cwd=str(ROOT))
            self.assertEqual(r.returncode, 0, f"{tool} failed while visual ran: {r.stdout}\n{r.stderr}")

    def test_no_error_any_category(self):
        self.assertEqual(self.report.get("errors"), 0, f"visual errors: {json.dumps(self.report.get('issues',[]), indent=2)}")

    def test_no_warning_any_category(self):
        self.assertEqual(self.report.get("warnings"), 0, f"visual warnings: {json.dumps(self.report.get('issues',[]), indent=2)}")

    def test_mesh_complexity(self): self.assertEqual(self._errors("mesh_complexity"), [])
    def test_excessive_object_count(self): self.assertEqual(self._errors("excessive_object_count"), [])
    def test_texture_material(self): self.assertEqual(self._errors("texture_material_problems"), [])
    def test_lod(self): self.assertEqual(self._errors("lod_issues"), [])
    def test_collision(self): self.assertEqual(self._errors("collision_complexity"), [])
    def test_duplicate_materials(self): self.assertEqual(self._errors("duplicate_materials"), [])
    def test_huge_textures(self): self.assertEqual(self._errors("huge_textures"), [])
    def test_invisible_unused(self): self.assertEqual(self._errors("invisible_unused_objects"), [])
    def test_draw_calls(self): self.assertEqual(self._errors("draw_call_modular_pieces"), [])
    def test_lighting(self): self.assertEqual(self._errors("lighting_problems"), [])
    def test_probes(self): self.assertEqual(self._errors("reflection_probe_issues"), [])
    def test_navigation(self): self.assertEqual(self._errors("navigation_mesh_issues"), [])
    def test_streaming(self): self.assertEqual(self._errors("streaming_scene_organization"), [])
    def test_memory(self): self.assertEqual(self._errors("memory_performance_risks"), [])

    def test_json_round_trip(self):
        self.assertIsInstance(self.report.get("issues"), list)
        self.assertEqual(
            set(self.report.get("categories", [])),
            {"mesh_complexity","excessive_object_count","texture_material_problems","lod_issues",
             "collision_complexity","duplicate_materials","huge_textures","invisible_unused_objects",
             "draw_call_modular_pieces","lighting_problems","reflection_probe_issues",
             "navigation_mesh_issues","streaming_scene_organization","memory_performance_risks"}
        )


if __name__ == "__main__":
    unittest.main()
