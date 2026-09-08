"""Regression: combat log & status effect — guards Batch2 fixes."""
from __future__ import annotations
import pathlib, unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]
def read(rel:str)->str: return (ROOT/rel).read_text(encoding="utf-8",errors="ignore")
class CombatLogStatusTests(unittest.TestCase):
    def test_combat_log_source_field(self):
        txt=read("scripts/combat/combat_log.gd")
        self.assertIn('"source": String(source_id)',txt)
        self.assertIn('data.get("source"',txt)
        self.assertIn("damage_by_source",txt)
    def test_status_effect_tick_clamps(self):
        txt=read("scripts/status/status_effect.gd")
        self.assertIn("active_delta = minf(delta, remaining)",txt)
        self.assertIn("remaining = maxf(remaining - delta, 0.0)",txt)
    def test_music_manager_null_run_guard(self):
        txt=read("scripts/audio/music_manager.gd")
        self.assertIn('GameRoot.has_method("get_run")',txt)
        self.assertIn('var run: Variant = GameRoot.call("get_run")',txt)
        self.assertIn("if run != null:",txt)
        self.assertIn("if run is Dictionary:",txt)
    def test_weapon_manager_avoids_shadowing(self):
        txt=read("scripts/weapons/weapon_manager.gd")
        self.assertIn("var status_result: Variant = sm.call",txt)
        self.assertNotIn("var applied: Variant = sm.call(\"apply_effects\"",txt)
        self.assertIn("status_result is Dictionary",txt)
    def test_wave_manager_rebinds_director_damage(self):
        txt=read("scripts/waves/wave_manager.gd")
        self.assertIn("func _rebind_player_damage()",txt)
        self.assertIn("_wired_health",txt)
if __name__=="__main__": unittest.main()
