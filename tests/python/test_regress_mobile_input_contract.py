"""Regression: the mobile input & interruption contract.

The touch/input layer is the least device-verified surface in the game and it
carried the weakest shapes in the tree, all fixed in one pass:

1. TouchControls._ready's tail (resized/visibility wiring + first layout) was
   mis-indented INSIDE _on_button_pressed: every declined tap re-connected two
   signals (engine errors) and stomped UiRoot's safe-area plan with a full-rect
   fallback recompute, jumping the stick/buttons mid-combat.
2. project.godot carried a dead emulation setting
   (`window/handheld/emulate_touchscreen_mouse` — no such engine key) while the
   two real keys went unstated; and Back-button behavior was left on the engine
   default (quit_on_go_back=true), which quits the app instantly from anywhere.
3. Nothing auto-paused on app interruption: Android/iOS background the app
   WITHOUT pausing the tree, so a call taken mid-wave meant returning to a
   corpse (AudioManager already mutes for exactly this reason).
4. TouchActionButton fired on RELEASE, adding the whole tap duration as input
   latency to the two most time-critical verbs; the engine's own gameplay
   button (TouchScreenButton.pressed) fires on press-down.
5. VirtualJoystick._input routed every normal thumb-lift through cancel(),
   dumping the 20-line input trace per release and arming an 80 ms ignore
   window that ate fast re-taps; _draw mixed physical safe-area pixels with
   logical units for an inset UiSafeArea+UiLayout already own upstream.
6. scripts/device_qa.sh hardcoded a launch package that had drifted from the
   export preset, so the smoke-launch targeted an uninstalled package.

Each test below pins the FIXED shape (and would fail if the defect returned).
"""
from __future__ import annotations

import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8", errors="ignore")


def func_body(rel: str, name: str) -> str:
    """Source of `func <name>(...)` in `rel`, up to the next top-level func."""
    text = read(rel)
    m = re.search(r"\nfunc %s\(.*?(?=\nfunc |\Z)" % re.escape(name), text, re.S)
    if m is None:
        raise AssertionError("func %s() not found in %s" % (name, rel))
    return m.group(0)


def project_setting_lines() -> list[str]:
    """Non-comment, non-section key=value lines of project.godot."""
    out: list[str] = []
    for raw in read("project.godot").splitlines():
        line = raw.strip()
        if not line or line.startswith(";") or line.startswith("["):
            continue
        out.append(line)
    return out


class ProjectConfigHonestyTests(unittest.TestCase):
    def test_no_dead_emulation_setting(self):
        for line in project_setting_lines():
            self.assertNotIn(
                "emulate_touchscreen_mouse",
                line,
                msg="no such engine setting exists; the real keys are input_devices/pointing/*",
            )

    def test_emulation_keys_are_real_and_intentional(self):
        lines = project_setting_lines()
        self.assertIn("pointing/emulate_mouse_from_touch=true", lines)
        self.assertIn("pointing/emulate_touch_from_mouse=false", lines)
        # They must sit in their own section: under [display] they would
        # resolve to display/input_devices/... and silently do nothing.
        text = read("project.godot")
        section = text.split("[input_devices]")[1].split("[input]")[0]
        self.assertIn("pointing/emulate_mouse_from_touch=true", section)

    def test_max_fps_override_hangs_off_the_real_key(self):
        lines = project_setting_lines()
        self.assertIn("run/max_fps=0", lines)
        self.assertIn("run/max_fps.android=60", lines)
        # An absolute-form line under [application] would resolve to
        # application/application/... and silently do nothing.
        for line in lines:
            self.assertFalse(
                line.startswith("application/run/max_fps"),
                msg="section-absolute max_fps line resolves nowhere: %s" % line,
            )

    def test_back_button_is_owned_in_game_not_by_quit(self):
        self.assertIn("config/quit_on_go_back=false", project_setting_lines())


class TouchControlsWiringTests(unittest.TestCase):
    def test_layout_backstops_live_in_ready(self):
        body = func_body("scripts/ui/touch_controls.gd", "_ready")
        self.assertIn("resized.connect(_layout)", body)
        self.assertIn("visibility_changed.connect(_on_visibility_changed)", body)
        self.assertIn("_layout.call_deferred()", body)

    def test_press_handler_never_rewires_layout(self):
        # The exact bug shape: signal wiring inside the per-press handler.
        body = func_body("scripts/ui/touch_controls.gd", "_on_button_pressed")
        self.assertNotIn(".connect(", body)
        self.assertNotIn("_layout", body)

    def test_process_has_no_dead_paused_branch(self):
        # PROCESS_MODE_INHERIT never runs _process while paused; UiRoot's
        # cancel() owns pause cleanup, so a paused branch here is dead code.
        body = func_body("scripts/ui/touch_controls.gd", "_process")
        self.assertNotIn("get_tree().paused", body)


