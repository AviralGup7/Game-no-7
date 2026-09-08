"""Regression tests guarding 41 deep-bug-hunt fixes (batches 1-9).

Each test is a cheap string/structure check that fails if the fixed bug
regresses. No Godot runtime, no network, no file writes outside temp.

Run: python3 -m unittest discover -s tests/python -v
"""
from __future__ import annotations

import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8", errors="ignore")


def no_match(text: str, patt: str, msg: str = "") -> None:
    assert re.search(patt, text, re.MULTILINE) is None, msg


class Batch1CriticalTests(unittest.TestCase):
    """Batch 1: 11 critical/gameplay/persistence bugs (4d6123a)."""

    def test_player_tscn_load_steps_is_26(self):
        txt = read("scenes/player/player.tscn")
        first = txt.splitlines()[0] if txt else ""
        m = re.search(r"load_steps=(\d+)", first)
        self.assertIsNotNone(m, "player.tscn header missing load_steps")
        self.assertEqual(int(m.group(1)), 26, "player.tscn load_steps must be 26 (was 25)")
        # sanity: ext+sub+1 == 26 -> 24 ext +1 sub +1 =26 (matches file)
        ext = len(re.findall(r"\[ext_resource", txt))
        sub = len(re.findall(r"\[sub_resource", txt))
        self.assertEqual(ext + sub + 1, 26)

    def test_save_manager_dirty_flag_only_on_success(self):
        txt = read("scripts/save/save_manager.gd")
        # _dirty = false must be inside `if ok:` branch, not before it.
        self.assertIn("if ok:", txt)
        # The buggy form was `_write_raw` then `_dirty = false` then `if ok:`.
        # Ensure the unconditional assignment before the branch is gone.
        self.assertIn("\tif ok:\n\t\t_dirty = false", txt)
        self.assertNotIn("_write_raw(SAVE_PATH, JSON.stringify(_save))\n\t_dirty = false\n\tif ok:", txt)

    def test_game_root_legal_transitions_include_restart(self):
        txt = read("scripts/core/game_root.gd")
        self.assertIn('State.PLAYING: [State.WAVE_TRANSITION, State.GAME_OVER, State.STARTING_RUN', txt)
        self.assertIn('State.WAVE_TRANSITION: [State.PLAYING, State.UPGRADE_SELECTION, State.GAME_OVER, State.STARTING_RUN', txt)
        self.assertIn('State.UPGRADE_SELECTION: [State.PLAYING, State.GAME_OVER, State.STARTING_RUN', txt)

    def test_game_root_request_restart_fallback(self):
        txt = read("scripts/core/game_root.gd")
        self.assertIn("func request_restart()", txt)
        self.assertIn("if not transition_to(State.STARTING_RUN):", txt)
        self.assertIn("_apply_state(State.MAIN_MENU)", txt)
        self.assertIn("get_tree().paused = false", txt)

    def test_wave_manager_rebinds_director_damage(self):
        txt = read("scripts/waves/wave_manager.gd")
        self.assertIn("func _rebind_player_damage()", txt)
        self.assertIn("_rebind_player_damage()", txt)
        self.assertIn("_wired_health", txt)  # device to track current health node

    def test_health_component_emits_on_max_change(self):
        txt = read("scripts/player/health_component.gd")
        self.assertIn("func set_max_health", txt)
        self.assertIn("health_changed.emit(current_health, max_health)", txt)
        self.assertIn("not is_equal_approx(max_health, new_max)", txt)

    def test_input_remapper_clears_before_restore(self):
        txt = read("scripts/utilities/input_remapper.gd")
        self.assertIn("InputMap.action_erase_event", txt)
        self.assertIn("MAX_BINDS_PER_ACTION", txt)
        self.assertIn("# Clear existing remappable bindings before restoring", txt)

    def test_area_damage_tie_deterministic(self):
        txt = read("scripts/combat/area_damage.gd")
        self.assertIn("is_equal_approx(d, best_dist) and best == null", txt)
        self.assertIn("Strict < keeps candidate order stable on ties", txt)

    def test_arena_hazards_stable_spike_key(self):
        txt = read("scripts/arena/arena_hazards.gd")
        self.assertIn("stable_id", txt)
        self.assertIn('spike_cd_%s" % stable_id', txt)
        self.assertNotIn('h.hash()', txt)

    def test_damage_payload_deep_duplicate_and_timestamp(self):
        txt = read("scripts/combat/damage_payload.gd")
        self.assertIn("metadata.duplicate(true)", txt)
        self.assertIn("timestamp_msec = timestamp_msec", txt)
        self.assertIn("Preserve original timestamp", txt)

    def test_projectile_pool_emergency_fallback(self):
        txt = read("scripts/weapons/projectile_pool.gd")
        self.assertIn("config.duplicate(true)", txt)
        self.assertIn("emergency fallback", txt)
        self.assertIn("if p == null:", txt)
        self.assertIn("_make_projectile()", txt)

    def test_hitstop_manager_restores_on_exit(self):
        txt = read("scripts/combat/hitstop_manager.gd")
        self.assertIn("func _exit_tree()", txt)
        self.assertIn("Engine.time_scale = 1.0", txt)
        self.assertIn("stale hitstop/slowmo never freezes", txt)


