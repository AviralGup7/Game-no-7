"""Regression: UI skill_bar, run_summary, joystick, settings — guards Batch6/8/9."""
from __future__ import annotations
import pathlib, re, unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]
def read(rel:str)->str: return (ROOT/rel).read_text(encoding="utf-8",errors="ignore")
class UISkillTests(unittest.TestCase):
    def test_skill_bar_connects_ready_signal(self):
        txt=read("scripts/ui/skill_bar.gd")
        self.assertIn("skill_became_ready",txt)
        self.assertIn("skill_cooldown_started",txt)
    def test_run_summary_rounds_duration(self):
        txt=read("scripts/ui/run_summary_panel.gd")
        self.assertIn("int(round(maxf(seconds,",txt)
        self.assertRegex(txt,r"maxi\(int\(round\(maxf\(seconds,\s*0\.0\)\)\)")
    def test_virtual_joystick_deadzone_range(self):
        txt=read("scripts/ui/virtual_joystick.gd")
        self.assertRegex(txt,r"@export_range\(0\.0,\s*0\.5,\s*0\.01\)")
        self.assertIn("dead_zone",txt)
        self.assertNotIn("@export var dead_zone",txt)
    def test_settings_panel_defaults_to_high(self):
        txt=read("scripts/ui/settings_panel.gd")
        self.assertIn("high",txt.lower())
    def test_ui_tier_fallback_to_high(self):
        txt=read("scripts/ui/ui_root.gd")
        self.assertIn('if tier_idx < 0:',txt)
        self.assertIn("tier_idx = 2",txt)
        self.assertIn("high is the default when save carries an unknown",txt)
    def test_weapon_combo_chains_only_inside_window(self):
        # Combo chaining is canonical in WeaponInstance: a press only chains while
        # the previous swing's window is still open and below the max step
        # (the legacy AttackController/ComboChain window logic was removed).
        txt=read("scripts/weapons/weapon_instance.gd")
        self.assertIn("_chain_left <= 0.0",txt)
        self.assertIn("combo_step += 1",txt)
    def test_arena_resolve_handles_dict_and_object(self):
        txt=read("scripts/arena/arena.gd")
        block = txt[txt.find("func _resolve_arena_id"):txt.find("func _resolve_arena_id") + 500]
        self.assertIn("GameRoot.get_run()", block)
        self.assertIn("run.arena_id", block)
if __name__=="__main__": unittest.main()
