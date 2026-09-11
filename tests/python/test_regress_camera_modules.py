"""Regression: camera modules keep the defects that made the rig fight the player closed.

Godot suite `tests/unit/test_camera_modules.gd` drives the math; this file pins
that the wiring stays in the coordinator and that we do not resurrect the
double-lock, dead-touch, double-stick, or stacked-boom paths.
"""
from __future__ import annotations

import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8", errors="ignore")


class LockOnOwnershipTests(unittest.TestCase):
    def test_player_owns_lock_on_input(self):
        player = read("scripts/player/player.gd")
        self.assertIn("func request_lock_on() -> bool:", player)
        self.assertIn('Input.is_action_just_pressed("lock_on")', player)
        self.assertIn("rig.toggle_lock_on()", player)

    def test_rig_unhandled_input_does_not_also_toggle_lock(self):
        rig = read("scripts/main/camera_rig.gd")
        body_start = rig.index("func _unhandled_input(")
        body_end = rig.index("func _process(", body_start)
        body = rig[body_start:body_end]
        self.assertIn('event.is_action_pressed("camera_reset")', body)
        self.assertIn("reset_orbit()", body)
        self.assertNotIn('event.is_action_pressed("lock_on")', body)
        self.assertNotIn("toggle_lock_on()", body)


class TouchAndStickTests(unittest.TestCase):
    def test_touch_drag_uses_look_delta_not_fake_mouse(self):
        rig = read("scripts/main/camera_rig.gd")
        self.assertIn("_input_handler.handle_touch_look(", rig)
        self.assertIn("LOOK_ZONE_X", rig)
        self.assertIn("_look_touch_index", rig)
        self.assertNotIn("drag.relative * 0.8", rig)
        handler = read("scripts/main/camera/camera_input_handler.gd")
        self.assertIn("func handle_look_delta(relative: Vector2) -> void:", handler)
        self.assertIn("func handle_touch_look(relative: Vector2, viewport_size: Vector2) -> void:", handler)
        self.assertIn("touch_orbit_yaw_per_screen", handler)
        orbit = read("scripts/main/camera/camera_orbit_controller.gd")
        self.assertIn("orbit.current_yaw -= yaw_delta", orbit)
        self.assertIn("orbit.current_pitch += pitch_delta", orbit)
        profile = read("scripts/main/camera_profile.gd")
        self.assertIn("touch_orbit_yaw_per_screen: float = 540.0", profile)

    def test_gamepad_stick_is_not_read_twice(self):
        handler = read("scripts/main/camera/camera_input_handler.gd")
        self.assertNotIn("Input.get_joy_axis", handler)
        self.assertIn('Input.get_axis("camera_look_left", "camera_look_right")', handler)


class AutoFollowAndFramingTests(unittest.TestCase):
    def test_shooter_profiles_disable_souls_auto_follow(self):
        for rel in (
            "data/cameras/default.tres",
            "data/cameras/combat.tres",
            "data/cameras/boss.tres",
        ):
            txt = read(rel)
            self.assertIn("auto_follow_enabled = false", txt, msg=rel)
            self.assertIn("auto_follow_toward_camera_threshold = 0.", txt, msg=rel)
            self.assertIn("aim_distance = ", txt, msg=rel)
        profile = read("scripts/main/camera_profile.gd")
        self.assertIn("auto_follow_enabled: bool = false", profile)
        self.assertIn("aim_distance: float = 22.0", profile)
        self.assertIn("min_pitch_deg: float = -55.0", profile)
        framing = read("scripts/main/camera/camera_framing_controller.gd")
        self.assertIn("aim_dir", framing)
        self.assertIn("_profile.aim_distance", framing)
        handler = read("scripts/main/camera/camera_input_handler.gd")
        self.assertIn("yaw_deg += _touch_accum.x", handler)
        loco = read("scripts/player/character_controller.gd")
        self.assertIn("func _face_look_yaw(", loco)
        self.assertIn("_face_look_yaw(dir, delta)", loco)

    def test_toward_camera_threshold_is_consumed(self):
        auto = read("scripts/main/camera/camera_auto_follow_controller.gd")
        self.assertIn("auto_follow_toward_camera_threshold", auto)
        self.assertNotIn("if dot > 0.25:", auto)

    def test_authored_thresholds_are_positive_dots(self):
        for rel in (
            "data/cameras/default.tres",
            "data/cameras/combat.tres",
            "data/cameras/boss.tres",
        ):
            txt = read(rel)
            self.assertIn("auto_follow_toward_camera_threshold = 0.", txt, msg=rel)
            self.assertNotIn("auto_follow_toward_camera_threshold = -", txt, msg=rel)

    def test_combat_boom_is_applied_once(self):
        framing = read("scripts/main/camera/camera_framing_controller.gd")
        desired = framing[framing.index("func calculate_desired_position("):]
        desired = desired[: desired.index("func calculate_look_target(")]
        self.assertNotIn("_combat_distance_boost", desired)
        self.assertIn("var dist := orbit.current_distance", desired)
        orbit = read("scripts/main/camera/camera_orbit_controller.gd")
        self.assertIn("combat_boost = framing.get_combat_distance_boost()", orbit)

    def test_combat_framing_lerps_every_frame(self):
        framing = read("scripts/main/camera/camera_framing_controller.gd")
        tick = framing[framing.index("func tick_combat_framing("):]
        # The lerp must sit outside the interval early-return.
        self.assertIn("lerpf(_combat_distance_boost, target_dist_boost, weight)", tick)
        self.assertNotIn("if _last_enemy_check < interval:\n\t\treturn", tick)


class ModeAndCollisionTests(unittest.TestCase):
    def test_unlock_restores_mode_before_lock(self):
        mode = read("scripts/main/camera/camera_mode_controller.gd")
        self.assertIn("var _mode_before_lock", mode)
        self.assertIn("set_mode(_mode_before_lock", mode)

    def test_clear_collision_keeps_shoulder_offset(self):
        solver = read("scripts/main/camera/camera_collision_solver.gd")
        solve = solver[solver.index("func solve("): solver.index("func _needs_fresh_pass(")]
        self.assertIn("result = to", solve)
        self.assertNotIn("result = from + final_dir * orbit.current_distance", solve)


class HarnessRegistrationTests(unittest.TestCase):
    def test_godot_module_suite_is_registered(self):
        txt = read("tests/run_tests.gd")
        self.assertIn('"res://tests/unit/test_camera_modules.gd"', txt)


if __name__ == "__main__":
    unittest.main()
