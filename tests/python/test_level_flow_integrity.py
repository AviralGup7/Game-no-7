#!/usr/bin/env python3
"""Wrapper that runs the offline level-flow validator as a unittest suite."""
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TOOL = ROOT / "tool" / "validate_level_flow.py"


class LevelFlowIntegrityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Run once; share JSON across per-category tests
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            cls.json_path = Path(tmp.name)
        result = subprocess.run(
            [sys.executable, str(TOOL), "--json", str(cls.json_path)],
            capture_output=True, text=True, cwd=str(ROOT)
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

    def _issues(self, category):
        return [it for it in self.report.get("issues", []) if it.get("category") == category]

    def _errors(self, category):
        return [it for it in self._issues(category) if it.get("severity") == "error"]

    def test_validator_exits_zero(self):
        self.assertEqual(self.proc.returncode, 0,
                         f"validator failed: {self.proc.stdout}\n{self.proc.stderr}")

    def test_geometry_companion_is_clean(self):
        # Agent 1 gate must remain green alongside flow
        geom = ROOT / "tool" / "validate_geometry.py"
        r = subprocess.run([sys.executable, str(geom)], capture_output=True, text=True, cwd=str(ROOT))
        self.assertEqual(r.returncode, 0, f"geometry failed while flow ran: {r.stdout}\n{r.stderr}")

    def test_campaign_topology_is_clean(self):
        camp = ROOT / "tool" / "validate_campaign.py"
        r = subprocess.run([sys.executable, str(camp)], capture_output=True, text=True, cwd=str(ROOT))
        self.assertEqual(r.returncode, 0, f"campaign failed: {r.stdout}\n{r.stderr}")

    def test_no_error_any_category(self):
        self.assertEqual(self.report.get("errors"), 0,
                         f"level-flow errors: {json.dumps(self.report.get('issues',[]), indent=2)}")

    def test_structure(self):
        self.assertEqual(self._errors("structure"), [], f"structure errors: {self._errors('structure')}")

    def test_navigation(self):
        self.assertEqual(self._errors("navigation"), [], f"navigation errors: {self._errors('navigation')}")

    def test_dead_ends(self):
        self.assertEqual(self._errors("dead_ends"), [], f"dead_ends errors: {self._errors('dead_ends')}")

    def test_blocked_corridors(self):
        self.assertEqual(self._errors("blocked_corridors"), [], f"blocked_corridors errors: {self._errors('blocked_corridors')}")

    def test_narrow_passages(self):
        self.assertEqual(self._errors("narrow_passages"), [], f"narrow_passages errors: {self._errors('narrow_passages')}")

    def test_door_alignment(self):
        self.assertEqual(self._errors("door_alignment"), [], f"door_alignment errors: {self._errors('door_alignment')}")

    def test_vertical(self):
        self.assertEqual(self._errors("vertical"), [], f"vertical errors: {self._errors('vertical')}")

    def test_connectivity(self):
        self.assertEqual(self._errors("connectivity"), [], f"connectivity errors: {self._errors('connectivity')}")

    def test_isolated_areas(self):
        self.assertEqual(self._errors("isolated_areas"), [], f"isolated_areas errors: {self._errors('isolated_areas')}")

    def test_campaign_path(self):
        self.assertEqual(self._errors("campaign_path"), [], f"campaign_path errors: {self._errors('campaign_path')}")

    def test_json_round_trip(self):
        self.assertIsInstance(self.report.get("issues"), list)
        self.assertIsInstance(self.report.get("categories"), list)
        self.assertEqual(set(self.report.get("categories", [])),
                         {"structure","navigation","dead_ends","blocked_corridors","narrow_passages",
                          "door_alignment","vertical","connectivity","isolated_areas","campaign_path"})

    def test_no_unacknowledged_warnings(self):
        """A warning either gets fixed or gets recorded with a reason in the validator.

        The gate is not "warnings are allowed": an unreviewed warning fails CI
        exactly like an error, so a new design note has to be written down in
        ACKNOWLEDGED_WARNINGS and docs/LEVEL_FLOW_AUDIT.md before it can pass.
        """
        open_warns = [it for it in self.report.get("issues", [])
                      if it.get("severity") == "warning" and not it.get("acknowledged")]
        self.assertEqual(open_warns, [],
                         f"unacknowledged level-flow warnings: {json.dumps(open_warns, indent=2)}")

    def test_acknowledged_notes_carry_a_rationale(self):
        notes = self.report.get("acknowledged_notes", [])
        self.assertIsInstance(notes, list)
        for note in notes:
            self.assertTrue(str(note.get("rationale", "")).strip(),
                            f"acknowledged note without a rationale: {note}")

    def test_report_describes_the_authored_topology(self):
        """The topology model is derived from the map, and the report proves it."""
        authored = json.loads((ROOT / "data/campaign/station_zero.json").read_text(encoding="utf-8"))
        topology = self.report.get("topology", {})
        self.assertEqual(topology.get("districts"), len(authored["sectors"]))
        self.assertEqual(topology.get("floors"), len(authored["floors"]))
        self.assertEqual(
            topology.get("connector_decks", 0) + topology.get("spurs", 0) + topology.get("perimeter_spines", 0),
            topology.get("floors", 0) - topology.get("districts", 0),
            f"every non-district floor must be classified: {topology}")
        pacing = self.report.get("pacing", {})
        self.assertLessEqual(pacing.get("total", float("inf")), pacing.get("total_budget", 0))
        self.assertLessEqual(pacing.get("max_leg", float("inf")), pacing.get("leg_budget", 0))


if __name__ == "__main__":
    unittest.main()
