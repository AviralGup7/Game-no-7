"""Regression: combat damage & hitstop — guards Batch1 area_damage, payload, pool, hitstop."""
from __future__ import annotations
import pathlib, unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]
def read(rel:str)->str: return (ROOT/rel).read_text(encoding="utf-8",errors="ignore")
class CombatDamageTests(unittest.TestCase):
    def test_area_damage_tie_deterministic(self):
        txt=read("scripts/combat/area_damage.gd")
        self.assertIn("is_equal_approx(d, best_dist) and best == null",txt)
        self.assertIn("Strict < keeps candidate order stable on ties",txt)
    def test_damage_payload_deep_duplicate_and_timestamp(self):
        txt=read("scripts/combat/damage_payload.gd")
        self.assertIn("metadata.duplicate(true)",txt)
        self.assertIn("timestamp_msec = timestamp_msec",txt)
        self.assertIn("Preserve original timestamp",txt)
    def test_projectile_pool_emergency_fallback(self):
        txt=read("scripts/weapons/projectile_pool.gd")
        self.assertIn("config.duplicate(true)",txt)
        self.assertIn("emergency fallback",txt)
        self.assertIn("if p == null:",txt)
        self.assertIn("_make_projectile()",txt)
    def test_hitstop_restores_on_exit(self):
        txt=read("scripts/combat/hitstop_manager.gd")
        self.assertIn("func _exit_tree()",txt)
        self.assertIn("Engine.time_scale = 1.0",txt)
        self.assertIn("stale hitstop/slowmo never freezes",txt)
    def test_hitstop_stacks_with_max(self):
        txt=read("scripts/combat/hitstop_manager.gd")
        self.assertIn("_hitstop_left = maxf(_hitstop_left, duration)",txt)
        self.assertIn("MAX_HITSTOP_SECONDS",txt)
    def test_arena_hazards_stable_spike_key(self):
        txt=read("scripts/arena/arena_hazards.gd")
        self.assertIn("stable_id",txt)
        self.assertIn('spike_cd_%s" % stable_id',txt)
        self.assertNotIn('h.hash()',txt)
    def test_ranged_resolver_clamps_spread(self):
        txt=read("scripts/weapons/ranged_resolver.gd")
        self.assertIn("maxf(spread_degrees, 0.0)",txt)
        self.assertIn("clamped_spread",txt)
if __name__=="__main__": unittest.main()
