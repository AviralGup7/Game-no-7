"""Regression guards for the release-readiness QA pass.

Every test here pins a bug that was found by auditing the full existing-user flow
(launch -> menu -> run -> pause -> restart -> relaunch) and was fixed in that pass.
These are static-source guards on purpose: the repo's Python suite runs without a
Godot binary, so the checks assert the *shape* of the fix rather than executing it.
"""
from __future__ import annotations

import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8", errors="ignore")


def func_body(text: str, name: str) -> str:
    """Return the source of `func name(...)` up to the next top-level func."""
    m = re.search(r"^func %s\(.*?\).*?:\n(.*?)(?=^func |\Z)" % re.escape(name), text, re.S | re.M)
    assert m is not None, "function %s not found" % name
    return m.group(1)


class SkillBarSignalArityTests(unittest.TestCase):
    """SkillController.skill_became_ready(skill_id) has ONE argument.

    It used to be connected to _on_cooldown_event(skill_id, duration), which takes
    two required arguments, so Godot raised "too few arguments" every single time a
    skill came off cooldown.
    """

    def test_ready_signal_uses_single_arg_handler(self):
        txt = read("scripts/ui/skill_bar.gd")
        self.assertIn("skill_became_ready.connect(_on_skill_ready)", txt)
        self.assertNotIn("skill_became_ready.connect(_on_cooldown_event)", txt)

    def test_ready_signal_disconnects_the_same_handler_it_connects(self):
        txt = read("scripts/ui/skill_bar.gd")
        self.assertIn("skill_became_ready.disconnect(_on_skill_ready)", txt)
        self.assertNotIn("skill_became_ready.disconnect(_on_cooldown_event)", txt)

    def test_handler_arity_matches_each_signal(self):
        txt = read("scripts/ui/skill_bar.gd")
        self.assertRegex(txt, r"func _on_skill_ready\(\s*_?skill_id: StringName\s*\)")
        self.assertRegex(
            txt, r"func _on_cooldown_event\(\s*_?skill_id: StringName,\s*_?duration: float\s*\)"
        )

    def test_controller_signal_definitions_are_unchanged(self):
        ctl = read("scripts/skills/skill_controller.gd")
        self.assertIn("signal skill_became_ready(skill_id: StringName)", ctl)
        self.assertIn("signal skill_cooldown_started(", ctl)


class PauseDoesNotLeakIntoMainMenuTests(unittest.TestCase):
    """request_main_menu() must clear SceneTree.paused, not just the local flag.

    Setting `_paused = false` directly left `get_tree().paused == true`. Worse, the
    `if _paused == value: return` guard in _set_paused then swallowed every later
    unpause, so the next run started frozen while the UI stayed responsive.
    """

    def test_request_main_menu_goes_through_set_paused(self):
        body = func_body(read("scripts/core/game_root.gd"), "request_main_menu")
        self.assertIn("_set_paused(false)", body)

    def test_request_main_menu_does_not_assign_paused_directly(self):
        body = func_body(read("scripts/core/game_root.gd"), "request_main_menu")
        self.assertNotRegex(body, r"^\s*_paused\s*=", "assigning _paused directly re-introduces the leak")

    def test_set_paused_still_owns_all_three_pause_flags(self):
        body = func_body(read("scripts/core/game_root.gd"), "_set_paused")
        self.assertIn("_paused = value", body)
        self.assertIn("_current_run.paused = value", body)
        self.assertIn("tree.paused = value", body)


class WorldRebuildNameCollisionTests(unittest.TestCase):
    """_clear_world() must detach children, not only queue_free() them.

    queue_free() defers to the end of the frame, so the outgoing "Arena"/"Player"
    nodes still held their names while build_world() added the replacements. Godot
    renamed the new nodes ("Arena2", ...) and path lookups such as "WorldRoot/Arena"
    resolved to the dying node for the rest of the frame.
    """

    def test_clear_world_removes_before_freeing(self):
        body = func_body(read("scripts/main/main.gd"), "_clear_world")
        self.assertIn("remove_child(child)", body)
        self.assertIn("child.queue_free()", body)
        self.assertLess(
            body.index("remove_child(child)"),
            body.index("child.queue_free()"),
            "remove_child must happen before queue_free to free the node name immediately",
        )


class PerformanceMonitorRestoresFpsCapTests(unittest.TestCase):
    """Engine.max_fps is global but PerformanceMonitor is a per-run node.

    A run that degraded to the LOW tier pinned the whole app (menus included) to
    30 fps for the rest of the session, because nothing restored the cap on teardown.
    """

    def test_monitor_restores_max_fps_on_exit(self):
        # The mechanism is main's (_configured_max_fps() reads the project setting)
        # rather than the snapshot this branch originally used -- theirs is better,
        # since it cannot capture an already-degraded cap. Only the guarantee is
        # pinned: teardown must reassign Engine.max_fps.
        txt = read("scripts/utilities/performance_monitor.gd")
        self.assertIn("func _exit_tree", txt)
        self.assertIn("Engine.max_fps =", func_body(txt, "_exit_tree"))

    def test_only_one_exit_tree_is_defined(self):
        # Two independent fixes for this bug landed; a merge that keeps both would
        # be a duplicate func definition, which is a GDScript parse error.
        txt = read("scripts/utilities/performance_monitor.gd")
        self.assertEqual(txt.count("func _exit_tree"), 1)

    def test_dead_displayserver_noop_guard_removed(self):
        body = func_body(read("scripts/utilities/performance_monitor.gd"), "_apply_tier_to_engine")
        self.assertNotIn("pass", body, "the old DisplayServer.get_name() guard did nothing")


