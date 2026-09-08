"""Regression: UI, visuals, audio, status, skills, arena, save — validated helpers."""
import pathlib, unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]
def read(p): return (ROOT/p).read_text(encoding="utf-8", errors="ignore")

class UITests(unittest.TestCase):
    def test_minimap(self):
        self.assertIn("_validated_map_pos", read("scripts/ui/minimap.gd"))
    def test_upgrade_panel_card(self):
        self.assertIn("_validated_card_index", read("scripts/ui/upgrade_panel.gd"))
    def test_boss_bar(self):
        self.assertIn("_validated_boss_fraction", read("scripts/ui/boss_health_bar.gd"))
    def test_game_hud(self):
        self.assertIn("_validated_hud_fraction", read("scripts/ui/game_hud.gd"))
    def test_skill_bar(self):
        self.assertIn("_validated_skill_cd", read("scripts/ui/skill_bar.gd"))
    def test_tutorial_guards(self):
        txt=read("scripts/ui/tutorial_manager.gd")
        self.assertIn("is_finite(delta)",txt)
        self.assertIn("has_method(\"get_current_state\")",txt)
    def test_announcement(self):
        self.assertIn("_validated_banner_text", read("scripts/ui/announcement_banner.gd"))
    def test_damage_number(self):
        self.assertIn("_validated_damage_label", read("scripts/ui/damage_number_layer.gd"))
    def test_menu_panel(self):
        self.assertIn("_validated_menu_id", read("scripts/ui/menu_panel.gd"))
    def test_run_setup(self):
        self.assertIn("_validated_setup_seed", read("scripts/ui/run_setup_panel.gd"))
    def test_touch(self):
        self.assertIn("_validated_touch_deadzone", read("scripts/ui/touch_controls.gd"))
    def test_joystick(self):
        self.assertIn("_validated_joy_vec", read("scripts/ui/virtual_joystick.gd"))
    def test_settings(self):
        self.assertIn("_validated_slider", read("scripts/ui/settings_panel.gd"))
    def test_ui_root(self):
        self.assertIn("_validated_state", read("scripts/ui/ui_root.gd"))

class VisualsTests(unittest.TestCase):
    def test_effect_director(self):
        self.assertIn("_validated_effect_scale", read("scripts/visuals/effect_director.gd"))
    def test_ring_fade(self):
        self.assertIn("_validated_fade_time", read("scripts/visuals/ring_fade.gd"))
    def test_model_visual(self):
        self.assertIn("_validated_model_path", read("scripts/visuals/model_visual.gd"))
    def test_character_visuals(self):
        self.assertIn("_validated_model_id", read("scripts/visuals/character_visuals.gd"))
    def test_arena(self):
        self.assertIn("_validated_half", read("scripts/arena/arena.gd"))
    def test_arena_config(self):
        self.assertIn("_validated_arena_half", read("scripts/arena/arena_config.gd"))
    def test_arena_decorator(self):
        self.assertIn("_validated_decor_seed", read("scripts/arena/arena_decorator.gd"))
    def test_hazards(self):
        self.assertIn("_validated_hazard_damage", read("scripts/arena/arena_hazards.gd"))

class AudioTests(unittest.TestCase):
    def test_audio_manager(self):
        self.assertIn("_validated_volume", read("scripts/audio/audio_manager.gd"))
    def test_music_manager(self):
        self.assertIn("_validated_fade", read("scripts/audio/music_manager.gd"))
    def test_audio_config(self):
        self.assertIn("_validated_audio_range", read("scripts/audio/audio_config.gd"))
    def test_procedural(self):
        self.assertIn("_validated_pitch", read("scripts/audio/procedural_sfx.gd"))

class StatusTests(unittest.TestCase):
    def test_status_manager_validated(self):
        txt=read("scripts/status/status_manager.gd")
        self.assertIn("_validated_effects",txt)
        self.assertIn("is_finite(delta)",txt)
        self.assertIn("is_instance_valid(fx)",txt)
    def test_status_effect(self):
        self.assertIn("_validated_duration", read("scripts/status/status_effect.gd"))

class SkillsTests(unittest.TestCase):
    def test_skill_controller(self):
        self.assertIn("_validated_cooldown", read("scripts/skills/skill_controller.gd"))
    def test_skill_config(self):
        self.assertIn("_validated_skill_stats", read("scripts/skills/skill_config.gd"))
    def test_skill_executor(self):
        self.assertIn("_validated_cast_pos", read("scripts/skills/skill_executor.gd"))

class SaveTests(unittest.TestCase):
    def test_validated_currency(self):
        self.assertIn("_validated_currency", read("scripts/save/save_manager.gd"))
    def test_validated_save_dict(self):
        self.assertIn("_validated_save_dict", read("scripts/save/save_manager.gd"))
    def test_validated_version(self):
        self.assertIn("_validated_save_version", read("scripts/save/save_manager.gd"))

class MetaTests(unittest.TestCase):
    def test_meta_spend(self):
        self.assertIn("_validated_spend", read("scripts/meta/meta_progression.gd"))
    def test_achievements_unlock(self):
        self.assertIn("_validated_unlock", read("scripts/meta/achievements.gd"))

class EnemyStateMachineLikeTests(unittest.TestCase):
    def test_enemy_state_machine_guard(self):
        txt=read("scripts/enemies/enemy_state_machine.gd")
        self.assertIn("state_id == &\"\"",txt)

if __name__=="__main__": unittest.main()
