"""Regression: underdeveloped systems are now wired, not placeholders."""
from __future__ import annotations

import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8", errors="ignore")


class LockOnTests(unittest.TestCase):
    def test_lock_on_is_not_double_toggled(self):
        txt = read("scripts/main/camera_rig.gd")
        self.assertIn("func toggle_lock_on() -> bool:", txt)
        self.assertIn("lock_on_midpoint_factor", txt)
        self.assertIn('_swap_profile(&"combat")', txt)
        self.assertIn('_swap_profile(&"boss")', txt)
        # camera_reset snaps the boom; lock_on is owned by Player.request_lock_on.
        # Sharing one handler double-toggled every press (lock, then unlock).
        self.assertIn('event.is_action_pressed("camera_reset")', txt)
        self.assertNotIn('event.is_action_pressed("lock_on")', txt)
        self.assertNotIn("if not toggle_lock_on():", txt)

    def test_lock_on_input_exists(self):
        txt = read("project.godot")
        self.assertIn("lock_on={", txt)

    def test_player_and_commands_expose_lock(self):
        self.assertIn("func request_lock_on() -> bool:", read("scripts/player/player.gd"))
        self.assertIn('&"request_lock_on"', read("scripts/ui/ui_commands.gd"))


class AimAssistAndGraphicsTests(unittest.TestCase):
    def test_targeting_reads_settings(self):
        txt = read("scripts/player/targeting_component.gd")
        self.assertIn("func apply_settings() -> void:", txt)
        self.assertIn("is_aim_assist_enabled()", txt)
        self.assertIn("sticky_bonus", txt)

    def test_graphics_quality_drives_shadows_and_glow(self):
        txt = read("scripts/utilities/performance_monitor.gd")
        self.assertIn("func _apply_render_tier() -> void:", txt)
        self.assertIn("sun.shadow_enabled = shadow_on", txt)
        self.assertIn("wenv.environment.glow_enabled = glow_on", txt)
        root = read("scripts/ui/ui_root.gd")
        self.assertIn('&"ultra"', root)


class ShakeAndWhiskerTests(unittest.TestCase):
    def test_shake_decay_is_consumed(self):
        txt = read("scripts/main/camera/camera_shake_controller.gd")
        self.assertIn("_profile.shake_decay", txt)

    def test_whiskers_use_pitch(self):
        txt = read("scripts/main/camera/camera_collision_solver.gd")
        self.assertIn("test_pitch", txt)


class AnalyticsNarratorBossTests(unittest.TestCase):
    def test_analytics_tracks_live_kills(self):
        txt = read("scripts/core/run_analytics.gd")
        self.assertIn("func note_lock_on()", txt)
        self.assertIn("func get_live()", txt)
        self.assertIn("EventBus.enemy_spawned.connect", txt)

    def test_narrator_first_of_kind(self):
        txt = read("scripts/meta/narrator.gd")
        self.assertIn("func note_enemy_spawned", txt)
        self.assertIn("func reset_run()", txt)

    def test_boss_shockwave_exists(self):
        txt = read("scripts/enemies/boss_controller.gd")
        self.assertIn("TELEGRAPH_SHOCKWAVE", txt)
        self.assertIn("func _resolve_shockwave()", txt)

    def test_godot_suite_registered(self):
        self.assertIn(
            '"res://tests/unit/test_systems_completion.gd"',
            read("tests/run_tests.gd"),
        )


if __name__ == "__main__":
    unittest.main()
