"""Regression: enemies face the player (yaw 180 on +Z-authored models) and arena
decoration keeps clear of the player spawn."""
from __future__ import annotations
import pathlib, unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]
def read(rel:str)->str: return (ROOT/rel).read_text(encoding="utf-8",errors="ignore")
class EnemyFacingTests(unittest.TestCase):
    def test_all_enemy_animators_apply_half_turn(self):
        scenes = sorted((ROOT/"scenes"/"enemies").glob("*.tscn"))
        checked = 0
        for p in scenes:
            txt = p.read_text(encoding="utf-8", errors="ignore")
            if "EnemyAnimator" not in txt:
                continue
            checked += 1
            self.assertIn("yaw_offset_degrees = 180.0", txt,
                msg=f"{p.name}: EnemyAnimator must counter-rotate +Z-authored models onto -Z facing")
        self.assertEqual(checked, 8, msg="expected 8 enemy scenes with EnemyAnimator")
class SpawnClearanceTests(unittest.TestCase):
    def test_decorator_keeps_spawn_clear(self):
        txt = read("scripts/arena/arena_decorator.gd")
        self.assertIn("SPAWN_CLEAR_RADIUS", txt)
        self.assertIn("get_player_start", txt)
        self.assertIn("_player_spawn_local", txt)
    def test_player_start_clears_landmark_and_decor_rings(self):
        import re
        txt = read("scenes/arena/arena.tscn")
        m = re.search(r"\[node name=\"PlayerStart\"[^\]]*\]\ntransform = Transform3D\([0-9., \-]+, ([0-9.\-]+), ([0-9.\-]+), ([0-9.\-]+)\)", txt)
        self.assertIsNotNone(m, msg="PlayerStart must have an explicit spawn transform")
        x, y, z = float(m.group(1)), float(m.group(2)), float(m.group(3))
        self.assertGreater((x*x+z*z) ** 0.5, 3.2, msg="spawn must clear landmark + decor rings")
if __name__ == "__main__":
    unittest.main()
