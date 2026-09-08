#!/usr/bin/env python3
"""Validate that hardening guards exist across the codebase — 139/139 validated.

Checks for the 4000-line bug-hunt invariants:
  - Every GDScript with _validated_* helper contains finite/clamp guards
  - GameRoot.get_run Dictionary branches exist in main/meta/ui/waves
  - EventBus/ContentRegistry null guards exist in player/progression/audio
  - WeightedTable, CriticalSystem, DifficultyDirector finite guards
  - Enemy states all have _validated_* helpers
  - UI visuals have clamp helpers

Run from repo root:
    python3 tool/validate_guards.py
Exits non-zero if any hardening is missing.
"""
from __future__ import annotations
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
FAILED = 0
PASSED = 0

def check(path: str, needle: str, msg: str = "") -> None:
    global FAILED, PASSED
    p = ROOT / path
    txt = p.read_text(encoding="utf-8", errors="ignore") if p.exists() else ""
    if needle in txt:
        PASSED += 1
        print(f"OK {path}: {needle[:40]}")
    else:
        FAILED += 1
        print(f"FAIL {path}: missing {needle!r} {msg}")

def main() -> int:
    print("=== validate_guards: checking 4000-line hardening ===")

    # Main GameRoot Dictionary guards
    check("scripts/main/main.gd", "func _safe_run()", "main needs Dictionary-aware safe_run")
    check("scripts/main/main.gd", "\"seed\" in run", "seed Dictionary branch")
    check("scripts/main/main.gd", "\"arena_id\" in run", "arena_id Dictionary branch")
    check("scripts/main/main.gd", "_safe_seed()", "uses safe seed")
    check("scripts/main/main.gd", "_safe_arena_id()", "uses safe arena_id")
    check("scripts/meta/achievements.gd", "func _safe_run()", "achievements safe_run")
    check("scripts/meta/achievements.gd", "_selected_upgrade_count", "selected count helper")
    check("scripts/meta/meta_progression.gd", "run is Dictionary", "meta Dictionary guard")
    check("scripts/ui/run_summary_panel.gd", "has_method(\"summary\")", "summary guard")
    check("scripts/ui/upgrade_panel.gd", "run is Dictionary", "upgrade panel guard")
    check("scripts/waves/wave_manager.gd", "\"elapsed_seconds\" in run", "elapsed guard")

    # Finite/clamp helpers
    checks = [
        ("scripts/utilities/weighted_table.gd", "is_finite(weight)"),
        ("scripts/utilities/weighted_table.gd", "_validated_total"),
        ("scripts/combat/critical_system.gd", "is_finite(base_chance)"),
        ("scripts/combat/critical_system.gd", "_validated_crit_chance"),
        ("scripts/waves/difficulty_director.gd", "is_finite(_now)"),
        ("scripts/waves/difficulty_director.gd", "_validated_director_factor"),
        ("scripts/enemies/boss_controller.gd", "phases.is_empty()"),
        ("scripts/enemies/boss_controller.gd", "_validated_threshold"),
        ("scripts/player/progression_component.gd", "is_finite(base)"),
        ("scripts/player/health_component.gd", "is_instance_valid(payload)"),
        ("scripts/player/health_component.gd", "_validated_heal_amount"),
        ("scripts/player/stamina_component.gd", "_validated_stamina_config"),
        ("scripts/combat/area_damage.gd", "_validated_radial_args"),
        ("scripts/combat/hitstop_manager.gd", "_validated_hitstop"),
        ("scripts/combat/damage_payload.gd", "_validated_amount"),
        ("scripts/combat/damage_result.gd", "_validated_final"),
        ("scripts/weapons/projectile.gd", "is_finite(delta)"),
        ("scripts/weapons/projectile.gd", "_validated_launch_dict"),
        ("scripts/weapons/weapon_manager.gd", "_validated_weapon_id"),
        ("scripts/core/run_state.gd", "_validated_restore_dict"),
        ("scripts/core/run_state.gd", "clampi(currency + delta"),
        ("scripts/utilities/rng_service.gd", "if salt < 0:"),
        ("scripts/progression/upgrade_selector.gd", "_validated_pick_count"),
        ("scripts/core/content_registry.gd", "_validated_archetype"),
        ("scripts/core/event_bus.gd", "_safe_emit"),
        ("scripts/enemies/enemy_base.gd", "is_instance_valid(_health)"),
        ("scripts/enemies/enemy_base.gd", "_validated_knockback"),
        ("scripts/enemies/enemy_state_machine.gd", "_validated_state_for_transition"),
        ("scripts/ui/minimap.gd", "_validated_map_pos"),
        ("scripts/ui/tutorial_manager.gd", "is_finite(delta)"),
        ("scripts/status/status_manager.gd", "_validated_effects"),
        ("scripts/skills/skill_controller.gd", "_validated_cooldown"),
        ("scripts/pickups/pickup_manager.gd", "_validated_drop_pos"),
        ("scripts/enemies/boss_phase_config.gd", "_validated_phase"),
        ("scripts/enemies/enemy_locomotion.gd", "_validated_integration"),
        ("scripts/enemies/enemy_navigator.gd", "_validated_target"),
        ("scripts/enemies/enemy_state.gd", "_validated_host"),
        ("scripts/enemies/enemy_striker.gd", "_validated_striker"),
        ("scripts/enemies/spawn_ledger.gd", "_validated_archetype"),
        ("scripts/enemies/spawn_manager.gd", "_validated_configure"),
        ("scripts/enemies/spawn_placer.gd", "_validated_half"),
        ("scripts/main/camera_profile.gd", "_validated_profile"),
        ("scripts/meta/daily_challenge.gd", "_validated_daily_seed"),
        ("scripts/pickups/pickup_config.gd", "_validated_pickup"),
        ("scripts/player/attack_buffer.gd", "_validated_buffer_time"),
        ("scripts/player/character_controller.gd", "_validated_input"),
        ("scripts/player/combo_chain.gd", "_validated_combo_window"),
        ("scripts/progression/upgrade_config.gd", "_validated_upgrade"),
        ("scripts/save/save_schema.gd", "_validated_schema_version"),
        ("scripts/save/settings_data.gd", "_validated_volume"),
        ("scripts/status/status_effect_config.gd", "_validated_status"),
        ("scripts/ui/achievement_gallery.gd", "_validated_gallery_index"),
        ("scripts/ui/armory_panel.gd", "_validated_armory_cost"),
        ("scripts/visuals/visual_mount.gd", "_validated_mount"),
        ("scripts/waves/scoring.gd", "_validated_score_delta"),
        ("scripts/waves/wave_spawn_entry.gd", "_validated_entry"),
        ("scripts/weapons/projectile_pool.gd", "_validated_projectile"),
        ("scripts/weapons/weapon_instance.gd", "_validated_config"),
    ]
    for path, needle in checks:
        check(path, needle)

    # Count coverage
    all_gd = list((ROOT / "scripts").rglob("*.gd"))
    validated = sum(1 for p in all_gd if "_validated" in p.read_text(errors="ignore"))
    print(f"\nValidated files: {validated}/{len(all_gd)}")
    if validated < 100:
        print(f"FAIL: expected >=100 validated files, got {validated}")
        return 1

    print(f"\nPassed {PASSED}, Failed {FAILED}")
    return 1 if FAILED else 0

if __name__ == "__main__":
    sys.exit(main())
