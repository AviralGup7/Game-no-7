"""Regression: UI/UX polish pass — shared layout solver, touch targets, theme.

These are static guards over the presentation layer. The *behavioural* geometry
contract (no overlaps, everything inside the safe area, touch-target floor at
every Android resolution and text scale) is asserted at runtime by
``_test_layout_solver`` in ``tests/ui/ui_test_runner.gd``.
"""

from __future__ import annotations

import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
UI = ROOT / "scripts" / "ui"


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8", errors="ignore")


class LayoutSolverTests(unittest.TestCase):
    def test_solver_exists_and_is_pure(self):
        txt = read("scripts/ui/ui_layout.gd")
        self.assertIn("class_name UiLayout", txt)
        for func in ("compute", "sanitize", "place", "is_collapsed", "gutter", "is_compact"):
            self.assertIn("static func %s(" % func, txt)
        # A pure solver must not reach into the tree or singletons.
        for forbidden in ("get_tree()", "get_viewport(", "DisplayServer.", "EventBus."):
            self.assertNotIn(forbidden, txt)
        # Portrait phones (1080x2340) are compact even though width >= 900.
        self.assertIn("size.x < NARROW_WIDTH or size.x < size.y", txt)
        self.assertNotIn("return size.x < 900.0\n", txt)

    def test_short_viewport_shrinks_the_action_cluster(self):
        txt = read("scripts/ui/ui_layout.gd")
        self.assertIn("cluster.size.y = maxf(minf(cluster.size.y, room), MIN_TOUCH)", txt)
        self.assertIn("static func _action_rects(", txt)

    def test_solver_publishes_every_overlay_rect(self):
        txt = read("scripts/ui/ui_layout.gd")
        for key in (
            "top_bar", "vitals", "minimap", "boss", "banner",
            "toast", "stick", "attack", "dodge", "swap", "skills",
        ):
            self.assertIn('"%s":' % key, txt)

    def test_touch_target_floor_is_android_accessible(self):
        txt = read("scripts/ui/ui_layout.gd")
        match = re.search(r"const MIN_TOUCH := ([0-9.]+)", txt)
        self.assertIsNotNone(match)
        self.assertGreaterEqual(float(match.group(1)), 88.0)
        self.assertGreaterEqual(int(re.search(r"const TOUCH_MIN := (\d+)", read("scripts/ui/ui_theme.gd")).group(1)), 88)

    def test_root_drives_every_overlay_from_one_solution(self):
        txt = read("scripts/ui/ui_root.gd")
        self.assertIn("UiLayout.compute(view, _text_scale)", txt)
        self.assertIn("_hud.apply_layout(plan, view)", txt)
        self.assertIn("_touch.apply_layout(plan, view)", txt)
        # The old hardcoded pixel offsets must be gone.
        for stale in ("Vector2(290, 160)", "width * 0.5 - 160", "width < 850", "height - (210"):
            self.assertNotIn(stale, txt)

    def test_no_magic_offsets_left_in_overlay_widgets(self):
        for rel in ("scripts/ui/game_hud.gd", "scripts/ui/touch_controls.gd"):
            txt = read(rel)
            self.assertIn("apply_layout", txt)
            self.assertNotIn("PRESET_BOTTOM_WIDE", txt)


class TouchAndFeedbackTests(unittest.TestCase):
    def test_action_buttons_have_press_feedback(self):
        txt = read("scripts/ui/touch_action_button.gd")
        self.assertIn("if _held", txt)
        self.assertIn("outline_size", txt)  # label stays readable over the arena
        self.assertIn("UiTheme.GOLD if _held else UiTheme.CYAN", txt)

    def test_joystick_draws_in_local_space(self):
        txt = read("scripts/ui/virtual_joystick.gd")
        self.assertIn("var local_base := _base", txt)
        self.assertIn("var local_knob := _knob", txt)

    def test_touch_controls_still_thumb_friendly(self):
        txt = read("scripts/ui/touch_controls.gd")
        self.assertIn("64.0", txt)  # attack remains the largest target
        self.assertIn("52.0", txt)

    def test_skill_bar_sizes_from_bar_rect(self):
        txt = read("scripts/ui/skill_bar.gd")
        self.assertIn("func fit_touch_targets(bar_size: Vector2)", txt)
        self.assertIn("UiLayout.MIN_TOUCH", txt)
        # Ready / cooling / locked must be visually distinct, not just text.
        self.assertIn("Color(1, 1, 1, 0.45)", txt)
        self.assertIn("Color(1, 1, 1, 0.7)", txt)

    def test_hud_pause_is_a_full_touch_target(self):
        txt = read("scripts/ui/game_hud.gd")
        self.assertIn("UiLayout.MIN_TOUCH", txt)