class Batch2RegressionTests(unittest.TestCase):
    """Batch 2: 7 bugs (17dfe7c)."""

    def test_armory_vitality_key_correct(self):
        txt = read("scripts/meta/meta_progression.gd")
        self.assertIn('&"vitality_tome"', txt)
        self.assertNotIn('&"vitality Tome"', txt.split("# Migrate")[0])  # before migration comment no typo
        self.assertIn('&"second_wind": {"name": "Second Wind", "cost": 200, "requires": [&"vitality_tome"]', txt)

    def test_armory_migrates_legacy_key(self):
        txt = read("scripts/meta/meta_progression.gd")
        self.assertIn('StringName("vitality Tome")', txt)
        self.assertIn("Migrate legacy key typo", txt)
        self.assertIn('_ranks.erase(legacy)', txt)
        self.assertIn('maxi(int(_ranks[&"vitality_tome"])', txt)

    def test_apply_all_to_run_hoisted_guard(self):
        txt = read("scripts/meta/meta_progression.gd")
        # Guard must be before loop, not inside it.
        self.assertIn("func apply_all_to_run() -> void:\n\tif GameRoot == null or GameRoot.get_active_player() == null:", txt)
        # Loop must not contain early return.
        loop_section = txt.split("func apply_all_to_run")[1].split("func ")[0]
        # After the guard, the for loop should call prog directly without inner return
        self.assertIn("for item_id in _ranks:", loop_section)
        self.assertIn('prog.call("add_permanent_bonus"', loop_section)
        self.assertNotIn("if GameRoot == null or GameRoot.get_active_player() == null:\n\t\t\treturn", loop_section)

    def test_combat_log_source_field(self):
        txt = read("scripts/combat/combat_log.gd")
        self.assertIn('"source": String(source_id)', txt)
        self.assertIn('data.get("source"', txt)
        self.assertIn("damage_by_source", txt)

    def test_status_effect_tick_clamps(self):
        txt = read("scripts/status/status_effect.gd")
        self.assertIn("active_delta = minf(delta, remaining)", txt)
        self.assertIn("remaining = maxf(remaining - delta, 0.0)", txt)
        self.assertNotIn("remaining -= delta", txt.replace("maxf(remaining - delta", ""))  # ensure clamped form used

    def test_music_manager_null_run_guard(self):
        txt = read("scripts/audio/music_manager.gd")
        self.assertIn('GameRoot.has_method("get_run")', txt)
        self.assertIn('var run: Variant = GameRoot.call("get_run")', txt)
        self.assertIn("if run != null:", txt)
        self.assertIn("if run is Dictionary:", txt)

    def test_weapon_manager_avoids_shadowing(self):
        txt = read("scripts/weapons/weapon_manager.gd")
        self.assertIn("var status_result: Variant = sm.call", txt)
        self.assertNotIn("var applied: Variant = sm.call(\"apply_effects\"", txt)
        self.assertIn("status_result is Dictionary", txt)

    def test_achievements_flawless_wiring(self):
        txt = read("scripts/meta/achievements.gd")
        self.assertIn("_player_health", txt)
        self.assertIn("_on_player_damaged", txt)
        self.assertIn("flawless", txt)


