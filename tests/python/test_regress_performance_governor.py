"""Regression guards for the PerformanceMonitor governor rebuild.

The old monitor averaged FPS over a 60-sample window with absolute 45/57 fps
thresholds, started every run at a hardcoded HIGH tier regardless of the
player's saved graphics quality, never persisted what auto-scaling found,
and let ui_root re-assert the saved tier on EVERY settings save (clobbering
the auto-scaled tier). On top of that the "ultra" tier was unreachable: the
settings panel did not offer it and SettingsData silently dropped it, so the
value could never round-trip through a save.

Static-source guards on purpose: the Python suite runs without a Godot
binary, so each check asserts the shape of the fix. The deterministic
behavioural contract lives in tests/unit/test_performance_monitor.gd.
"""
from __future__ import annotations

import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8", errors="ignore")


def code_lines(text: str) -> str:
    """Only the executable lines: full-line and inline # / ## comments stripped.

    The autoload-identifier guard must not trip on a docstring that merely
    *names* SaveManager to explain the seam; it must trip on a real reference.
    """
    out: list[str] = []
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("#"):
            continue
        if " #" in line:
            line = line.split(" #", 1)[0]
        out.append(line)
    return "\n".join(out)


def func_body(text: str, name: str) -> str:
    m = re.search(
        r"^(?:static )?func %s\(.*?\).*?:\n(.*?)(?=^(?:static )?func |\Z)" % re.escape(name),
        text,
        re.S | re.M,
    )
    assert m is not None, "function %s not found" % name
    return m.group(1)


MONITOR = "scripts/utilities/performance_monitor.gd"
MAIN = "scripts/main/main.gd"
UI_ROOT = "scripts/ui/ui_root.gd"
PANEL = "scripts/ui/settings_panel.gd"
SETTINGS = "scripts/save/settings_data.gd"
RUNNER = "tests/run_tests.gd"


class UltraQualityRoundTripTests(unittest.TestCase):
    """All four governor tiers must be user-selectable and save-persistable."""

    def test_settings_accepts_ultra(self):
        txt = read(SETTINGS)
        self.assertIn('const QUALITY_PRESETS := [&"low", &"medium", &"high", &"ultra"]', txt)
        self.assertIn("value in QUALITY_PRESETS", txt)
        # The old whitelist (three presets) must be gone.
        self.assertNotIn('if value == &"low" or value == &"medium" or value == &"high":', txt)

    def test_settings_panel_offers_all_four_tiers(self):
        body = func_body(read(PANEL), "refresh")
        self.assertIn('[&"low", &"medium", &"high", &"ultra"]', body)

    def test_ui_root_still_maps_ultra(self):
        self.assertIn('&"ultra"', read(UI_ROOT))


class OpeningTierFromSaveTests(unittest.TestCase):
    """A run must open at the player's saved quality, not a hardcoded tier."""

    def test_main_configures_initial_tier_from_save(self):
        main = read(MAIN)
        self.assertIn("perf.configure(_initial_quality_tier()", main)
        body = func_body(main, "_initial_quality_tier")
        self.assertIn("SaveManager.get_settings().graphics_quality", body)
        self.assertIn("PerformanceMonitor.TIER_MEDIUM", body)

    def test_main_wires_the_persistence_seam(self):
        main = read(MAIN)
        self.assertIn("perf.set_persist_tier_callable(_persist_quality_tier)", main)
        body = func_body(main, "_persist_quality_tier")
        self.assertIn("next.set_graphics_quality(StringName(tier_name))", body)
        self.assertIn("SaveManager.save_settings(next)", body)

    def test_monitor_stays_free_of_autoload_identifiers(self):
        """Unit suites compile this script under --script, where autoload
        globals are not injected: any bare SaveManager/EventBus identifier
        would make the whole unit tier fail to load. The EventBus is resolved
        by path and cast to the project class (typed dispatch, no strings)."""
        code = code_lines(read(MONITOR))
        self.assertNotIn("SaveManager", code)
        self.assertNotIn("\nEventBus", code)
        self.assertIn('"/root/EventBus"', code)
        self.assertIn("as EventBusService", code)
        self.assertIn("bus.report_info(text)", code)
        # String dispatch is banned by the typed-architecture gate — no
        # exceptions. Debug telemetry uses the typed
        # OS.get_static_memory_usage() (4.4 has no total-RAM getter).
        self.assertNotIn(".has_method(", code)
        self.assertNotIn('.call("', code)
        self.assertIn("OS.get_static_memory_usage()", code)

    def test_governor_rebuild_suite_registered(self):
        self.assertIn("res://tests/unit/test_performance_monitor.gd", read(RUNNER))


