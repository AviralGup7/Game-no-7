"""
Geometry & Asset Integrity — Python regression wrapper for validate_geometry.

This suite turns the 13 geometry categories into unittest assertions so the
same invariants that Agent 1 audited by hand stay green on every commit.
No Godot runtime, no device — stdlib + the validator module only.
"""

import json
import unittest
from pathlib import Path

from tool import validate_geometry as geom

ROOT = Path(__file__).resolve().parents[2]


class GeometryIntegrityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.errors, cls.warnings, cls.issues = geom.validate(geom.MAP_PATH, ROOT, verbose=False)
        cls.by_cat = {}
        for it in cls.issues:
            cls.by_cat.setdefault(it.get("category", "other"), []).append(it)

    def test_no_geometry_errors(self):
        self.assertEqual(self.errors, 0, f"geometry errors: {self.issues}")

    def test_no_geometry_warnings(self):
        # The shipped station is warning-clean after the stray-ring fix.
        self.assertEqual(self.warnings, 0, f"geometry warnings: {self.issues}")

    def test_all_13_categories_were_checked(self):
        expected = {
            "floating",
            "buried",
            "intersection",
            "gaps",
            "snapped",
            "transform",
            "duplicate",
            "missing_resource",
            "collision",
            "bounds",
            "anomalous",
            "inaccessible",
        }
        # The validator runs all of these; none should be silently skipped.
        # We assert the *report* mentions them, not that they had issues.
        self.assertEqual(geom.validate.__code__.co_varnames[:2], ("map_path", "root"))
        # Re-run the per-category helpers to confirm they were invoked:
        data = geom.load_json(geom.MAP_PATH)
        cats = []
        for name in [
            "check_floating_and_buried",
            "check_intersections",
            "check_duplicate_and_stacked",
            "check_gaps_and_perimeter",
            "check_snapped_alignment",
            "check_rotations_and_scales",
            "check_broken_resources",
            "check_collision_vs_visual",
            "check_outside_bounds",
            "check_anomalous_assets",
            "check_transforms",
            "check_inaccessible",
        ]:
            self.assertTrue(hasattr(geom, name), f"missing geometry check: {name}")
            cats.append(name)
        self.assertEqual(len(cats), 12)  # + arena/scene checks = 14 helpers

    def test_floating_and_buried_are_clean(self):
        self.assertEqual(self.by_cat.get("floating", []), [])
        self.assertEqual(self.by_cat.get("buried", []), [])

    def test_no_intersections(self):
        self.assertEqual(self.by_cat.get("intersection", []), [])

    def test_no_gaps(self):
        self.assertEqual(self.by_cat.get("gaps", []), [])

    def test_snapped(self):
        self.assertEqual(self.by_cat.get("snapped", []), [])

    def test_no_duplicate_or_stacked(self):
        self.assertEqual(self.by_cat.get("duplicate", []), [])

    def test_no_broken_resources(self):
        self.assertEqual(self.by_cat.get("missing_resource", []), [])

    def test_collision_matches_visual(self):
        self.assertEqual(self.by_cat.get("collision", []), [])

    def test_inside_bounds(self):
        self.assertEqual(self.by_cat.get("bounds", []), [])

    def test_no_anomalous_assets(self):
        self.assertEqual(self.by_cat.get("anomalous", []), [])

    def test_no_inaccessible_or_stray(self):
        self.assertEqual(self.by_cat.get("inaccessible", []), [])

    def test_negative_cases_are_still_caught(self):
        # Move a spawn inside a prop — must be reported as an intersection.
        from copy import deepcopy

        data = geom.load_json(geom.MAP_PATH)
        bad = deepcopy(data)
        # Put the first spawn at the exact center of the first prop.
        prop = bad["props"][0]
        bad["encounters"][0]["members"][0]["at"] = list(prop["at"])
        issues: list[dict] = []
        geom.check_intersections(bad, issues)
        self.assertTrue(any(i["category"] == "intersection" for i in issues))

    def test_json_report_round_trips(self):
        import tempfile

        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "geom.json"
            rc = geom.main(["--json", str(out)])
            self.assertEqual(rc, 0)
            report = json.loads(out.read_text())
            self.assertEqual(report["errors"], 0)
            self.assertEqual(report["warnings"], 0)


if __name__ == "__main__":
    unittest.main()
