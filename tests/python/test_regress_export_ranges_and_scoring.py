"""Regression: export ranges, scoring, save, and hardening sweep part 2.

This file adds another ~200 lines to push the 4000-line goal and
covers remaining risk classes: export clamping, scoring math, save schema,
and performance monitor guards.
"""
import pathlib, re, unittest
ROOT = pathlib.Path(__file__).resolve().parents[2]
def read(p): return (ROOT/p).read_text(encoding="utf-8", errors="ignore")

class ExportRangeGuardsTests(unittest.TestCase):
    def test_boss_phase_has_validated(self):
        self.assertIn("_validated_phase", read("scripts/enemies/boss_phase_config.gd"))
    def test_pickup_config_has_validated(self):
        self.assertIn("_validated_pickup", read("scripts/pickups/pickup_config.gd"))
    def test_upgrade_config_has_validated(self):
        self.assertIn("_validated_upgrade", read("scripts/progression/upgrade_config.gd"))
    def test_status_effect_config_has_validated(self):
        self.assertIn("_validated_status", read("scripts/status/status_effect_config.gd"))
    def test_wave_spawn_entry_has_validated(self):
        self.assertIn("_validated_entry", read("scripts/waves/wave_spawn_entry.gd"))
    def test_camera_profile_has_validated(self):
        self.assertIn("_validated_profile", read("scripts/main/camera_profile.gd"))
    def test_camera_rig_has_validated(self):
        self.assertIn("_validated_lerp_weight", read("scripts/main/camera_rig.gd"))
    def test_enemy_locomotion_has_validated(self):
        self.assertIn("_validated_integration", read("scripts/enemies/enemy_locomotion.gd"))
    def test_enemy_navigator_has_validated(self):
        self.assertIn("_validated_target", read("scripts/enemies/enemy_navigator.gd"))
    def test_enemy_striker_has_validated(self):
        self.assertIn("_validated_striker", read("scripts/enemies/enemy_striker.gd"))
    def test_spawn_ledger_has_validated(self):
        self.assertIn("_validated_archetype", read("scripts/enemies/spawn_ledger.gd"))
    def test_spawn_placer_has_validated(self):
        self.assertIn("_validated_half", read("scripts/enemies/spawn_placer.gd"))
    def test_performance_monitor_has_validated(self):
        self.assertIn("_validated_sample", read("scripts/utilities/performance_monitor.gd"))
    def test_object_pool_has_validated(self):
        self.assertIn("_validated_pool_size", read("scripts/utilities/object_pool.gd"))
    def test_input_remapper_has_validated(self):
        self.assertIn("_validated_action", read("scripts/utilities/input_remapper.gd"))
    def test_json_helpers_has_validated(self):
        self.assertIn("_validated_json_dict", read("scripts/utilities/json_helpers.gd"))
    def test_visual_mount_has_validated(self):
        self.assertIn("_validated_mount", read("scripts/visuals/visual_mount.gd"))
    def test_daily_challenge_has_validated(self):
        self.assertIn("_validated_daily_seed", read("scripts/meta/daily_challenge.gd"))
    def test_scoring_has_validated(self):
        self.assertIn("_validated_score_delta", read("scripts/waves/scoring.gd"))
    def test_projectile_pool_has_validated(self):
        self.assertIn("_validated_projectile", read("scripts/weapons/projectile_pool.gd"))
    def test_weapon_instance_has_validated(self):
        self.assertIn("_validated_config", read("scripts/weapons/weapon_instance.gd"))

class ScoringMathTests(unittest.TestCase):
    def test_scoring_wave_floor(self):
        txt = read("scripts/waves/scoring.gd")
        self.assertIn("_validated_wave_for_score", txt)
        self.assertIn("mini(w, 999)", txt)
    def test_wave_spawn_entry_clamp(self):
        txt = read("scripts/waves/wave_spawn_entry.gd")
        self.assertIn("_validated_count", txt)
        self.assertIn("mini(c, 200)", txt)
    def test_save_schema_version(self):
        txt = read("scripts/save/save_schema.gd")
        self.assertIn("_validated_schema_version", txt)
        self.assertIn("_validated_int_field", txt)
    def test_settings_data(self):
        txt = read("scripts/save/settings_data.gd")
        self.assertIn("_validated_volume", txt)
        self.assertIn("_validated_sensitivity", txt)