class NoTierClobberTests(unittest.TestCase):
    """Saving an unrelated setting must not re-assert the saved tier."""

    def test_tier_applied_only_on_quality_change(self):
        ui = read(UI_ROOT)
        self.assertIn("var _last_applied_quality", ui)
        self.assertIn("if quality != _last_applied_quality:", ui)
        body = func_body(ui, "_apply_settings")
        # The guard must come before any set_tier call in the same function.
        self.assertLess(
            body.index("if quality != _last_applied_quality:"),
            body.index("monitor.set_tier(tier_idx)"),
            "the change guard must precede set_tier",
        )

    def test_auto_tier_changes_update_damage_budget(self):
        ui = read(UI_ROOT)
        self.assertIn("quality_tier_changed.connect(_on_monitor_tier_changed)", ui)
        body = func_body(ui, "_on_monitor_tier_changed")
        self.assertIn("set_max_live(monitor.max_damage_numbers())", body)


class GovernorAlgorithmTests(unittest.TestCase):
    """Frame-time percentiles, relative budgets, hysteresis, window clears."""

    def test_decisions_run_on_frame_time_not_fps_average(self):
        txt = read(MONITOR)
        self.assertIn("func push_frame_time(ms: float) -> void:", txt)
        self.assertIn("func process_tick(delta: float) -> void:", txt)
        self.assertIn("func get_p95_frame_ms() -> float:", txt)
        # Old absolute-fps machinery is gone.
        for gone in ("DOWN_THRESHOLD", "UP_THRESHOLD", "DOWN_SAMPLES", "UP_SAMPLES"):
            self.assertNotIn(gone, txt)
        self.assertNotIn("Engine.get_frames_per_second()", txt)

    def test_thresholds_are_relative_to_the_tier_budget(self):
        txt = read(MONITOR)
        self.assertIn("func frame_budget_ms(", txt)
        for ratio in (
            "DOWN_AVG_RATIO",
            "DOWN_P95_RATIO",
            "UP_AVG_RATIO",
            "UP_P95_RATIO",
            "AT_CAP_AVG_RATIO",
            "HITCH_BUDGET_MULT",
        ):
            self.assertIn("%s :=" % ratio, txt)

    def test_rate_capped_tiers_use_flat_pacing_gate(self):
        """A capped tier hides headroom: the upgrade gate must branch on
        'at the cap' instead of requiring average headroom the cap forbids."""
        body = func_body(read(MONITOR), "_is_clean")
        self.assertIn("AT_CAP_AVG_RATIO", body)
        self.assertIn("UP_P95_AT_CAP_RATIO", body)
        self.assertIn("UP_AVG_RATIO", body)

    def test_hysteresis_down_and_up(self):
        txt = read(MONITOR)
        self.assertIn("_down_streak >= 2", txt)
        # Auto downgrades must take the persisting _auto_step path, not the
        # manual request_step_down() (which by contract never persists):
        # the next launch has to open at the tier the device settled on.
        tick = func_body(txt, "_tick_auto_scale")
        self.assertIn("_auto_step(_tier - 1,", tick)
        self.assertNotIn("request_step_down()", tick)
        self.assertIn("UP_STABILITY_SECONDS := 15.0", txt)
        self.assertIn("now - _stable_since_msec >= int(UP_STABILITY_SECONDS * 1000.0)", txt)
        self.assertIn("MIN_SECONDS_BETWEEN_STEPS := 5.0", txt)
        self.assertIn("WARMUP_SECONDS := 3.0", txt)

    def test_window_clears_on_tier_change(self):
        body = func_body(read(MONITOR), "_change_tier")
        self.assertIn("_clear_ring()", body)

    def test_ring_is_o1_per_frame(self):
        txt = read(MONITOR)
        # 4.4 has no PackedFloat32Array(int) constructor, so the ring is built
        # via resize; the O(1) contract is the modulo head, not a growing FIFO.
        self.assertIn("static func make_ring() -> PackedFloat32Array:", txt)
        self.assertIn("r.resize(RING_SIZE)", txt)
        self.assertNotIn("PackedFloat32Array(RING_SIZE)", txt)
        # The ring starts empty (4.4-safe) and is lazily sized on first push.
        self.assertIn("if _ring.size() != RING_SIZE:", txt)
        self.assertIn("(_head + 1) % RING_SIZE", txt)
        # The old per-frame FIFO pop made every frame O(n).
        self.assertNotIn("remove_at(0)", txt)

    def test_auto_steps_persist_manual_never_do(self):
        txt = read(MONITOR)
        self.assertIn("func set_persist_tier_callable(callable: Callable) -> void:", txt)
        # The manual path takes no persist flag at all; only the shared
        # _change_tier can persist, and only when its auto caller asks.
        self.assertIn(
            "func set_tier(tier: int) -> void:\n\t_change_tier(clampi(tier, TIER_LOW, TIER_ULTRA))",
            txt,
        )
        self.assertIn(
            'func _change_tier(target: int, reason: String = "", persist: bool = false) -> void:',
            txt,
        )
        self.assertIn(
            "func _auto_step(new_tier: int, reason: String) -> void:\n"
            "\t_change_tier(clampi(new_tier, TIER_LOW, TIER_ULTRA), reason, true)",
            txt,
        )
        change = func_body(txt, "_change_tier")
        self.assertIn("_persist_tier.call(get_tier_name())", change)

    def test_deterministic_test_seams_exist(self):
        txt = read(MONITOR)
        self.assertIn("func set_test_time(ms: int) -> void:", txt)
        self.assertIn("func arm(now_ms: int = -1) -> void:", txt)

    def test_session_cap_survives_tier_changes(self):
        txt = read(MONITOR)
        self.assertIn("func configure(initial_tier: int, session_cap_fps: int = 0) -> void:", txt)
        body = func_body(txt, "_tier_fps_cap")
        self.assertIn("mini(base, _session_cap_fps)", body)
        self.assertNotIn("Engine.max_fps = 0", txt)


class EngineKnobTests(unittest.TestCase):
    """Real actuators: MSAA per tier, restored on teardown like the fps cap."""

    def test_msaa_follows_the_tier(self):
        body = func_body(read(MONITOR), "_apply_msaa")
        self.assertIn("Viewport.MSAA_DISABLED", body)
        self.assertIn("Viewport.MSAA_2X", body)
        self.assertIn("Viewport.MSAA_4X", body)
        self.assertIn("msaa_3d", body)

    def test_msaa_restored_on_exit_like_fps_cap(self):
        txt = read(MONITOR)
        exit_body = func_body(txt, "_exit_tree")
        self.assertIn("Engine.max_fps =", exit_body)
        self.assertIn("_restore_msaa()", exit_body)
        restore = func_body(txt, "_restore_msaa")
        self.assertIn('rendering/anti_aliasing/quality/msaa_3d', restore)
        self.assertEqual(txt.count("func _exit_tree"), 1)

    def test_apply_tier_to_engine_has_no_noop_guard(self):
        # Historical pin: the old DisplayServer name-check guard was a no-op.
        self.assertNotIn("pass", func_body(read(MONITOR), "_apply_tier_to_engine"))


if __name__ == "__main__":
    unittest.main()
