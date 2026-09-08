"""Regression: stamina exhaust emit, experience reset emit, boss exit disconnect — Batch 11."""
from __future__ import annotations
import pathlib, unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]
def read(rel:str)->str: return (ROOT/rel).read_text(encoding="utf-8",errors="ignore")
class Batch11Tests(unittest.TestCase):
    def test_stamina_exhaust_emits_changed(self):
        txt=read("scripts/player/stamina_component.gd")
        # insufficient branch must emit stamina_changed so HUD updates on exhaustion
        self.assertIn("_exhausted = true\n\t\texhausted.emit()\n\t\tstamina_changed.emit(_current, _max)",txt)
        self.assertIn("EventBus.stamina_changed.emit(_current, _max)",txt)
    def test_experience_reset_emits_xp_changed(self):
        txt=read("scripts/player/experience_component.gd")
        self.assertIn("func reset_for_new_run() -> void:\n\t_xp = 0\n\t_level = 1\n\t_xp_multiplier = 1.0\n\txp_changed.emit(_xp, _level",txt)
    def test_boss_controller_disconnects_on_exit(self):
        txt=read("scripts/enemies/boss_controller.gd")
        self.assertIn("func _exit_tree() -> void:",txt)
        self.assertIn('_health.health_changed.disconnect(_on_health_changed)',txt)
        self.assertIn('_host.died.disconnect(_on_boss_died)',txt)
        self.assertIn("stale boss health_changed/died",txt)
if __name__=="__main__": unittest.main()
