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
    """Return the source of `[static] func name(...)` up to the next top-level func."""
    m = re.search(
        r"^(?:static )?func %s\(.*?\).*?:\n(.*?)(?=^(?:static )?func |\Z)" % re.escape(name),
        text,
        re.S | re.M,
    )
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
        """Assert the property (detach precedes release), not a literal call.

        Either free() or queue_free() is acceptable as long as the node is
        detached first; origin/main independently settled on the immediate
        free(), which is stronger here because build_world() runs synchronously.
        """
        body = func_body(read("scripts/main/main.gd"), "_clear_world")
        code = "\n".join(
            ln for ln in body.splitlines() if not ln.strip().startswith("#")
        )
        self.assertIn("remove_child(child)", code)
        m = re.search(r"child\.(queue_free|free)\(\)", code)
        self.assertIsNotNone(m, "the detached child must be released")
        self.assertLess(
            code.index("remove_child(child)"),
            m.start(),
            "remove_child must happen before the free so the node name is "
            "released before build_world() re-adds the replacements",
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

    def test_ui_suite_does_not_pin_the_old_clamped_value(self):
        """The UI runner must assert bounding, not the pre-fix DEFAULT_POOL.

        tests/ui/ui_test_runner.gd called set_max_live(999) and then asserted
        _max_live == DEFAULT_POOL. That is the behaviour the fix removed: it
        would silently re-break the ULTRA tier's 48-number request. This is a
        semantic conflict git merges cleanly, so it needs a guard.
        """
        txt = read("tests/ui/ui_test_runner.gd")
        m = re.search(
            r'_check\(\s*"damage number pool bounded",\s*([^)]*?)\)', txt, re.S
        )
        self.assertIsNotNone(m, "the bounded-pool UI check is missing")
        assertion = m.group(1)
        self.assertIn(
            "MAX_POOL",
            assertion,
            "the bound is MAX_POOL; pinning DEFAULT_POOL re-asserts the old bug",
        )
        self.assertNotIn("DEFAULT_POOL", assertion)


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


class ProgressionFirstStackTests(unittest.TestCase):
    """The first stack of EVERY upgrade silently did nothing.

    _accumulate() guarded with `_modifiers.get(k, 0.0)` (which supplies a default)
    but then assigned from `_modifiers[k]` (which does not). On the first stack of
    any key that index hit a missing entry: Godot pushes an error and evaluates to
    null, float(null) == 0.0, so the accumulated value was discarded. apply_upgrade()
    still returned true, so the failure was silent -- +15% damage still read as base.

    Caught by tests/unit/test_progression.gd once the headless gate was restored.
    """

    def test_accumulate_seeds_the_slot_before_reading_it(self):
        body = func_body(read("scripts/player/progression_component.gd"), "_accumulate")
        self.assertIn("_modifiers.get(k, 0.0)", body)

    def test_accumulate_never_indexes_a_possibly_missing_key(self):
        body = func_body(read("scripts/player/progression_component.gd"), "_accumulate")
        self.assertNotIn(
            "float(_modifiers[k]) + v",
            body,
            "reading _modifiers[k] directly drops the first stack of every upgrade",
        )


class WavePlannerCountCapTests(unittest.TestCase):
    """wave_planner caps basic and fast with mini() but heavy grew unbounded, so
    planned_count reached 46 by wave 40 against a documented ceiling of 40."""

    def test_heavy_tier_is_capped(self):
        body = func_body(read("scripts/waves/wave_planner.gd"), "_counts_for_wave")
        self.assertRegex(
            body,
            r"heavy = mini\(",
            "heavy must be capped like basic/fast or planned_count exceeds the ceiling",
        )

    def test_planned_count_stays_within_ceiling(self):
        """Recompute the planner's own curve and assert the documented bound."""
        body = func_body(read("scripts/waves/wave_planner.gd"), "_counts_for_wave")
        m = re.search(r"heavy = mini\(1 \+ int\(floor\(extra / 2\.0\)\), (\d+)\)", body)
        self.assertIsNotNone(m, "could not read the heavy cap from the planner")
        heavy_cap = int(m.group(1))
        early = {1: (5, 0, 0), 2: (7, 0, 0), 3: (8, 1, 0), 4: (10, 2, 0), 5: (8, 2, 1)}
        worst = 0
        for w in range(1, 41):
            if w in early:
                b, f, h = early[w]
            else:
                extra = w - 5
                b, f, h = min(8 + extra, 18), min(2 + extra, 10), min(1 + extra // 2, heavy_cap)
            worst = max(worst, b + f + h)
        self.assertLessEqual(worst, 40, "max planned_count over waves 1..40 is %d" % worst)


class CriticalSystemZeroChanceTests(unittest.TestCase):
    """A build with no crit chance must never crit, however much pity accrued.

    CriticalSystem.roll added the pity bonus to the base chance unconditionally,
    so a weapon at 0% crit still landed crits once enough non-crits stacked up.
    Pity escalates an existing chance; it must not manufacture one.
    """

    def test_zero_base_and_bonus_short_circuits_before_pity(self):
        body = func_body(read("scripts/combat/critical_system.gd"), "roll")
        self.assertRegex(
            body,
            r"if base_chance \+ bonus <= 0\.0:",
            "roll() must short-circuit to no-crit when there is no chance to escalate",
        )
        guard = body.split("if base_chance + bonus <= 0.0:")[1]
        pity_at = body.find("pity_bonus :=")
        guard_at = body.find("if base_chance + bonus <= 0.0:")
        self.assertLess(
            guard_at, pity_at, "the zero-chance guard must precede the pity bonus"
        )
        self.assertIn(
            '"crit": false', guard, "the zero-chance path must report crit == false"
        )

    def test_zero_chance_still_advances_the_pity_counter(self):
        body = func_body(read("scripts/combat/critical_system.gd"), "roll")
        guard = body.split("if base_chance + bonus <= 0.0:")[1].split("var pity_bonus")[0]
        self.assertRegex(
            guard,
            r"maxi\(pity_stacks, 0\) \+ 1",
            "a non-crit must still increment pity even on the zero-chance path",
        )


class Node3DSuiteSchedulingTests(unittest.TestCase):
    """Node3D-based suites must run on a live frame with in-tree fixtures.

    Node3D.get_global_transform() fails to the identity transform outside the
    tree, so parentless dummies all report global_position == ORIGIN. Production
    code (AreaDamage, MeleeResolver) reads .global_position, so spatial
    assertions silently degenerate: every target lands on the blast centre and
    arc/range filtering stops filtering.
    """

    NODE_SUITES = (
        "test_model_visual.gd",
        "test_weapons.gd",
        "test_area_combat.gd",
        "test_character_visuals.gd",
    )

    def test_runner_separates_pure_from_node_suites(self):
        txt = read("tests/run_tests.gd")
        self.assertIn("const NODE_SUITES", txt, "runner must declare NODE_SUITES")
        unit_block = txt.split("const UNIT_SUITES")[1].split("]")[0]
        node_block = txt.split("const NODE_SUITES")[1].split("]")[0]
        for suite in self.NODE_SUITES:
            self.assertIn(suite, node_block, "%s must be a deferred node suite" % suite)
            self.assertNotIn(
                suite, unit_block, "%s must not run in the synchronous phase" % suite
            )

    def test_node_suites_run_in_the_deferred_phase(self):
        body = func_body(read("tests/run_tests.gd"), "_process")
        self.assertIn(
            "_run_suites(NODE_SUITES)",
            body,
            "NODE_SUITES must be executed from _process, not _initialize",
        )
        init = func_body(read("tests/run_tests.gd"), "_initialize")
        self.assertNotIn(
            "NODE_SUITES", init, "NODE_SUITES must not run during _initialize"
        )

    def test_every_registered_suite_exists_exactly_once(self):
        txt = read("tests/run_tests.gd")
        listed = re.findall(r'"res://(tests/unit/[^"]+)"', txt)
        self.assertEqual(
            len(listed), len(set(listed)), "a suite is registered more than once"
        )
        on_disk = {
            "tests/unit/%s" % p.name
            for p in (ROOT / "tests" / "unit").iterdir()
            if p.suffix == ".gd"
        }
        self.assertEqual(
            set(listed), on_disk, "registered suites and tests/unit/*.gd disagree"
        )

    def test_spatial_fixtures_are_attached_before_positioning(self):
        """Dummies must be added to the tree, then positioned via global_position."""
        for path in ("tests/unit/test_area_combat.gd", "tests/unit/test_weapons.gd"):
            txt = read(path)
            self.assertIn(
                "root.add_child(d)", txt, "%s must attach its Node3D dummies" % path
            )
            add_at = txt.find("root.add_child(d)")
            pos_at = txt.find("d.global_position =")
            self.assertLess(
                add_at, pos_at, "%s must attach before setting global_position" % path
            )


class CombatLogCapacityFloorTests(unittest.TestCase):
    """CombatLog._init clamps capacity up to 8; tests must honour that floor."""

    def test_capacity_floor_is_documented_and_enforced(self):
        body = func_body(read("scripts/combat/combat_log.gd"), "_init")
        self.assertRegex(body, r"maxi\(capacity, 8\)", "capacity floor of 8 expected")

    def test_suite_does_not_request_a_capacity_below_the_floor(self):
        txt = read("tests/unit/test_area_combat.gd")
        for requested in re.findall(r"CombatLog\.new\((\d+)\)", txt):
            self.assertGreaterEqual(
                int(requested),
                8,
                "CombatLog.new(%s) is silently raised to 8; the test would assert "
                "against a capacity the class never honours" % requested,
            )


class SaveIdListSanitationTests(unittest.TestCase):
    """A malformed entry must be dropped, not stringified — and must not wipe the list.

    _string_list used String(item) unconditionally. On a non-string element that
    both coerces silently where it can (4 -> "4", smuggling a corrupt content id
    that resolves to no weapon/skill) and, in Godot, raises on the conversion,
    aborting the typed function so the WHOLE list comes back empty. A single bad
    element in a save file therefore erased every equipped weapon.
    """

    def test_non_string_entries_are_skipped_not_coerced(self):
        body = func_body(read("scripts/save/save_schema.gd"), "_string_list")
        self.assertRegex(
            body,
            r"if not \(item is String or item is StringName\):",
            "_string_list must reject non-text entries before String(item)",
        )
        guard_at = body.find("item is String or item is StringName")
        cast_at = body.find("String(item)")
        self.assertLess(
            guard_at, cast_at, "the type guard must precede the String() conversion"
        )
        self.assertIn("continue", body, "rejected entries must be skipped")


class TestRunnerAnnotationCapTests(unittest.TestCase):
    """GitHub caps ::error annotations at 10 per step.

    Emitting one annotation per failure silently truncates the tail of a long
    list, which makes an unchanged suite look like it grew new failures every
    time earlier ones are fixed. The runner must emit a single aggregated
    annotation so the whole list is always visible.
    """

    def test_failures_are_reported_as_one_aggregated_annotation(self):
        body = func_body(read("tests/run_tests.gd"), "_process")
        self.assertIn(
            '"\\n".join(_failures)',
            body,
            "all failures must be aggregated into one annotation",
        )
        self.assertIn(
            "%0A", body, "newlines must be escaped as %0A inside a workflow command"
        )
        # The per-failure loop must print plainly, without its own ::error.
        loop = body.split("for f in _failures:")[1].split("if not _failures")[0]
        code = "\n".join(
            ln for ln in loop.splitlines() if not ln.strip().startswith("#")
        )
        self.assertNotIn(
            "::error",
            code,
            "the per-failure loop must not emit one annotation each (cap is 10)",
        )


class MeleeArcFixtureTests(unittest.TestCase):
    """Arc fixtures must not sit exactly on the boundary.

    (1.5, 0, -1.5) is exactly 45.0 deg off-axis against a 90 deg arc, so whether
    it counts as a hit is decided by float rounding inside angle_to() rather than
    by the behaviour under test.
    """

    def test_near_side_fixture_is_strictly_inside_the_arc(self):
        import math

        txt = read("tests/unit/test_weapons.gd")
        m = re.search(r"var near_side := _melee_dummy\(Vector3\(([-\d.]+), 0, ([-\d.]+)\)\)", txt)
        self.assertIsNotNone(m, "could not locate the near_side melee fixture")
        x, z = float(m.group(1)), float(m.group(2))
        angle = math.degrees(math.acos(-z / math.hypot(x, z)))
        self.assertLess(
            angle,
            44.0,
            "near_side sits at %.2f deg, too close to the 45 deg arc edge" % angle,
        )


class BossPhaseSignalTests(unittest.TestCase):
    """Cosmetics must never gate the boss phase transition.

    _apply_phase_visuals creates tweens, and create_tween() fails on a node that
    is not inside the tree. _advance_to called it between applying the phase stat
    bumps and emitting phase_advanced, so a cosmetic failure applied the bumps but
    never told anyone the phase changed — desyncing UI, audio and analytics from
    the boss's real phase.
    """

    def test_visuals_are_guarded_by_an_inside_tree_check(self):
        body = func_body(read("scripts/enemies/boss_controller.gd"), "_apply_phase_visuals")
        self.assertRegex(
            body,
            r"if _host == null or not _host\.is_inside_tree\(\):",
            "_apply_phase_visuals must bail out when the host is not in the tree",
        )

    def test_phase_advanced_is_emitted_after_the_visual_call(self):
        body = func_body(read("scripts/enemies/boss_controller.gd"), "_advance_to")
        visuals_at = body.find("_apply_phase_visuals")
        emit_at = body.find("phase_advanced.emit")
        self.assertNotEqual(visuals_at, -1)
        self.assertNotEqual(emit_at, -1)
        self.assertLess(visuals_at, emit_at)
        self.assertIn(
            "if _host.is_inside_tree():",
            body,
            "the visual call inside _advance_to must itself be tree-guarded",
        )


class PackedSceneOwnerTests(unittest.TestCase):
    """PackedScene.pack() only serializes children whose owner is the pack root.

    The spawn-manager fixture packed an EnemyBase with a HealthComponent and a
    state machine but never set their owner, so the scene held a bare EnemyBase.
    Spawned enemies had no HealthComponent, apply_damage was rejected with
    no_health_component, nothing ever died, and every defeat/clear assertion in
    the stage failed for a reason unrelated to SpawnManager.
    """

    def test_fixture_children_are_owned_before_packing(self):
        body = func_body(read("tests/run_tests.gd"), "_pack_test_enemy_scene")
        owner_at = body.find("hp.owner = proto")
        machine_at = body.find("machine.owner = proto")
        pack_at = body.find("ps.pack(proto)")
        self.assertNotEqual(owner_at, -1, "HealthComponent must be owned by the root")
        self.assertNotEqual(machine_at, -1, "state machine must be owned by the root")
        self.assertLess(owner_at, pack_at, "owners must be set before pack()")
        self.assertLess(machine_at, pack_at, "owners must be set before pack()")


class EncounterSteppingTests(unittest.TestCase):
    """Manual physics stepping must actually move the body.

    move_and_slide() integrates against the engine physics tick, not the dt the
    test passes, and these fixtures run with set_physics_process(false) and no
    real physics frames -- so bodies stayed put and any distance-closing
    assertion observed a stationary enemy.
    """

    def test_step_enemy_integrates_velocity_with_the_test_delta(self):
        body = func_body(read("tests/run_tests.gd"), "_step_enemy")
        self.assertIn("enemy.velocity.x", body)
        self.assertIn("* dt", body, "position must advance using the test's dt")

    def test_a_condition_driven_stepping_helper_exists(self):
        txt = read("tests/run_tests.gd")
        self.assertIn(
            "func _step_enemy_until(",
            txt,
            "fixed frame budgets are fragile; a predicate-driven helper is required",
        )


class HealthResetAtomicityTests(unittest.TestCase):
    """HealthComponent.reset() must not publish an intermediate health state.

    reset() called set_max_health() first, which clamps the OLD current_health
    against the NEW maximum and emits that pairing before current_health is
    raised. Resetting a fresh 100 hp component to a 600 hp boss therefore
    published health_changed(100, 600) -- a 16% health fraction -- and
    BossController, which only ever advances phases upward, read it as "below the
    33% Enrage threshold" and enraged the boss before the fight began, with the
    phase damage/speed multipliers already applied.
    """

    def test_reset_assigns_both_fields_before_emitting(self):
        body = func_body(read("scripts/player/health_component.gd"), "reset")
        code = "\n".join(
            ln for ln in body.splitlines() if not ln.strip().startswith("#")
        )
        self.assertNotIn(
            "set_max_health(",
            code,
            "reset() must not route through set_max_health(); it emits a "
            "clamped intermediate state",
        )
        max_at = body.find("max_health = maxf(max_hp")
        cur_at = body.find("current_health = max_health")
        emit_at = body.find("health_changed.emit")
        for name, pos in (("max assignment", max_at), ("current assignment", cur_at)):
            self.assertNotEqual(pos, -1, "reset() must set %s directly" % name)
            self.assertLess(pos, emit_at, "%s must precede the emit" % name)

    def test_reset_still_emits_exactly_one_change(self):
        body = func_body(read("scripts/player/health_component.gd"), "reset")
        self.assertEqual(
            body.count("health_changed.emit"),
            1,
            "reset() must emit exactly one health_changed",
        )


class BossPhaseGatingTests(unittest.TestCase):
    """Phase advancement belongs to the fight, not to spawn-time setup."""

    def test_health_traffic_before_begin_fight_is_ignored(self):
        body = func_body(read("scripts/enemies/boss_controller.gd"), "_on_health_changed")
        self.assertIn(
            "if not _announced_intro:",
            body,
            "pre-fight health changes must not trigger a phase transition",
        )
        gate_at = body.find("if not _announced_intro:")
        advance_at = body.find("_advance_to(")
        self.assertLess(gate_at, advance_at, "the gate must precede _advance_to")

    def test_phase_advancement_remains_one_way(self):
        body = func_body(read("scripts/enemies/boss_controller.gd"), "_on_health_changed")
        self.assertIn(
            "if target > _phase:",
            body,
            "phases must only ever advance, never regress on healing",
        )
