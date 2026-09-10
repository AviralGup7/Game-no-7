"""Regression: arena and lifecycle guards."""
import pathlib, unittest
ROOT=pathlib.Path(__file__).resolve().parents[2]
def read(p): return (ROOT/p).read_text()
class ArenaGuards(unittest.TestCase):
    def test_arena_spawn_guarded(self):
        txt=read("scripts/arena/arena.gd")
        self.assertIn("is_inside_tree()", txt)
        self.assertIn("get_nodes_in_group", txt)
    def test_player_aim_guarded(self):
        txt=read("scripts/player/player.gd")
        self.assertIn("is_inside_tree()", txt)
        self.assertIn("_aim_attack", txt)
    def test_camera_reduced_motion(self):
        txt=read("scripts/main/camera_rig.gd")
        self.assertIn("_reduced_motion", txt)
        self.assertIn("SaveManager.get_settings().reduced_motion", txt)
    def test_minimap_throttled(self):
        # v2: group re-queries are throttled to 15 Hz; per-frame work is the
        # cheap track easing + gated redraw (see test_regress_minimap_radar).
        txt=read("scripts/ui/minimap.gd")
        self.assertIn("DISCOVERY_INTERVAL := 1.0 / 15.0", txt)
        self.assertIn("_discovery_acc", txt)
if __name__=="__main__": unittest.main()