class TouchActionButtonSemanticsTests(unittest.TestCase):
    def test_press_down_fires(self):
        body = func_body("scripts/ui/touch_action_button.gd", "_gui_input")
        press = body.split("if t.pressed and not _held:")[1].split("elif")[0]
        self.assertIn("_fire()", press)
        mouse_press = body.split("if mb.pressed and not _held:")[1].split("elif")[0]
        self.assertIn("_fire()", mouse_press)

    def test_release_clears_without_firing(self):
        body = func_body("scripts/ui/touch_action_button.gd", "_gui_input")
        touch_release = body.split("elif not t.pressed and _held")[1].split("elif event is")[0]
        mouse_release = body.split("elif not mb.pressed and _held")[1]
        for branch in (touch_release, mouse_release):
            self.assertNotIn("_fire()", branch)
            self.assertIn("cancel()", branch)
        cancel = func_body("scripts/ui/touch_action_button.gd", "cancel")
        self.assertIn("_held = false", cancel)
        self.assertIn("_aim = Vector2.ZERO", cancel)
        self.assertIn("_publish_fire()", cancel)

    def test_fire_does_not_clear_the_hold(self):
        # Clearing in _fire() would re-arm mid-press and let a second finger
        # double-fire; release branches and cancel() own the clearing.
        body = func_body("scripts/ui/touch_action_button.gd", "_fire")
        self.assertNotIn("_held = false", body)
        self.assertNotIn("_touch_index = -1", body)


class VirtualJoystickHygieneTests(unittest.TestCase):
    def test_draw_uses_logical_units_only(self):
        # The safe area arrives in physical pixels; UiSafeArea+UiLayout already
        # map it upstream, so _draw must not read DisplayServer at all.
        body = func_body("scripts/ui/virtual_joystick.gd", "_draw")
        self.assertNotIn("DisplayServer", body)

    def test_normal_release_is_quiet(self):
        # A thumb lifting is the normal end of a drag: quiet _end(), not the
        # trace-dumping cancel() (logcat spam + 80 ms re-tap block per lift).
        body = func_body("scripts/ui/virtual_joystick.gd", "_input")
        self.assertNotIn("cancel()", body)
        self.assertIn("_end()", body)

    def test_abnormal_ends_keep_their_paper_trail(self):
        body = func_body("scripts/ui/virtual_joystick.gd", "cancel")
        self.assertIn("InputTrace.dump(", body)


class InterruptionRoutingTests(unittest.TestCase):
    def test_game_root_auto_pauses_on_interruption(self):
        body = func_body("scripts/core/game_root.gd", "_notification")
        for note in (
            "NOTIFICATION_APPLICATION_PAUSED",
            "NOTIFICATION_APPLICATION_FOCUS_OUT",
            "NOTIFICATION_WM_WINDOW_FOCUS_OUT",
        ):
            self.assertIn(note, body)
        # Ungated, every menu alt-tab would log an illegal-pause warning.
        self.assertIn("if _can_pause_from(_current_state):", body)
        self.assertIn("request_pause()", body)
        # No auto-resume: the pause screen owns the return.
        self.assertNotIn("request_resume()", body)

    def test_ui_root_routes_the_back_button(self):
        notify = func_body("scripts/ui/ui_root.gd", "_notification")
        self.assertIn("NOTIFICATION_WM_GO_BACK_REQUEST", notify)
        body = func_body("scripts/ui/ui_root.gd", "_handle_back_button")
        self.assertIn("_modal.cancel_all()", body)
        self.assertIn("_close_auxiliary()", body)
        self.assertIn("GameRoot.request_pause()", body)
        self.assertIn("GameRoot.request_resume()", body)
        self.assertIn("GameRoot.request_main_menu()", body)
        self.assertIn("_request_quit()", body)


class DeviceQaPackageTests(unittest.TestCase):
    def test_launch_package_tracks_the_preset(self):
        script = read("scripts/device_qa.sh")
        self.assertIn("package/unique_name", script)
        self.assertIn("export_presets.cfg", script)
        stale = "com.laststand.arena"
        for line in script.splitlines():
            stripped = line.strip()
            if stripped.startswith("#"):
                continue
            self.assertNotIn(stale, stripped)
        self.assertNotIn(stale, read("docs/DEVICE_QA.md"))


if __name__ == "__main__":
    unittest.main()
