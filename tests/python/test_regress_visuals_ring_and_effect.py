"""Regression: ring_fade & effect_director — guards Batch3 visuals fixes."""
from __future__ import annotations
import pathlib, unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]
def read(rel:str)->str: return (ROOT/rel).read_text(encoding="utf-8",errors="ignore")
class VisualsTests(unittest.TestCase):
    def test_ring_fade_resets_alpha(self):
        txt=read("scripts/visuals/ring_fade.gd")
        self.assertIn("c.a = 0.45",txt)
        self.assertIn("Reset material alpha so reused pooled rings",txt)
        self.assertIn("func trigger(duration: float)",txt)
    def test_effect_director_pool_caps(self):
        txt=read("scripts/visuals/effect_director.gd")
        self.assertIn("RING_TEXTURE",txt)
        self.assertIn("BURST_TEXTURE",txt)
        # Caps are mobile-safe and bounded — major visuals raised to 10/14 from 6/10.
        self.assertRegex(txt, r"MAX_BURSTS\s*:=\s*(6|10)")
        self.assertRegex(txt, r"MAX_RINGS\s*:=\s*(10|14)")
        # Enforce upper bound: keep memory predictable.
        import re
        m=re.search(r"MAX_BURSTS\s*:=\s*(\d+)",txt)
        self.assertIsNotNone(m)
        self.assertLessEqual(int(m.group(1)), 12)
        m=re.search(r"MAX_RINGS\s*:=\s*(\d+)",txt)
        self.assertIsNotNone(m)
        self.assertLessEqual(int(m.group(1)), 16)
    def test_arena_decorator_uses_local_position(self):
        txt=read("scripts/arena/arena_decorator.gd")
        self.assertIn("(n as Node3D).position",txt)
        self.assertNotIn("(n as Node3D).global_position = center",txt)
    def test_frost_nova_avoids_double_slow(self):
        txt=read("scripts/skills/skill_executor.gd")
        self.assertIn('if &"slow" in cfg.victim_effects:',txt)
        self.assertIn("avoid double-stacking",txt.lower())
    def test_locomotion_clamps_limit_non_negative(self):
        txt=read("scripts/enemies/enemy_locomotion.gd")
        self.assertIn("maxf(_bounds_half - _bounds_margin, 0.0)",txt)
    def test_minimap_radius_clamped(self):
        txt=read("scripts/ui/minimap.gd")
        self.assertIn("maxf(minf",txt)
        self.assertIn("maxf(half, 0.01)",txt)
if __name__=="__main__": unittest.main()