class ThemeConsistencyTests(unittest.TestCase):
    def test_spacing_scale_is_shared(self):
        txt = read("scripts/ui/ui_theme.gd")
        for const in ("SPACE_S", "SPACE_M", "SPACE_L", "RADIUS", "TOUCH_MIN"):
            self.assertIn("const %s :=" % const, txt)

    def test_pressed_state_is_distinct_from_hover(self):
        txt = read("scripts/ui/ui_theme.gd")
        self.assertIn('theme.set_stylebox("pressed"', txt)
        self.assertIn("font_pressed_color", txt)

    def test_labels_use_the_project_font(self):
        txt = read("scripts/ui/ui_theme.gd")
        self.assertIn('theme.set_font("font", "Label", REGULAR)', txt)
        self.assertIn('theme.set_font("font", "RichTextLabel", REGULAR)', txt)

    def test_factory_never_emits_a_small_button(self):
        txt = read("scripts/ui/ui_factory.gd")
        self.assertIn("maxf(min_size.y, UiTheme.TOUCH_MIN)", txt)
        self.assertIn("UiTheme.TOUCH_MIN", txt)

    def test_no_hardcoded_56px_targets_remain(self):
        for path in sorted(UI.glob("*.gd")):
            body = path.read_text(encoding="utf-8", errors="ignore")
            self.assertNotIn("custom_minimum_size.y = 56", body, path.name)
            self.assertNotIn("Vector2(220, 56)", body, path.name)


class ResponsiveScreenTests(unittest.TestCase):
    def test_upgrade_grid_reflows_by_width(self):
        txt = read("scripts/ui/upgrade_panel.gd")
        self.assertIn("clampi(", txt)
        self.assertNotIn("size.x < 1000", txt)

    def test_menu_secondary_row_stacks_when_narrow(self):
        txt = read("scripts/ui/menu_panel.gd")
        self.assertIn("_row.vertical = size.x < 560.0", txt)

    def test_confirm_dialog_is_sized_from_the_viewport(self):
        # Modal sizing/focus moved out of ui_root into the UiModal controller; the
        # guard now pins the location so it is not re-inlined or hardcoded.
        txt = read("scripts/ui/ui_modal.gd")
        self.assertIn("class_name UiModal", txt)
        self.assertIn("func confirm(", txt)
        self.assertIn("func _present()", txt)
        self.assertIn("AUTOWRAP_WORD_SMART", txt)
        self.assertNotIn("popup_centered(Vector2i(500, 220))", txt)
        root = read("scripts/ui/ui_root.gd")
        self.assertIn("_modal.confirm(", root)
        self.assertIn("_confirm = _modal.get_dialog()", root)

    def test_center_box_measure_is_capped_for_readability(self):
        txt = read("scripts/ui/ui_factory.gd")
        self.assertIn("panel.size.x * 0.62", txt)

    def test_runtime_geometry_contract_is_exercised(self):
        txt = read("tests/ui/ui_test_runner.gd")
        self.assertIn("_test_layout_solver()", txt)
        self.assertIn("do not overlap", txt)
        self.assertIn("meets touch floor", txt)
        self.assertIn("Vector2(1080, 2340)", txt)  # tall portrait Android
        self.assertIn('"res://tests/unit/test_ui_layout.gd"', read("tests/run_tests.gd"))

    def test_hud_rewrites_compact_captions_on_layout(self):
        hud = read("scripts/ui/game_hud.gd")
        self.assertIn("_refresh_wave_label()", hud)
        self.assertIn("_score_label.visible = not _compact", hud)
        self.assertIn("_gauges.set_compact(_compact)", hud)
        gauges = read("scripts/ui/ui_gauges.gd")
        self.assertIn('stamina_caption.text = "STA %d/%d"', gauges)


if __name__ == "__main__":
    unittest.main()
