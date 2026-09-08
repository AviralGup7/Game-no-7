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
        txt=read("scripts/ui/minimap.gd")
        self.assertIn("UPDATE_INTERVAL", txt)
        self.assertIn("15", txt)  # 15 Hz
if __name__=="__main__": unittest.main()
