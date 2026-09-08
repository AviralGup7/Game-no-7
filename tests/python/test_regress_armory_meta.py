"""Regression: Armory vitality & meta progression — guards Batch2 fixes."""
from __future__ import annotations
import pathlib, unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]
def read(rel:str)->str: return (ROOT/rel).read_text(encoding="utf-8",errors="ignore")
class ArmoryMetaTests(unittest.TestCase):
    def test_armory_vitality_key_correct(self):
        txt=read("scripts/meta/meta_progression.gd")
        self.assertIn('&"vitality_tome"',txt)
        self.assertNotIn('&"vitality Tome"',txt.split("# Migrate")[0])
        self.assertIn('&"second_wind": {"name": "Second Wind", "cost": 200, "requires": [&"vitality_tome"]',txt)
    def test_armory_migrates_legacy_key(self):
        txt=read("scripts/meta/meta_progression.gd")
        self.assertIn('StringName("vitality Tome")',txt)
        self.assertIn("Migrate legacy key typo",txt)
        self.assertIn('_ranks.erase(legacy)',txt)
        self.assertIn('maxi(int(_ranks[&"vitality_tome"])',txt)
    def test_apply_all_hoisted_guard(self):
        txt=read("scripts/meta/meta_progression.gd")
        self.assertIn("func apply_all_to_run() -> void:\n\tif GameRoot == null or GameRoot.get_active_player() == null:",txt)
        loop_section=txt.split("func apply_all_to_run")[1].split("func ")[0]
        self.assertIn("for item_id in _ranks:",loop_section)
        self.assertIn('prog.call("add_permanent_bonus"',loop_section)
        self.assertNotIn("if GameRoot == null or GameRoot.get_active_player() == null:\n\t\t\treturn",loop_section)
    def test_achievements_flawless_wiring(self):
        txt=read("scripts/meta/achievements.gd")
        self.assertIn("_player_health",txt)
        self.assertIn("_on_player_damaged",txt)
        self.assertIn("flawless",txt)
    def test_upgrade_service_preserves_active_modifiers(self):
        txt=read("scripts/core/upgrade_service.gd")
        self.assertIn("selected_upgrades",txt)
        self.assertIn("active_modifiers",txt)
        self.assertIn("do not overwrite it",txt.lower())
        self.assertNotIn("get_modifier_snapshot",txt)
    def test_skill_unlock_gate_minus1_blocked(self):
        txt=read("scripts/skills/skill_controller.gd")
        self.assertIn("if level < cfg.unlock_level:",txt)
        self.assertIn("returns -1 when no ExperienceComponent",txt)
        self.assertIn("Treat unknown level as blocked",txt)
if __name__=="__main__": unittest.main()
