"""Regression: UI modularisation — shared primitives stay single-sourced.

Guards the UiFactory / UiTheme widget vocabulary so future UI code composes the
shared primitives (primary, overlay, select_card, gauge, metric, kicker,
hairline) instead of re-implementing their chrome. Also keeps the extracted
UiGauges dock authoritative for the in-run meters so that chrome can never drift
between the HUD and any other gauge.
"""

from __future__ import annotations

import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
UI = ROOT / "scripts" / "ui"


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8", errors="ignore")


class FactoryVocabularyTests(unittest.TestCase):
    def test_shared_primitives_all_live_in_ui_factory(self):
        txt = read("scripts/ui/ui_factory.gd")
        for func in ("primary", "overlay", "select_card", "gauge", "metric", "kicker", "hairline", "screen_header"):
            self.assertIn("static func %s(" % func, txt, func)

    def test_overlay_scaffold_is_the_only_full_screen_root(self):
        # Floating screens must mount through UiFactory.overlay (or the UiRoot
        # _mount_overlay wrapper), never hand-roll scroll+centre by hand.
        factory = read("scripts/ui/ui_factory.gd")
        self.assertIn("static func overlay(", factory)
        self.assertIn('return {"panel": panel, "box": box', factory)
        root = read("scripts/ui/ui_root.gd")
        self.assertIn("func _mount_overlay(", root)
        # No inline full-screen scaffold remains in the composition root.
        self.assertNotIn("UiFactory.center_box(", root)


class UiGaugesTests(unittest.TestCase):
    def test_gauges_dock_exists_and_is_dedicated(self):
        body = read("scripts/ui/ui_gauges.gd")
        self.assertIn("class_name UiGauges", body)
        self.assertIn("extends VBoxContainer", body)

    def test_gauges_share_the_factory_gauge(self):
        body = read("scripts/ui/ui_gauges.gd")
        for member in ("health_bar", "stamina_bar", "xp_bar"):
            self.assertIn("%s = UiFactory.gauge(self" % member, body)
        # The dock must never hand-build a meter (single source of chrome).
        self.assertNotIn("ProgressBar.new()", body)

    def test_hud_instantiates_the_packed_gauges_scene(self):
        hud = read("scripts/ui/game_hud.gd")
        self.assertIn("const GAUGES_SCENE := preload(\"res://scenes/ui/ui_gauges.tscn\")", hud)
        self.assertIn("_gauges = GAUGES_SCENE.instantiate() as UiGauges", hud)
        self.assertIn("func set_health", hud)
        # HUD no longer constructs raw meters; the dock owns that chrome.
        self.assertNotIn("ProgressBar.new()", hud)

    def test_gauges_packed_scene_is_valid_and_wired(self):
        # The thin-shell scene lets editors grab the dock as a node while metre
        # chrome stays single-sourced in UiFactory.gauge via the script.
        scene = (ROOT / "scenes/ui/ui_gauges.tscn").read_text(encoding="utf-8")
        self.assertIn("type=\"VBoxContainer\"", scene)
        self.assertIn("path=\"res://scripts/ui/ui_gauges.gd\"", scene)
        self.assertIn("type=\"Script\"", scene)


class ModalAndScreenHeaderTests(unittest.TestCase):
    def test_confirm_flow_routes_through_uimodal(self):
        modal = read("scripts/ui/ui_modal.gd")
        self.assertIn("class_name UiModal", modal)
        for member in ("func confirm(", "func cancel_all()", "func _present()", "func _restore_focus()"):
            self.assertIn(member, modal)
        root = read("scripts/ui/ui_root.gd")
        self.assertIn("_modal = UiModal.new()", root)
        self.assertIn("_confirm = _modal.get_dialog()", root)
        # No screen hand-builds a ConfirmationDialog any more.
        self.assertNotIn("ConfirmationDialog.new()", root)

    def test_floating_menus_share_the_screen_header(self):
        factory = read("scripts/ui/ui_factory.gd")
        self.assertIn("static func screen_header(", factory)
        root = read("scripts/ui/ui_root.gd")
        for needle in ("UiFactory.screen_header(box, \"\", String(key).to_upper()",
                       "UiFactory.screen_header(status_box, \"LOADING\"",
                       "UiFactory.screen_header(box, \"TAKE A BREATH\""):
            self.assertIn(needle, root)
        self.assertIn("status_header.title.name = \"StatusTitle\"", root)


class RuntimeLinkageTests(unittest.TestCase):
    def test_engine_runner_smokes_the_modular_components(self):
        # Codify that tests/ui/ui_test_runner.gd exercises the new components at
        # runtime (it runs in the Godot engine / CI), not just in static text.
        runner = read("tests/ui/ui_test_runner.gd")
        for needle in ("_ui._hud._gauges is UiGauges",
                       "_ui._modal",
                       "mouse_filter == Control.MOUSE_FILTER_STOP"):
            self.assertIn(needle, runner)


class MeterChromeTests(unittest.TestCase):
    def test_only_the_factory_and_boss_frame_build_meters(self):
        # Progress bars are constructed in exactly two places by design: the
        # shared UiFactory.gauge and the layered boss frame (which needs its own
        # full-rect anchored stack). Everywhere else must reuse them.
        for rel in ["scripts/ui/ui_factory.gd", "scripts/ui/boss_health_bar.gd"]:
            self.assertIn("ProgressBar.new()", read(rel))
        for rel in ["scripts/ui/menu_panel.gd", "scripts/ui/run_setup_panel.gd",
                    "scripts/ui/run_summary_panel.gd", "scripts/ui/upgrade_panel.gd",
                    "scripts/ui/settings_panel.gd", "scripts/ui/armory_panel.gd"]:
            self.assertNotIn("ProgressBar.new()", read(rel), rel)

    def test_boss_meter_reuses_the_shared_fill_token(self):
        body = read("scripts/ui/boss_health_bar.gd")
        self.assertIn("UiTheme.bar(fill)", body)


class CataloguePickerTests(unittest.TestCase):
    def test_run_setup_uses_the_shared_select_card(self):
        setup = read("scripts/ui/run_setup_panel.gd")
        factory = read("scripts/ui/ui_factory.gd")
        self.assertIn("UiFactory.select_card(body", setup)
        self.assertIn("OptionButton.new()", factory)  # cards built once in the factory


if __name__ == "__main__":
    unittest.main()
