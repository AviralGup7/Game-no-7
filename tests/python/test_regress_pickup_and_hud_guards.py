"""Regression: pickup_manager & game_hud null guards — guards Batch10 fixes."""
from __future__ import annotations
import pathlib, unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]
def read(rel:str)->str: return (ROOT/rel).read_text(encoding="utf-8",errors="ignore")
class PickupHudGuardTests(unittest.TestCase):
    def test_pickup_manager_wave_guard(self):
        txt=read("scripts/pickups/pickup_manager.gd")
        self.assertIn('GameRoot.has_method("get_run")',txt)
        self.assertIn('var run: Variant = GameRoot.call("get_run")',txt)
        self.assertIn('if run is Dictionary:',txt)
        self.assertIn('elif "current_wave" in run:',txt)
    def test_pickup_currency_score_guards(self):
        txt=read("scripts/pickups/pickup_manager.gd")
        self.assertIn('has_method("add_currency")',txt)
        self.assertIn('has_method("add_score")',txt)
        self.assertIn('run_c is Dictionary',txt)
    def test_game_hud_run_guard(self):
        txt=read("scripts/ui/game_hud.gd")
        self.assertIn('if GameRoot == null or not GameRoot.has_method("get_run"):',txt)
        self.assertIn('var run: Variant = GameRoot.call("get_run")',txt)
        self.assertIn('if run == null:',txt)
        self.assertIn('if run is Dictionary:',txt)
if __name__=="__main__": unittest.main()