class DamageNumberPoolTests(unittest.TestCase):
    """The live budget was clamped to the initial pool size, so the ULTRA tier's
    request for 48 damage numbers silently stayed at 32."""

    def test_max_live_can_exceed_default_pool(self):
        txt = read("scripts/ui/damage_number_layer.gd")
        self.assertIn("const MAX_POOL", txt)
        self.assertIn("clampi(count, 4, MAX_POOL)", txt)

    def test_pool_grows_to_match_budget(self):
        body = func_body(read("scripts/ui/damage_number_layer.gd"), "set_max_live")
        self.assertIn("_pool.append(_make_label())", body)

    def test_ultra_tier_budget_fits_in_pool(self):
        layer = read("scripts/ui/damage_number_layer.gd")
        max_pool = int(re.search(r"const MAX_POOL := (\d+)", layer).group(1))
        monitor = read("scripts/utilities/performance_monitor.gd")
        wanted = [int(n) for n in re.findall(r"return (\d+)", func_body(monitor, "max_damage_numbers"))]
        self.assertTrue(wanted, "max_damage_numbers should return numeric budgets")
        self.assertLessEqual(max(wanted), max_pool)

    def test_recycled_label_is_reset(self):
        body = func_body(read("scripts/ui/damage_number_layer.gd"), "_obtain")
        self.assertIn("recycled.visible = false", body)


class OptionButtonIndexBoundsTests(unittest.TestCase):
    """OptionButton.selected is -1 before a pick; indexing the id arrays with it
    would read out of bounds."""

    def test_run_setup_clamps_selection_indices(self):
        txt = read("scripts/ui/run_setup_panel.gd")
        self.assertIn("func _selected_arena_index", txt)
        self.assertIn("func _selected_weapon_index", txt)
        self.assertNotIn("_arena_ids[_arenas.selected]", txt)
        self.assertNotIn("_weapon_ids[_weapons.selected]", txt)

    def test_clamp_is_lower_bounded_at_zero(self):
        txt = read("scripts/ui/run_setup_panel.gd")
        self.assertIn("clampi(_arenas.selected, 0,", txt)
        self.assertIn("clampi(_weapons.selected, 0,", txt)


class UiRootNullCastTests(unittest.TestCase):
    def test_status_title_lookup_is_null_checked(self):
        body = func_body(read("scripts/ui/ui_root.gd"), "_sync_from_state")
        self.assertIn("if title != null:", body)


class HeadlessRunnerIsTheRealSuiteTests(unittest.TestCase):
    """CI ran res://tests/run_tests.gd, but that file had been replaced by a
    temporary compile probe that only load()-ed five diagnostic copies and never
    executed a single assertion. The real runner was parked in tests/diag_full.gd."""

    def test_runner_executes_unit_suites(self):
        txt = read("tests/run_tests.gd")
        self.assertIn("const UNIT_SUITES", txt)
        self.assertIn('script.call("suite")', txt)

    def test_runner_runs_integration_stages(self):
        txt = read("tests/run_tests.gd")
        for stage in (
            "_run_combat_integration",
            "_run_attack_combo_integration",
            "_run_enemy_encounter_integration",
            "_run_boss_integration",
            "_run_spawn_manager_integration",
        ):
            self.assertIn(stage, txt, "runner lost the %s stage" % stage)

    def test_runner_is_not_a_compile_probe(self):
        txt = read("tests/run_tests.gd")
        self.assertNotIn("DIAGNOSTIC BUILD", txt)
        self.assertNotIn("const PROBES", txt)

    def test_diagnostic_copies_are_gone(self):
        for n in range(1, 5):
            self.assertFalse(
                (ROOT / ("tests/diag_var%d.gd" % n)).exists(),
                "tests/diag_var%d.gd is a duplicate of the runner and must not come back" % n,
            )
        self.assertFalse((ROOT / "tests/diag_full.gd").exists())

    def test_every_unit_suite_file_is_registered(self):
        txt = read("tests/run_tests.gd")
        listed = set(re.findall(r'"res://tests/unit/([^"]+)"', txt))
        on_disk = {p.name for p in (ROOT / "tests/unit").glob("*.gd")}
        self.assertEqual(
            on_disk - listed, set(), "unit suite(s) exist but are never run by the headless runner"
        )

    def test_registered_suites_all_exist(self):
        txt = read("tests/run_tests.gd")
        for rel in re.findall(r'"res://(tests/unit/[^"]+)"', txt):
            self.assertTrue((ROOT / rel).exists(), "runner references missing suite %s" % rel)


class LintCleanlinessTests(unittest.TestCase):
    """docs claim `gdlint scripts tests` passes; two function-scope names broke it."""

    def test_no_underscore_prefixed_locals_that_are_used(self):
        for rel in ("scripts/ui/tutorial_manager.gd", "scripts/waves/wave_manager.gd"):
            txt = read(rel)
            self.assertNotIn("var _p_check", txt)
            self.assertNotIn("var _pl:", txt)


class AndroidPermissionDocAccuracyTests(unittest.TestCase):
    """The policy doc claimed the game never calls vibrate_handheld. It does."""

    def test_doc_acknowledges_haptics(self):
        doc = read("docs/ANDROID_PERMISSIONS.md")
        self.assertIn("vibrate_handheld", doc)
        self.assertNotIn("does not call `vibrate_handheld`", doc)

    def test_haptics_are_still_gated_on_the_user_setting(self):
        txt = read("scripts/ui/touch_action_button.gd")
        self.assertIn("vibration_enabled", txt)


if __name__ == "__main__":
    unittest.main()