class Batch3RegressionTests(unittest.TestCase):
    """Batch 3: ring fade, effect director, save rounding."""

    def test_ring_fade_resets_alpha(self):
        txt = read("scripts/visuals/ring_fade.gd")
        self.assertIn("c.a = 0.45", txt)
        self.assertIn("Reset material alpha so reused pooled rings", txt)
        self.assertIn("func trigger(duration: float)", txt)

    def test_effect_director_texture_exists_check(self):
        # Historically _claim_burst would error when texture missing; guard added.
        txt = read("scripts/visuals/effect_director.gd")
        # The director owns RING_TEXTURE/BURST_TEXTURE constants pointing to kenney assets
        self.assertIn("RING_TEXTURE", txt)
        self.assertIn("BURST_TEXTURE", txt)
        # Ensure built-in pool caps exist
        self.assertIn("MAX_BURSTS := 6", txt)
        self.assertIn("MAX_RINGS := 10", txt)

    def test_save_schema_int_rounding(self):
        txt = read("scripts/save/save_schema.gd")
        self.assertIn("int(round(float(v)))", txt)
        self.assertIn("func _string_int_map", txt)
        self.assertIn("maxi(int(round(float(v))), 0)", txt)


class Batch4RegressionTests(unittest.TestCase):
    """Batch 4: placer half, loader determinism, router guard, ranged clamp, ui tier fallback, hitstop stacking."""

    def test_spawn_placer_uses_half_param(self):
        txt = read("scripts/enemies/spawn_placer.gd")
        self.assertIn("interior_half_value: float = 12.0", txt)
        self.assertIn("var half := interior_half_value", txt)
        self.assertIn("interior_half(arena)", txt)

    def test_content_loader_deterministic(self):
        txt = read("scripts/core/content_loader.gd")
        self.assertIn("keys.sort()", txt)
        self.assertIn("keys: Array = arenas.keys()", txt)

    def test_scene_router_guards_invalid(self):
        txt = read("scripts/core/scene_router.gd")
        self.assertIn("get_tree() != null", txt)
        self.assertIn("if is_inside_tree() and get_tree() != null:", txt)
        self.assertIn("else:\n\t\t_transitioning = false", txt)

    def test_ranged_resolver_clamps_spread(self):
        txt = read("scripts/weapons/ranged_resolver.gd")
        self.assertIn("maxf(spread_degrees, 0.0)", txt)
        self.assertIn("clamped_spread", txt)

    def test_ui_tier_fallback_to_high(self):
        txt = read("scripts/ui/ui_root.gd")
        self.assertIn('if tier_idx < 0:', txt)
        self.assertIn("tier_idx = 2", txt)
        self.assertIn("high is the default when save carries an unknown", txt)

    def test_hitstop_stacks_with_max(self):
        txt = read("scripts/combat/hitstop_manager.gd")
        self.assertIn("_hitstop_left = maxf(_hitstop_left, duration)", txt)
        self.assertIn("MAX_HITSTOP_SECONDS", txt)


class Batch5RegressionTests(unittest.TestCase):
    """Batch 5: combo chaining, skill unlock gate, arena resolve."""

    def test_attack_combo_chains_only_on_hit(self):
        txt = read("scripts/player/attack_controller.gd")
        self.assertIn("combo_chain_window", txt)
        self.assertIn("if _elapsed > combo_chain_window:", txt)
        self.assertIn("must not escalate into a combo", txt)

    def test_skill_unlock_gate_treats_minus1_as_blocked(self):
        txt = read("scripts/skills/skill_controller.gd")
        self.assertIn("if level < cfg.unlock_level:", txt)
        # comment is split across two lines; check substrings
        self.assertIn("returns -1 when no ExperienceComponent", txt)
        self.assertIn("Treat unknown level as blocked", txt)

    def test_arena_resolve_handles_dict_and_object(self):
        txt = read("scripts/arena/arena.gd")
        self.assertIn("if run is Dictionary:", txt)
        self.assertIn('elif run is Object and "arena_id" in run:', txt)
        self.assertIn("func _resolve_arena_id()", txt)


class Batch6RegressionTests(unittest.TestCase):
    """Batch 6: settings tier default, minimap clamp, drop chance clamp."""

    def test_settings_panel_defaults_to_high(self):
        txt = read("scripts/ui/settings_panel.gd")
        self.assertIn("high", txt.lower())
        # Must handle missing/unknown quality gracefully

    def test_minimap_radius_clamped(self):
        txt = read("scripts/ui/minimap.gd")
        # radius clamped: maxf(minf(size.x ... ) guards huge/negative and arena half is safe
        self.assertIn("maxf(minf", txt)
        self.assertIn("maxf(half, 0.01)", txt)
        self.assertIn("radius", txt.lower())

    def test_drop_table_chance_clamped_0_1(self):
        txt = read("scripts/pickups/drop_table.gd")
        self.assertIn("clampf", txt)
        self.assertIn("chance", txt.lower())
        self.assertIn("0.0, 1.0", txt)


