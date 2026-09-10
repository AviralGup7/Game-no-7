"""Regression: the joystick -> locomotion -> physics/camera pipeline must be
non-finite-proof. A single NaN/inf sample is self-perpetuating (it is integrated into a
CharacterBody3D and lerped into the camera rig, so it never decays), which is why the
device died "a few steps after" moving the stick rather than on the bad frame itself.

Guards, not guesses: `tests/unit/test_locomotion_nan.gd` drives the same boundaries in
Godot; this file pins that the guards are still wired at the hand-off points, because
they are the difference between a dropped frame and an aborted run.
"""
from __future__ import annotations
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8", errors="ignore")


class VirtualJoystickTests(unittest.TestCase):
    def test_radius_cannot_divide_by_zero(self):
        txt = read("scripts/ui/virtual_joystick.gd")
        self.assertIn("func _safe_radius() -> float:", txt)
        self.assertIn("return radius if is_finite(radius) and radius >= 8.0 else 8.0", txt)
        # The division that produced inf/NaN goes through the safe radius, and both
        # the drag clamp and the draw path use it.
        self.assertIn("var r := _safe_radius()", txt)
        self.assertIn("var normalized := delta / r", txt)
        self.assertNotIn("var normalized := delta / radius", txt)
        self.assertNotIn("if length > radius:", txt)

    def test_pointer_positions_are_validated(self):
        txt = read("scripts/ui/virtual_joystick.gd")
        self.assertIn("func _is_finite_v2(v: Vector2) -> bool:", txt)
        self.assertIn("if not _is_finite_v2(pointer_position):\n\t\treturn", txt)

    def test_value_only_exists_while_captured(self):
        # A drag that arrives after release must not publish phantom movement.
        txt = read("scripts/ui/virtual_joystick.gd")
        fn = txt[txt.index("func _update(pointer_position: Vector2)"):]
        self.assertIn("if not _active:\n\t\treturn", fn[:400])

    def test_value_accessor_never_hands_out_garbage(self):
        txt = read("scripts/ui/virtual_joystick.gd")
        self.assertIn("return _value if _is_finite_v2(_value) else Vector2.ZERO", txt)

    def test_mouse_drag_is_accepted_for_desktop_repro(self):
        txt = read("scripts/ui/virtual_joystick.gd")
        self.assertIn("const _MOUSE_INDEX := -2", txt)
        self.assertIn("elif event is InputEventMouseButton:", txt)
        self.assertIn("elif event is InputEventMouseMotion and _active and _touch_index == _MOUSE_INDEX:", txt)


class TouchControlsTests(unittest.TestCase):
    def test_ui_never_forwards_a_poisoned_sample(self):
        txt = read("scripts/ui/touch_controls.gd")
        block = txt[txt.index("func _process("):]
        self.assertIn("if not is_finite(value.x) or not is_finite(value.y):", block)
        # Refusing the value must also release the latched one, not freeze it.
        self.assertIn("UiCommands.move(Vector2.ZERO)", block)


class LocomotionTests(unittest.TestCase):
    def test_move_input_boundary_is_finite(self):
        txt = read("scripts/player/player_locomotion.gd")
        fn = txt[txt.index("func set_move_input("):txt.index("func current_input()")]
        self.assertIn("if not is_finite(input_vector.x) or not is_finite(input_vector.y):", fn)
        self.assertIn("_move_input = Vector2.ZERO", fn)

    def test_gathered_axis_input_is_finite(self):
        txt = read("scripts/player/player_locomotion.gd")
        fn = txt[txt.index("func gather()"):txt.index("func track(")]
        self.assertIn("if not is_finite(v.x) or not is_finite(v.y):", fn)

    def test_bounds_clamp_repairs_a_poisoned_transform(self):
        txt = read("scripts/player/player_locomotion.gd")
        fn = txt[txt.index("func clamp_to_bounds()"):]
        self.assertIn("_body.velocity = Vector3.ZERO", fn)
        self.assertIn("if not (is_finite(p.x) and is_finite(p.y) and is_finite(p.z)):", fn)


class CharacterControllerTests(unittest.TestCase):
    def test_single_velocity_choke_point(self):
        txt = read("scripts/player/character_controller.gd")
        self.assertIn("func _apply_velocity(vel: Vector3) -> void:", txt)
        # Nobody writes velocity + move_and_slide outside the choke point.
        self.assertEqual(txt.count("_owner_body.move_and_slide()"), 1)
        self.assertEqual(txt.count("_owner_body.velocity = "), 4)  # entry, slide-jump rollback, repair, stop()
        self.assertIn("_apply_velocity(vel)", txt)
        self.assertIn("_apply_velocity(_clean_velocity(_owner_body.velocity))", txt)

    def test_delta_and_inputs_are_validated(self):
        txt = read("scripts/player/character_controller.gd")
        self.assertIn("if not is_finite(delta) or delta <= 0.0:", txt)
        self.assertIn("if not _is_finite_v3(direction) or not is_finite(speed) or not is_finite(delta):", txt)
        self.assertIn("var vel := _clean_velocity(_owner_body.velocity)", txt)

    def test_camera_relative_basis_cannot_inject_nan(self):
        txt = read("scripts/player/character_controller.gd")
        self.assertIn("return yaw if is_finite(yaw) else 0.0", txt)
        self.assertIn("if not _is_finite_v3(dir3):", txt)

    def test_rotation_is_assigned_whole_and_checked(self):
        txt = read("scripts/player/character_controller.gd")
        # Component-assignment on a transform-backed property is how a partial/garbage
        # write sneaks in; the hero's yaw goes through a validated vector instead.
        self.assertNotIn("_owner_body.global_rotation.y =", txt)
        self.assertIn("if _is_finite_v3(rot):", txt)

    def test_move_speed_setter_is_bounded(self):
        txt = read("scripts/player/character_controller.gd")
        self.assertIn(
            "move_speed = 0.0 if not is_finite(value) else clampf(value, 0.0, 40.0)", txt)

    def test_diagnostic_survives_the_fix(self):
        # Hardening without a signal hides the real source of the bad sample.
        txt = read("scripts/player/character_controller.gd")
        self.assertIn("func _report_non_finite(where: String) -> void:", txt)
        self.assertIn("push_warning(", txt)


