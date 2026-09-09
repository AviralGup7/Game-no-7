"""Regression guards for the Minimap radar v2 rebuild.

v1 re-sampled entity groups at 15 Hz and snapped every dot to its fresh
position, so tracks stepped ~0.5 m per refresh. It also carried a dead
`_north_up` member, had no spawn/death transitions, no facing cone, no threat
emphasis and no boss "danger" state — and it redrew unconditionally at the
discovery cadence even when nothing moved.

Static-source guards on purpose: the Python suite runs without a Godot
binary, so each check asserts the shape of the fix. The deterministic
behavioural contract lives in tests/unit/test_minimap_radar.gd.
"""
from __future__ import annotations

import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8", errors="ignore")


MINIMAP = "scripts/ui/minimap.gd"


def func_body(text: str, name: str) -> str:
    m = re.search(
        r"^(?:static )?func %s\((.*?)\n(.*?)(?=^func |^static func |\Z)" % re.escape(name),
        text,
        re.S | re.M,
    )
    assert m, "func %s not found" % name
    return m.group(2)


class TestMinimapRadarShape(unittest.TestCase):
    def test_v1_dead_code_removed(self) -> None:
        text = read(MINIMAP)
        self.assertNotIn("_north_up", text)
        # The 15 Hz cadence now appears exactly once, as the discovery
        # constant only — v1 used it to drive both sampling and drawing.
        self.assertEqual(text.count("1.0 / 15.0"), 1)
        self.assertIn("DISCOVERY_INTERVAL := 1.0 / 15.0", text)

    def test_v1_api_pinned(self) -> None:
        text = read(MINIMAP)
        self.assertIn("class_name Minimap", text)
        self.assertIn("extends Control", text)
        self.assertIn("static func project_to_map(", text)
        self.assertIn("var arena_half", text)
        self.assertIn("custom_minimum_size = Vector2(140, 140)", text)
        # Rim clamp semantics: offset normalised when mag > 1.
        body = func_body(text, "project_to_map")
        self.assertIn("mag > 1.0", body)

    def test_smoothing_is_exponential_and_framerate_independent(self) -> None:
        text = read(MINIMAP)
        body = func_body(text, "track_position")
        # Canonical frame-rate-independent smoothing, same family as
        # CameraMath.exp_weight (1 - exp(-rate * dt)); NOT a raw dt lerp.
        self.assertIn("1.0 - exp(-", body)
        self.assertNotIn("current.lerp(target, rate * delta)", body)
        self.assertIn("func advance_tracks(", text)

    def test_discovery_and_redraw_are_decoupled(self) -> None:
        text = read(MINIMAP)
        self.assertIn("DISCOVERY_INTERVAL := 1.0 / 15.0", text)
        proc = func_body(text, "_process")
        # Redraws are gated: idle radar must not queue_redraw() every frame.
        self.assertIn("if _dirty or _animating(now_ms):", proc)
        self.assertIn("_discovery_acc", proc)
        # Group queries live in _discover, not in the per-frame path.
        self.assertNotIn("get_nodes_in_group", proc)
        discover = func_body(text, "_discover")
        # Shared group constants (no ad-hoc string duplication).
        self.assertIn("get_nodes_in_group(EnemyBase.TARGET_GROUP)", discover)
        self.assertIn("get_nodes_in_group(Pickup.PICKUP_GROUP)", discover)
        self.assertIn("_find_arena()", discover)
        # Roster compare: repaint at discovery cadence only on change.
        self.assertIn("fresh != _live", discover)

    def test_threat_features_present(self) -> None:
        text = read(MINIMAP)
        # Spawn ping (newly spotted enemy) + death fade.
        self.assertIn("SPAWN_PING_MS := 1200", text)
        self.assertIn("TRACK_FADE_SECONDS := 0.35", text)
        self.assertIn("func ping_progress(", text)
        # Player facing cone (orientation on a north-up radar).
        self.assertIn("FOV_CONE_HALF_DEGREES := 35.0", text)
        self.assertIn("func wedge_points(", text)
        # Nearest-threat emphasis.
        self.assertIn("_nearest_threat_id", text)
        # Boss danger state (rim pulse + boss halo).
        self.assertIn("DANGER_PULSE_HZ := 1.4", text)
        self.assertIn("has_any_node_in_group(BossController.BOSS_GROUP)", text)
        # Facing cone uses Godot's -Z forward (v1 convention, not +X).
        self.assertIn("Vector2(-f.x, -f.z)", text)
        # Pickup expiry blink driven by real lifetime data.
        self.assertIn("PICKUP_BLINK_FRACTION := 0.75", text)
        self.assertIn("cfg.lifetime", text)
        self.assertIn("func blink_alpha(", text)

    def test_angle_and_vector_math_is_44_safe(self) -> None:
        text = read(MINIMAP)
        # DEG2RAD/RAD2DEG are Godot 3 globals (removed in 4.0); 4.x exposes
        # deg_to_rad()/rad_to_deg() instead.
        self.assertNotIn("DEG2RAD", text)
        self.assertNotIn("RAD2DEG", text)
        self.assertIn("deg_to_rad(FOV_CONE_HALF_DEGREES)", text)
        # Vector3.xz is not a 4.4 member: world projection goes through the
        # explicit world_xz() helper.
        self.assertIn("static func world_xz(p: Vector3) -> Vector2:", text)
        self.assertNotIn(".xz)", text)

    def test_dots_are_drawn_from_tracks_not_from_entities(self) -> None:
        text = read(MINIMAP)
        draw = func_body(text, "_draw")
        # Entity sampling must stay out of the draw path entirely: the canvas
        # renders the track table (smoothed display positions), never the raw
        # node transforms (v1's snap).
        self.assertIn("_tracks", draw)
        self.assertNotIn("get_nodes_in_group", draw)
        self.assertNotIn("EnemyBase", draw)
        self.assertNotIn("Pickup", draw)
        # The player wedge is the one intentional instant read.
        self.assertIn("_player", draw)

    def test_nan_guards(self) -> None:
        text = read(MINIMAP)
        self.assertGreaterEqual(text.count("is_finite("), 8)
        self.assertIn("func _finite_xz(", text)

    def test_help_legend_updated(self) -> None:
        help_text = read("scripts/ui/help_panel.gd")
        self.assertIn("closest threat", help_text)
        self.assertIn("new spawn", help_text)
        self.assertIn("where you face", help_text)

    def test_unit_suite_registered(self) -> None:
        run_tests = read("tests/run_tests.gd")
        self.assertIn("res://tests/unit/test_minimap_radar.gd", run_tests)
        unit = read("tests/unit/test_minimap_radar.gd")
        self.assertIn("static func suite() -> Array", unit)
        # The behavioural contract pins frame-rate independence explicitly.
        self.assertIn("frame-rate independent", unit)
        self.assertIn("advance_tracks", unit)
        self.assertIn("ping_progress", unit)
        self.assertIn("blink_alpha", unit)
        self.assertIn("wedge_points", unit)


if __name__ == "__main__":
    unittest.main()