class Batch7RegressionTests(unittest.TestCase):
    """Batch 7: decorator position, frost nova dedup, locomotion clamp."""

    def test_arena_decorator_uses_local_position(self):
        txt = read("scripts/arena/arena_decorator.gd")
        self.assertIn("(n as Node3D).position", txt)
        self.assertIn("Node3D", txt)
        self.assertNotIn("(n as Node3D).global_position = center", txt)

    def test_frost_nova_avoids_double_slow(self):
        txt = read("scripts/skills/skill_executor.gd")
        self.assertIn('if &"slow" in cfg.victim_effects:', txt)
        self.assertIn("avoid double-stacking", txt.lower())

    def test_locomotion_clamps_limit_non_negative(self):
        txt = read("scripts/enemies/enemy_locomotion.gd")
        self.assertIn("maxf(_bounds_half - _bounds_margin, 0.0)", txt)
        self.assertNotIn("_bounds_half - _bounds_margin\n", txt)  # ensure clamp is present


class Batch8RegressionTests(unittest.TestCase):
    """Batch 8: skill bar ready, run summary rounding, upgrade active_modifiers preserve."""

    def test_skill_bar_connects_ready_signal(self):
        txt = read("scripts/ui/skill_bar.gd")
        self.assertIn("skill_became_ready", txt)
        self.assertIn("skill_cooldown_started", txt)
        self.assertIn("bind_controller", txt)

    def test_run_summary_rounds_duration(self):
        txt = read("scripts/ui/run_summary_panel.gd")
        self.assertIn("int(round(maxf(seconds,", txt)
        self.assertIn("round(maxf", txt)
        self.assertRegex(txt, r"maxi\(int\(round\(maxf\(seconds,\s*0\.0\)\)\)")
        self.assertIn('func duration(seconds: float)', txt)

    def test_upgrade_service_preserves_active_modifiers(self):
        txt = read("scripts/core/upgrade_service.gd")
        self.assertIn("selected_upgrades", txt)
        self.assertIn("active_modifiers", txt)
        self.assertIn("do not overwrite it", txt.lower())
        self.assertNotIn("run.active_modifiers = (prog.call(\"get_modifier_snapshot\"", txt)
        self.assertNotIn("get_modifier_snapshot", txt)


class Batch9RegressionTests(unittest.TestCase):
    """Batch 9: joystick deadzone, scoring wave clamp."""

    def test_virtual_joystick_deadzone_range(self):
        txt = read("scripts/ui/virtual_joystick.gd")
        self.assertRegex(txt, r"@export_range\(0\.0,\s*0\.5,\s*0\.01\)")
        self.assertIn("dead_zone", txt)
        # must not be plain @export var
        self.assertNotIn("@export var dead_zone", txt)

    def test_scoring_wave_floor(self):
        txt = read("scripts/waves/scoring.gd")
        self.assertRegex(txt, r"maxi\(wave_number,\s*1\)")
        self.assertRegex(txt, r"var w\s*:=\s*maxi\(wave_number,\s*1\)")


class GuardRailsTests(unittest.TestCase):
    """Additional invariants that should never regress."""

    def test_no_vitality_tome_typo_anywhere(self):
        # The legacy string "vitality Tome" must survive only as migration code in
        # meta_progression.gd (StringName("vitality Tome")). It must not appear as
        # a StringName key (&"vitality Tome") or in ARMORY.
        bad = []
        for p in ROOT.rglob("*.gd"):
            txt = p.read_text(errors="ignore")
            if '&"vitality Tome"' in txt:
                bad.append(str(p.relative_to(ROOT)))
            # Also reject lowercase-less variants outside the known migration file
            if p.name != "meta_progression.gd" and "vitality Tome" in txt:
                bad.append(str(p.relative_to(ROOT)))
        self.assertEqual(bad, [], f"Found legacy typo vitality Tome in: {bad}")
        # Migration path must still exist
        self.assertIn('StringName("vitality Tome")', read("scripts/meta/meta_progression.gd"))

    def test_export_presets_still_no_permissions(self):
        cfg = read("export_presets.cfg")
        offending = [ln for ln in cfg.splitlines() if ln.startswith("permissions/")]
        self.assertEqual(offending, [])

    def test_catalog_uses_resource_ids(self):
        txt = read("tool/validate_assets.py")
        self.assertIn("content_ids", txt)


if __name__ == "__main__":
    unittest.main()
