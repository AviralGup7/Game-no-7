"""Regression: authority isolation — movement/damage/spawn/game state have exactly one owner."""
import pathlib, unittest
ROOT=pathlib.Path(__file__).resolve().parents[2]
def read(p): return (ROOT/p).read_text()
class AuthorityTests(unittest.TestCase):
    def test_movement_single_authority(self):
        txt=read("scripts/player/character_controller.gd")
        # must not consult legacy AttackController for windup lock
        self.assertNotIn("_legacy", txt, "CharacterController still references legacy AttackController")
        self.assertIn("WeaponInstance.PHASE_WINDUP", txt)
    def test_animation_single_authority(self):
        txt=read("scripts/player/player_animation.gd")
        self.assertNotIn("_legacy", txt, "PlayerAnimation still references legacy")
        self.assertIn("WeaponManager", txt)
    def test_player_aim_guarded(self):
        txt=read("scripts/player/player.gd")
        self.assertIn("is_inside_tree()", txt)
        self.assertIn("get_nodes_in_group", txt)
    def test_spawn_single_authority(self):
        txt=read("scripts/enemies/boss_controller.gd")
        self.assertIn("summon_requested", txt)
        sm=read("scripts/enemies/spawn_manager.gd")
        self.assertIn("_on_boss_summon_requested", sm)
    def test_damage_authority(self):
        txt=read("scripts/player/player.gd")
        self.assertIn("DamagePayload", txt)
        self.assertIn("WeaponManager", txt)
if __name__=="__main__": unittest.main()
