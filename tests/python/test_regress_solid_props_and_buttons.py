"""Regression: solid decoration props + the touch-action button dispatch.

Two player-visible defects are pinned here:

1. "The character walks through objects." The arena's interior obstacles and the
   central landmark were already solid, but the KayKit clutter the decorator
   scatters (barrels / crates / boxes / rubble / braziers / ice shards) was
   visual-only, so the hero and every enemy passed straight through them. Every
   floor-standing prop now gets a StaticBody3D on the world layer plus a nav-grid
   footprint, and props keep clear of the spawn markers.

2. "Clicking the attack button does nothing / kills the run." TouchActionButton
   ran the settings lookup + haptics BEFORE emitting `pressed`, so any failure in
   that presentation step aborted `_fire()` and swallowed the gameplay intent.
   The command is now delivered first and haptics are best-effort.
"""
from __future__ import annotations

import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]

DECORATOR = "scripts/arena/arena_decorator.gd"
ARENA = "scripts/arena/arena.gd"
BUTTON = "scripts/ui/touch_action_button.gd"
CONTROLS = "scripts/ui/touch_controls.gd"
COMMANDS = "scripts/ui/ui_commands.gd"


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8", errors="ignore")


def func_body(rel: str, name: str) -> str:
    """The source of `func <name>(...)` in `rel`, up to the next top-level func."""
    text = read(rel)
    m = re.search(r"\nfunc %s\(.*?(?=\nfunc |\Z)" % re.escape(name), text, re.S)
    if m is None:
        raise AssertionError("func %s() not found in %s" % (name, rel))
    return m.group(0)


class SolidDecorationTests(unittest.TestCase):
    def test_scattered_clutter_gets_a_collider(self):
        for fn in ("_scatter", "_mount_prop", "_compose_frost"):
            self.assertIn(
                "_add_prop_collision(",
                func_body(DECORATOR, fn),
                msg="%s() must give its props collision (nothing walks through objects)" % fn,
            )

    def test_collider_is_on_the_world_layer_the_actors_collide_with(self):
        body = func_body(DECORATOR, "_add_prop_collision")
        self.assertIn("StaticBody3D.new()", body)
        # Named bits, not `= 1`/`= 0`: this branch's collision contract (`tool/validate_guards.py` and
        # `tests/python/test_regress_collision_contract.py`) refuses a numeric layer anywhere under
        # scripts/. What this test cares about — a prop body is world-solid and queries nothing — holds.
        self.assertIn("body.collision_layer = CollisionLayers.WORLD_BODY_LAYER", body)
        self.assertIn("body.collision_mask = CollisionLayers.NO_LAYER", body)
        self.assertIn("BoxShape3D.new()", body)
        # Sized from the mounted model's own AABB, not a hardcoded guess.
        self.assertIn("_combined_local_aabb(", body)

    def test_collider_size_is_clamped(self):
        body = func_body(DECORATOR, "_add_prop_collision")
        for const in ("MIN_PROP_HALF", "MAX_PROP_HALF_XZ", "MAX_PROP_HALF_Y"):
            self.assertIn(const, body, msg="collider must clamp with %s" % const)

    def test_footprints_are_published_to_the_nav_grid(self):
        self.assertIn("_blockers.append(", func_body(DECORATOR, "_add_prop_collision"))
        self.assertIn("arena.register_decoration_blockers(", read(DECORATOR))
        self.assertIn("func get_nav_blockers", read(DECORATOR))
        self.assertIn("func register_decoration_blockers", read(ARENA))
        self.assertIn("_rebuild_navigation_floor()", func_body(ARENA, "register_decoration_blockers"))
        self.assertIn(
            "for foot in _decoration_blockers",
            func_body(ARENA, "_build_navigation_floor"),
            msg="the nav grid must block the same cells the new colliders block",
        )

    def test_structural_pillars_join_the_nav_grid_too(self):
        # Pillars always had collision but were missing from the nav grid, so the
        # AI's intent walked straight through them and leaned on the body.
        self.assertIn("_blockers.append(", func_body(DECORATOR, "_place_structural"))

    def test_props_keep_clear_of_spawn_markers(self):
        self.assertIn("SPAWN_MARKER_CLEAR_RADIUS", read(DECORATOR))
        self.assertIn("_spawn_marker_positions()", func_body(DECORATOR, "_open_spot"))
        self.assertIn("get_spawn_points()", func_body(DECORATOR, "_spawn_marker_positions"))

    def test_solid_prop_suite_is_registered_with_the_godot_runner(self):
        self.assertIn("tests/unit/test_decorator_collision.gd", read("tests/run_tests.gd"))


class TouchActionButtonTests(unittest.TestCase):
    def test_command_is_emitted_before_haptics(self):
        body = func_body(BUTTON, "_fire")
        self.assertLess(
            body.index("pressed.emit()"),
            body.index("_vibrate()"),
            msg="the gameplay intent must be delivered before the presentation-only haptic call",
        )

    def test_haptics_are_guarded(self):
        body = func_body(BUTTON, "_vibrate")
        self.assertIn("settings == null", body)
        self.assertIn("vibration_enabled", body)
        self.assertIn('OS.has_feature("mobile")', body)

    def test_buttons_route_through_one_guarded_dispatcher(self):
        self.assertIn("button.pressed.connect(_on_button_pressed.bind(method))", read(CONTROLS))
        self.assertIn("func _on_button_pressed(command: StringName)", read(CONTROLS))
        self.assertIn("UiCommands.action(command)", func_body(CONTROLS, "_on_button_pressed"))

    def test_skill_slot_arg_is_type_checked(self):
        self.assertIn("args[0] is int or args[0] is float", read(COMMANDS))


if __name__ == "__main__":
    unittest.main()
