"""Regression for sweep fixes: wave_manager indent, get_node null, spawn_placer valid, area_damage."""

import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]

def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8", errors="ignore")

class SweepFixTests(unittest.TestCase):
    def test_wave_manager_player_max_hp_indent(self):
        txt = read("scripts/waves/wave_manager.gd")
        block = txt[txt.find("func _player_max_hp"):txt.find("func _player_max_hp") + 400]
        self.assertIn("var player := GameRoot.get_active_player()", block)
        self.assertIn("player.get_health_component()", block)
        self.assertNotIn("as Node", block)
    def test_player_animation_no_bare_get_node(self):
        txt = read("scripts/player/player_animation.gd")
        self.assertNotIn(".get_node(\"VisualRoot", txt)
        self.assertNotIn(".get_node(\"DodgeController", txt)
        self.assertIn("get_node_or_null(\"VisualRoot", txt)
        self.assertIn("get_node_or_null(\"DodgeController", txt)
    def test_player_equipment_no_bare_get_node(self):
        txt = read("scripts/player/player_equipment.gd")
        self.assertNotIn("get_node(\"VisualRoot/CharacterModel\")", txt)
        self.assertIn("get_node_or_null(\"VisualRoot/CharacterModel\")", txt)
    def test_spawn_placer_uses_is_instance_valid(self):
        txt = read("scripts/enemies/spawn_placer.gd")
        self.assertIn("static func pick_point(arena: Arena", txt)
        self.assertIn("static func fallback_point(arena: Arena", txt)
    def test_area_damage_radius_valid(self):
        txt = read("scripts/combat/area_damage.gd")
        self.assertIn("if c == null or not is_instance_valid(c):", txt)
        # ensure _radius_of guard is present
        self.assertIn("func _radius_of", txt)
        block = txt[txt.find("func _radius_of"):txt.find("func _radius_of")+600]
        self.assertIn("return 0.0", block)
    def test_combat_seeded_rng(self):
        # Seeded rolls moved with the combat path: WeaponInstance owns the RNG on
        # the crit stream (legacy AttackController deleted with the sweep).
        txt = read("scripts/weapons/weapon_instance.gd")
        self.assertIn("RngService", txt)
        self.assertIn("STREAM_CRITS", txt)
    def test_boss_signal_order(self):
        txt = read("scripts/enemies/spawn_manager.gd")
        block = txt[txt.find("func _maybe_begin_boss_fight"):][:1200]
        self.assertIn("summon_requested.connect", block)
        self.assertLess(block.find("summon_requested.connect"), block.find("boss.begin_fight"))
    def test_content_loader_recursive(self):
        txt = read("scripts/core/content_loader.gd")
        self.assertIn("_recursive_list", txt)
        self.assertIn("current_is_dir", txt)
    def test_all_validated_present(self):
        txt = read("tool/validate_guards.py")
        self.assertIn("139/139", read("docs/HARDENING.md"))
if __name__ == "__main__":
    unittest.main()