class CameraTests(unittest.TestCase):
    def test_shared_finiteness_helpers_exist(self):
        txt = read("scripts/main/camera/camera_math.gd")
        self.assertIn("static func is_finite_v3(v: Vector3) -> bool:", txt)
        self.assertIn("static func is_finite_transform(xform: Transform3D) -> bool:", txt)

    def test_rig_position_write_cannot_latch_nan(self):
        txt = read("scripts/main/camera_rig.gd")
        self.assertIn("func _apply_follow_position(next_pos: Vector3, weight: float) -> void:", txt)
        # Both follow lerps go through it; no raw lerp of global_position remains.
        self.assertEqual(txt.count("_apply_follow_position("), 3)  # def + 2 call sites
        self.assertNotIn("global_position = global_position.lerp(", txt)
        self.assertIn("var w := 1.0 if not is_finite(weight) else clampf(weight, 0.0, 1.0)", txt)

    def test_look_at_rejects_degenerate_frames(self):
        txt = read("scripts/main/camera_rig.gd")
        fn = txt[txt.index("func _update_look_at()"):txt.index("func _apply_follow_position(")]
        self.assertIn("if not CameraMath.is_finite_v3(cam_origin) or not CameraMath.is_finite_v3(look_target):", fn)
        self.assertIn("if cam_origin.distance_squared_to(look_target) < 0.0004:", fn)
        self.assertIn("if not CameraMath.is_finite_transform(target_xform):", fn)


class AnimationAndHazardTests(unittest.TestCase):
    def test_clip_length_cannot_return_garbage(self):
        txt = read("scripts/player/player_animation.gd")
        fn = txt[txt.index("func _length("):txt.index("func _play(")]
        self.assertIn("if _animation == null or not _animation.has_animation(clip):", fn)
        self.assertIn("if anim == null or not is_finite(anim.length) or anim.length <= 0.0:", fn)

    def test_shake_and_fov_cannot_commit_a_bad_camera(self):
        shake = read("scripts/main/camera/camera_shake_controller.gd")
        self.assertIn("if not CameraMath.is_finite_v3(trauma_offset):", shake)
        self.assertIn("if CameraMath.is_finite_transform(rolled):", shake)
        # The shake pass is the last writer of the camera transform in the frame.
        self.assertNotIn("\t_camera.global_transform = _camera.global_transform.rotated_local(", shake)
        fov = read("scripts/main/camera/camera_fov_controller.gd")
        self.assertIn("current_fov = _bounded(lerpf(current_fov, target_fov, weight))", fov)
        self.assertIn("func _bounded(fov: float) -> float:", fov)
        self.assertIn("return current_fov if is_finite(current_fov) else 45.0", fov)

    def test_hazard_visuals_are_optional_not_unguarded(self):
        """A hazard's visual may be gone; its gameplay may not be, and a NaN centre may
        never reach a body.

        The pin here is the property, not the plumbing: exactly one place resolves the
        marker reference, and it validates before dereferencing. (It used to assert that
        `_hazard_emission(h: Dictionary)` existed, which pinned the untyped-record design
        the subsystem was rebuilt to remove; the guard moved to HazardInstance.visual().)
        """
        instance = read("scripts/arena/hazard_instance.gd")
        guard = "func visual() -> HazardMarker:"
        self.assertIn(guard, instance)
        block = instance[instance.index(guard):][:400]
        self.assertIn("marker == null or not is_instance_valid(marker)", block)
        hazards = read("scripts/arena/arena_hazards.gd")
        # Every gameplay marker touch goes through the guarded accessor; the raw field is
        # only ever assigned, never dereferenced.
        self.assertIn("instance.marker = marker", hazards)
        self.assertNotIn("instance.marker.", hazards,
                        "arena_hazards.gd must not dereference a marker without guarding it")
        self.assertIn("\tvar marker := instance.visual()\n\tif marker == null:\n\t\treturn", hazards)
        # A non-finite epicentre is skipped before any victim is touched.
        self.assertIn("if not instance.position_is_sane():", hazards)
        self.assertIn("return is_finite(position.x) and is_finite(position.y) and is_finite(position.z)", instance)


class HarnessRegistrationTests(unittest.TestCase):
    def test_godot_suite_is_registered(self):
        txt = read("tests/run_tests.gd")
        self.assertIn('"res://tests/unit/test_locomotion_nan.gd"', txt)

    def test_guard_contract_covers_the_pipeline(self):
        txt = read("tool/validate_guards.py")
        for needle in ("scripts/player/character_controller.gd", "scripts/ui/virtual_joystick.gd",
                       "scripts/main/camera_rig.gd", "scripts/player/player_locomotion.gd"):
            self.assertIn(needle, txt)


if __name__ == "__main__":
    unittest.main()
