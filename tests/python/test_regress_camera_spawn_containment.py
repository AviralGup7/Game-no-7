"""Regression: spawn + camera must stay inside the arena.

Pins the session fix for "hero looks outside the mountain but the body is inside"
and the turn-around / wall-clash crash. Godot suites
`test_camera_arena_containment.gd` and `test_safe_player_spawn.gd` drive the
math; this file pins that the guards stay wired at every hand-off.
"""
from __future__ import annotations

import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8", errors="ignore")


class PlayerStartFacingTests(unittest.TestCase):
    def test_player_start_faces_into_the_yard(self):
        # basis.z = (0,0,-1) so character forward (-Z) is world +Z: camera sits
        # north of the marker, not through the south wall into the HDRI sky.
        txt = read("scenes/arena/arena.tscn")
        self.assertIn(
            "transform = Transform3D(-1, 0, 0, 0, 1, 0, 0, 0, -1, 0, 0.2, 4.5)",
            txt,
        )
        self.assertNotIn(
            "transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 4.5)",
            txt,
        )


class SafeSpawnTests(unittest.TestCase):
    def test_arena_exposes_unstuck_and_safe_spawn(self):
        txt = read("scripts/arena/arena.gd")
        self.assertIn("func get_safe_player_spawn() -> Transform3D:", txt)
        self.assertIn("func unstuck_origin(p: Vector3) -> Vector3:", txt)
        self.assertIn("xf.origin = _find_clear_player_origin(unstuck_origin(xf.origin))", txt)
        self.assertIn("p.y = maxf(p.y, 0.15)", txt)

    def test_main_spawns_through_the_safe_pose(self):
        txt = read("scripts/main/main.gd")
        self.assertIn("arena.get_safe_player_spawn()", txt)
        self.assertNotIn('arena.get_node_or_null("PlayerStart") as Marker3D', txt)

    def test_locomotion_lifts_a_buried_body(self):
        txt = read("scripts/player/player_locomotion.gd")
        fn = txt[txt.index("func clamp_to_bounds()"):]
        self.assertIn("if y < 0.12:", fn)
        self.assertIn("y = 0.12", fn)


class CameraBoomTests(unittest.TestCase):
    def test_shorten_arm_helper_exists(self):
        txt = read("scripts/main/camera/camera_math.gd")
        self.assertIn("static func shorten_arm_to_box(", txt)
        self.assertIn("if not is_finite(yaw) or not is_finite(pitch) or not is_finite(distance):", txt)
        self.assertIn("return Vector3.ZERO", txt)

    def test_rig_writes_position_through_boom_fit(self):
        txt = read("scripts/main/camera_rig.gd")
        self.assertIn("func _keep_camera_inside_arena(pos: Vector3) -> Vector3:", txt)
        self.assertIn("CameraMath.shorten_arm_to_box(focus, pos, half)", txt)
        self.assertIn("next = _keep_camera_inside_arena(next)", txt)
        self.assertNotIn("func _clamp_inside_arena(", txt)

    def test_orbit_distance_is_profile_capped_not_hard_10_5(self):
        # A 10.5 m ceiling fought boss/combat profiles (12.5 m authored) and was
        # redundant with CameraRig._keep_camera_inside_arena / shorten_arm_to_box.
        txt = read("scripts/main/camera/camera_orbit_controller.gd")
        self.assertNotIn("ceiling = minf(ceiling, 10.5)", txt)
        self.assertIn(
            "orbit.current_distance = clampf(orbit.current_distance, _profile.min_distance, _profile.max_distance)",
            txt,
        )
        rig = read("scripts/main/camera_rig.gd")
        self.assertIn("CameraMath.shorten_arm_to_box(focus, pos, half)", rig)

    def test_collision_solver_recovers_from_inside_a_wall(self):
        txt = read("scripts/main/camera/camera_collision_solver.gd")
        self.assertIn("if safe < 0.04:", txt)
        self.assertIn("func _pull_out_of_overlap(", txt)
        self.assertIn("result = _pull_out_of_overlap(result, from, target, world)", txt)
        self.assertIn("space.intersect_shape(query, 1)", txt)


class WallClashTests(unittest.TestCase):
    def test_move_and_slide_jump_is_rolled_back(self):
        txt = read("scripts/player/character_controller.gd")
        self.assertIn("before.distance_squared_to(after_pos) > 36.0", txt)
        self.assertIn('_report_non_finite("move_and_slide jump")', txt)
        self.assertEqual(txt.count("_owner_body.move_and_slide()"), 1)


class HarnessRegistrationTests(unittest.TestCase):
    def test_godot_suites_are_registered(self):
        txt = read("tests/run_tests.gd")
        self.assertIn('"res://tests/unit/test_camera_arena_containment.gd"', txt)
        self.assertIn('"res://tests/unit/test_camera_modules.gd"', txt)
        self.assertIn('"res://tests/unit/test_safe_player_spawn.gd"', txt)

    def test_locomotion_nan_suite_still_covers_boom_fit(self):
        txt = read("tests/unit/test_locomotion_nan.gd")
        self.assertIn("CameraMath.shorten_arm_to_box", txt)
        self.assertIn("boom shortens instead of leaving the arena", txt)


if __name__ == "__main__":
    unittest.main()
