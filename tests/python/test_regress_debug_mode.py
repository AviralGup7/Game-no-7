"""Regression: debug-mode error trap contract (docs/DEBUG_MODE.md).

Pins the load-bearing shapes of the freeze-on-error system so a refactor
cannot silently break it:
  - the trap never freezes headless runs (no screen to read the report on),
  - error handling itself never emits diagnostics (no recursion),
  - the overlay sits above everything and swallows input while frozen,
  - stack traces skip the plumbing frames (frame #0 is the true caller),
  - errors are counted into analytics and visible to the test harness,
  - the toggle is reachable from the moment the game starts.
"""
from __future__ import annotations
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]

HANDLER = "scripts/debug/debug_error_handler.gd"
OVERLAY = "scripts/debug/debug_error_overlay.gd"
REPORT = "scripts/debug/error_report.gd"


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8", errors="ignore")


def code_lines(txt: str) -> str:
    # Comments may name a banned shape on purpose (the handler's own header
    # documents that EventBus.report_error is what it traps).
    return "\n".join(l for l in txt.splitlines() if not l.lstrip().startswith("#"))


class NoFreezeWithoutScreenTests(unittest.TestCase):
    def test_headless_runs_skip_the_pause(self) -> None:
        txt = read(HANDLER)
        self.assertIn('DisplayServer.get_name() == "headless"', txt)
        self.assertIn("_no_freeze", txt)

    def test_resume_re_reads_the_canonical_pause_flag(self) -> None:
        # The player may (un)pause via Android Back behind the overlay; restoring
        # a stale captured value would desync SceneTree.paused from GameRoot.
        txt = read(HANDLER)
        self.assertIn("GameRoot.is_paused() if GameRoot != null else _fallback_pause", txt)


class NoRecursionTests(unittest.TestCase):
    def test_error_handling_never_reports_an_error(self) -> None:
        # Any EventBus.report_* inside the handler would re-enter _on_diagnostic.
        txt = code_lines(read(HANDLER))
        self.assertNotIn("EventBus.report_", txt)
        self.assertIn('push_warning("DebugErrorHandler', txt)

    def test_analytics_error_counter_is_a_pure_increment(self) -> None:
        # note_error runs inside error handling; an emit there would recurse.
        txt = read("scripts/core/run_analytics.gd")
        body = txt[txt.find("func note_error()"):]
        body = body[:body.find("\n\n")]
        self.assertIn('_live["errors"]', body)
        self.assertNotIn("EventBus", body)
        self.assertNotIn("emit(", body)


class OverlayContractTests(unittest.TestCase):
    def test_overlay_sits_above_all_layers(self) -> None:
        txt = read(OVERLAY)
        self.assertIn("LAYER_ABOVE_ALL := 128", txt)
        self.assertIn("layer = LAYER_ABOVE_ALL", txt)

    def test_overlay_swallows_input_while_frozen(self) -> None:
        txt = read(OVERLAY)
        self.assertIn("MOUSE_FILTER_STOP", txt)
        self.assertIn("PROCESS_MODE_ALWAYS", txt)


class ReportWiringTests(unittest.TestCase):
    def test_plumbing_frames_are_stripped(self) -> None:
        self.assertIn("func drop_internal_frames(", read(REPORT))
        handler = read(HANDLER)
        self.assertIn("ErrorReport.drop_internal_frames(", handler)
        self.assertIn('INTERNAL_SOURCES := ["event_bus.gd", "debug_error_handler.gd"]', handler)

    def test_captures_pair_a_screenshot_with_the_log(self) -> None:
        handler = read(HANDLER)
        self.assertIn("func _capture_screenshot(", handler)
        self.assertIn('context["screenshot"]', handler)
        self.assertIn('_prune_files("crash_", ".png"', handler)


class IntegrationContractTests(unittest.TestCase):
    def test_handler_counts_errors_into_analytics(self) -> None:
        handler = read(HANDLER)
        self.assertIn("RunAnalytics.note_error()", handler)
        analytics = read("scripts/core/run_analytics.gd")
        self.assertIn('"errors": 0', analytics)
        self.assertIn('"session_errors"', analytics)

    def test_harness_exposes_the_debug_snapshot(self) -> None:
        harness = read("scripts/core/test_harness.gd")
        self.assertIn('"debug": DebugErrorHandler.get_debug_snapshot()', harness)
        self.assertIn('&"debug_trap_ready"', harness)

    def test_toggle_is_visible_from_game_start(self) -> None:
        self.assertIn("DebugModeToggle.new()", read("scripts/ui/menu_panel.gd"))
        settings = read("scripts/ui/settings_panel.gd")
        self.assertIn("DebugModeToggle.new()", settings)
        self.assertIn("TRIGGER TEST ERROR", settings)


if __name__ == "__main__":
    unittest.main()
