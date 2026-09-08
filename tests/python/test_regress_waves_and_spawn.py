"""Regression: waves, spawn, scoring & pickups — guards Batch4/6/9/10 fixes."""
from __future__ import annotations
import pathlib, re, unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]
def read(rel:str)->str: return (ROOT/rel).read_text(encoding="utf-8",errors="ignore")
class WavesSpawnTests(unittest.TestCase):
    def test_spawn_placer_uses_half_param(self):
        txt=read("scripts/enemies/spawn_placer.gd")
        self.assertIn("interior_half_value: float = 12.0",txt)
        self.assertIn("var half := interior_half_value",txt)
    def test_scoring_wave_floor(self):
        txt=read("scripts/waves/scoring.gd")
        self.assertRegex(txt,r"maxi\(wave_number,\s*1\)")
        self.assertRegex(txt,r"var w\s*:=\s*maxi\(wave_number,\s*1\)")
    def test_drop_table_chance_clamped(self):
        txt=read("scripts/pickups/drop_table.gd")
        self.assertIn("clampf",txt)
        self.assertIn("chance",txt.lower())
        self.assertIn("0.0, 1.0",txt)
    def test_wave_planner_int_division(self):
        txt=read("scripts/waves/wave_planner.gd")
        self.assertIn("extra // 2",txt)
        self.assertIn("mini(1 + extra // 2, 5)",txt)
        self.assertNotIn("mini(1 + extra / 2, 5)",txt)
if __name__=="__main__": unittest.main()
