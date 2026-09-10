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
        # Two bounds, not one: the frame's payout is capped outright (a 5 s hitch used to convert into
        # four seconds of DoT because the 64-tick budget is far above what a 4 s status needs), and the
        # accrual only counts the part of that frame the effect was alive for. The expiry clock is not
        # clamped, so a hitch cannot stretch a status's life to pay itself out more slowly.
        self.assertIn("var frame := minf(delta, MAX_PAYOUT_DELTA)",txt)
        self.assertIn("active_delta = minf(frame, remaining)",txt)
        self.assertIn("remaining = maxf(remaining - delta, 0.0)",txt)
        self.assertIn("const MAX_PAYOUT_DELTA := 0.5",txt)
    def test_music_manager_null_run_guard(self):
        txt=read("scripts/audio/music_manager.gd")
        self.assertIn("GameRoot.get_run()",txt)
        self.assertIn("if run != null",txt)
    def test_weapon_manager_avoids_shadowing(self):
        txt=read("scripts/weapons/weapon_manager.gd")
        self.assertIn("as StatusManager",txt)
        self.assertIn("sm.apply_effects(",txt)
        self.assertNotIn("sm.call(",txt)
    def test_wave_manager_rebinds_director_damage(self):
        txt=read("scripts/waves/wave_manager.gd")
        self.assertIn("func _rebind_player_damage()",txt)
        self.assertIn("_wired_health",txt)
if __name__=="__main__": unittest.main()
