#!/usr/bin/env python3
"""Wrapper that runs the offline shooter-readiness validator as a unittest suite."""
import json, subprocess, sys, tempfile, unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TOOL = ROOT / "tool" / "validate_shooter_readiness.py"

class ShooterReadinessTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            cls.json_path = Path(tmp.name)
        result = subprocess.run(
            [sys.executable, str(TOOL), "--json", str(cls.json_path)],
            capture_output=True, text=True, cwd=str(ROOT))
        cls.proc = result
        try:
            cls.report = json.loads(cls.json_path.read_text())
        except Exception:
            cls.report = {"errors": -1, "warnings": -1, "issues": [], "categories": []}
    @classmethod
    def tearDownClass(cls):
        try: cls.json_path.unlink(missing_ok=True)
        except Exception: pass
    def _issues(self, cat): return [it for it in self.report.get("issues",[]) if it.get("category")==cat]
    def _errors(self, cat): return [it for it in self._issues(cat) if it.get("severity")=="error"]

    def test_validator_exits_zero(self):
        self.assertEqual(self.proc.returncode, 0, f"validator failed: {self.proc.stdout}\n{self.proc.stderr}")
    def test_companions_clean(self):
        for tool in ["validate_geometry.py", "validate_level_flow.py", "validate_campaign.py"]:
            r=subprocess.run([sys.executable, str(ROOT/"tool"/tool)], capture_output=True, text=True, cwd=str(ROOT))
            self.assertEqual(r.returncode,0, f"{tool} failed while shooter ran: {r.stdout}\n{r.stderr}")
    def test_no_error_any_category(self):
        self.assertEqual(self.report.get("errors"),0, f"shooter errors: {json.dumps(self.report.get('issues',[]), indent=2)}")
    def test_no_unacknowledged_warnings(self):
        """A warning either gets fixed or gets recorded with a reason in the validator."""
        open_warns=[it for it in self.report.get("issues",[])
                    if it.get("severity")=="warning" and not it.get("acknowledged")]
        self.assertEqual(open_warns, [], f"unacknowledged shooter warnings: {json.dumps(open_warns, indent=2)}")

    def test_acknowledged_notes_carry_a_rationale(self):
        for note in self.report.get("acknowledged_notes", []):
            self.assertTrue(str(note.get("rationale","")).strip(), f"acknowledged note without a rationale: {note}")

    def test_sightline_budgets_are_derived_from_the_authored_combat_data(self):
        """The LOS budgets follow the shipped weapons/enemies, not a hard-coded map."""
        import re
        reach=self.report.get("combat_reach",{})
        self.assertGreater(reach.get("weapons_read",0), 0, "no weapon resources were read")
        self.assertGreater(reach.get("enemies_read",0), 0, "no enemy resources were read")
        weapons=max(float(m.group(1)) for p in (ROOT/"data"/"weapons").glob("*.tres")
                    for m in [re.search(r"^attack_range\s*=\s*([0-9.]+)", p.read_text(), re.M)] if m)
        self.assertEqual(reach.get("weapon"), weapons)
        budgets=self.report.get("derived_budgets",{})
        self.assertEqual(budgets.get("room_los_error"), 8.0*weapons)
        self.assertEqual(budgets.get("cover_interval"), 8.0*weapons)
        # and every district lane that outgrows the warn budget has cover beside it
        for lane in self.report.get("sightlines",[]):
            if lane["los"] > budgets.get("room_los_warn", 0):
                self.assertLessEqual(lane["cover"], budgets.get("cover_reach", 0),
                                     f"{lane['sector']} has an uncovered {lane['los']} m fire lane")
    def test_cover_placement(self): self.assertEqual(self._errors("cover_placement"),[])
    def test_sightline_problems(self): self.assertEqual(self._errors("sightline_problems"),[])
    def test_exposed_corridors(self): self.assertEqual(self._errors("extremely_long_exposed_corridors"),[])
    def test_sniper(self): self.assertEqual(self._errors("unintended_sniper_sightlines"),[])
    def test_no_cover(self): self.assertEqual(self._errors("areas_with_no_cover"),[])
    def test_excessive_cover(self): self.assertEqual(self._errors("areas_with_excessive_cover"),[])
    def test_enemy_spawn(self): self.assertEqual(self._errors("enemy_spawn_feasibility"),[])
    def test_player_spawn_safety(self): self.assertEqual(self._errors("player_spawn_safety"),[])
    def test_arena_dimensions(self): self.assertEqual(self._errors("arena_combat_space_dimensions"),[])
    def test_chokepoints(self): self.assertEqual(self._errors("chokepoints"),[])
    def test_flanking(self): self.assertEqual(self._errors("flanking_routes"),[])
    def test_loops(self): self.assertEqual(self._errors("traversal_loops"),[])
    def test_navigation(self): self.assertEqual(self._errors("navigation_around_props"),[])
    def test_head_height(self): self.assertEqual(self._errors("head_height_weapon_obstructions"),[])
    def test_camping(self): self.assertEqual(self._errors("potential_camping_spots"),[])
    def test_json_round_trip(self):
        self.assertIsInstance(self.report.get("issues"), list)
        self.assertEqual(set(self.report.get("categories",[])),
                         {"cover_placement","sightline_problems","extremely_long_exposed_corridors","unintended_sniper_sightlines",
                          "areas_with_no_cover","areas_with_excessive_cover","enemy_spawn_feasibility","player_spawn_safety",
                          "arena_combat_space_dimensions","chokepoints","flanking_routes","traversal_loops","navigation_around_props",
                          "head_height_weapon_obstructions","potential_camping_spots"})

if __name__=="__main__": unittest.main()