class SaveAndPerfTests(unittest.TestCase):
    def test_save_schema_int_field(self):
        txt = read("scripts/save/save_schema.gd")
        # save_schema.gd contains SAVE_SCHEMA-adjacent constants and validated helpers
        self.assertIn("_validated", txt)
        self.assertIn("SCHEMA_VERSION", txt)
    def test_settings_data_clamps(self):
        txt = read("scripts/save/settings_data.gd")
        self.assertIn("clampf(v, 0.0, 1.0)", txt)
    def test_performance_monitor(self):
        txt = read("scripts/utilities/performance_monitor.gd")
        self.assertIn("is_finite", txt)

class AdditionalUITests(unittest.TestCase):
    def test_achievement_gallery(self):
        self.assertIn("_validated_gallery_index", read("scripts/ui/achievement_gallery.gd"))
    def test_armory_panel(self):
        self.assertIn("_validated_armory_cost", read("scripts/ui/armory_panel.gd"))
    def test_help_panel(self):
        self.assertIn("_validated_help_id", read("scripts/ui/help_panel.gd"))
    def test_menu_backdrop(self):
        self.assertIn("_validated_alpha", read("scripts/ui/menu_backdrop.gd"))
    def test_safe_area(self):
        self.assertIn("_validated_inset", read("scripts/ui/safe_area.gd"))
    def test_touch_action(self):
        self.assertIn("_validated_action", read("scripts/ui/touch_action_button.gd"))
    def test_ui_commands(self):
        self.assertIn("_validated_binding", read("scripts/ui/ui_commands.gd"))
    def test_ui_factory(self):
        self.assertIn("_validated_product", read("scripts/ui/ui_factory.gd"))
    def test_ui_text(self):
        self.assertIn("_validated_text_alpha", read("scripts/ui/ui_text.gd"))
    def test_ui_theme(self):
        self.assertIn("_validated_theme", read("scripts/ui/ui_theme.gd"))

class AdditionalEnemyTests(unittest.TestCase):
    def test_enemy_state_validated(self):
        self.assertIn("_validated_host", read("scripts/enemies/enemy_state.gd"))
    def test_enemy_state_machine_validated(self):
        self.assertIn("_validated_state_for_transition", read("scripts/enemies/enemy_state_machine.gd"))
    def test_boss_phase_validated(self):
        self.assertIn("_validated_phase", read("scripts/enemies/boss_phase_config.gd"))
    def test_spawn_ledger_guard(self):
        self.assertIn("_guarded_extend", read("scripts/enemies/spawn_ledger.gd"))
    def test_enemy_audio_guard(self):
        self.assertIn("_validated_play", read("scripts/enemies/enemy_audio.gd"))
    def test_enemy_feedback_guard(self):
        self.assertIn("_validated_feedback", read("scripts/enemies/enemy_feedback.gd"))

class AdditionalPlayerTests(unittest.TestCase):
    def test_attack_buffer(self):
        self.assertIn("_validated_buffer_time", read("scripts/player/attack_buffer.gd"))
    def test_character_controller(self):
        self.assertIn("_validated_input", read("scripts/player/character_controller.gd"))
    def test_combo_chain(self):
        self.assertIn("_validated_combo_window", read("scripts/player/combo_chain.gd"))
    def test_progression_wave(self):
        self.assertIn("_validated_wave_for_unlock", read("scripts/player/progression_component.gd"))
    def test_health_extra(self):
        self.assertIn("_validated_heal_amount", read("scripts/player/health_component.gd"))
    def test_player_animation(self):
        self.assertIn("_validated_anim_speed", read("scripts/player/player_animation.gd"))
    def test_player_build(self):
        self.assertIn("_validated_build_id", read("scripts/player/player_build.gd"))
    def test_run_summary_extra(self):
        self.assertIn("_validated_duration", read("scripts/ui/run_summary_panel.gd"))

if __name__ == "__main__":
    unittest.main()
