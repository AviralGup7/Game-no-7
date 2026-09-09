#!/usr/bin/env python3
"""Post-refactor guard contract for Last Stand: Arena.

This tool replaces the original theater-enforcer, which "validated" the
codebase by asserting that 139/139 `_validated_*` helpers existed — 141 of
which turned out to be dead code (168 defined, 27 called). That layer was
removed by the typed-architecture refactor (docs/REFACTOR_PLAN.md).

What this tool pins now:
  1. The guards that were REAL, inlined at their use sites (finite checks,
     clamps, null guards on the hot paths).
  2. @export_range editor enforcement on authored content configs.
  3. The retirement itself: `func _validated_*` / `func _guarded_*` /
     `func _safe_emit` must never come back.

Architecture checks (no `.call("...")` / `has_method` duck typing, typed
references resolve) live in tool/check_typed_arch.py.

Run from repo root:
    python3 tool/validate_guards.py
Exits non-zero if any real guard is missing or any theater returns.
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
        print(f"OK   {path}: {needle[:48]}")
    else:
        FAILED += 1
        print(f"FAIL {path}: missing {needle!r} {msg}")


def main() -> int:
    global FAILED, PASSED
    print("=== validate_guards: real-guard contract (post typed refactor) ===")

    print("-- inlined runtime guards (hot paths) --")
    checks = [
        # Combat math.
        ("scripts/combat/critical_system.gd", "is_finite(base_chance)"),
        ("scripts/utilities/weighted_table.gd", "is_finite(weight)"),
        ("scripts/utilities/weighted_table.gd", "clampf(weight"),
        # Player vitals.
        ("scripts/player/health_component.gd", "is_finite(float(payload.amount))"),
        ("scripts/player/health_component.gd", "clampf(current_health / max_health, 0.0, 1.0)"),
        ("scripts/player/health_component.gd", "clampf(_mitigate(amount, payload), 0.0, INF)"),
        ("scripts/player/experience_component.gd", "clampf(mult, 0.0, 10.0)"),
        ("scripts/player/stamina_component.gd", "clampf(_current / _max, 0.0, 1.0)"),
        ("scripts/player/progression_component.gd", "is_finite(base)"),
        # Enemies + waves.
        ("scripts/enemies/enemy_base.gd", "is_finite(resisted.x)"),
        ("scripts/waves/wave_planner.gd", "maxi(wave_number, 1)"),
        ("scripts/waves/difficulty_director.gd", "is_finite(_now)"),
        ("scripts/waves/scoring.gd", "maxi(int(round(raw)), 0)"),
        # Systems.
        ("scripts/pickups/pickup_manager.gd", "clampi(pool_size"),
        ("scripts/audio/audio_manager.gd", "clampf(volume_db, -80.0, 6.0)"),
        ("scripts/audio/audio_manager.gd", "clampf(pitch_scale, 0.1, 4.0)"),
        ("scripts/save/settings_data.gd", "_clamp01"),
        ("scripts/visuals/ring_fade.gd", "clampf(_elapsed / _duration, 0.0, 1.0)"),
        # Joystick -> locomotion -> physics/camera: the non-finite-proof chain that keeps
        # a bad analog sample from latching into a CharacterBody3D / Camera3D transform
        # (docs/MOVEMENT_STABILITY.md). Losing any one of these re-opens a device crash.
        ("scripts/ui/virtual_joystick.gd", "func _safe_radius() -> float:"),
        ("scripts/ui/virtual_joystick.gd", "return _value if _is_finite_v2(_value) else Vector2.ZERO"),
        ("scripts/ui/touch_controls.gd", "if not is_finite(value.x) or not is_finite(value.y):"),
        ("scripts/player/player_locomotion.gd", "if not is_finite(input_vector.x) or not is_finite(input_vector.y):"),
        ("scripts/player/character_controller.gd", "func _apply_velocity(vel: Vector3) -> void:"),
        ("scripts/player/character_controller.gd", "func _clean_velocity(vel: Vector3) -> Vector3:"),
        ("scripts/player/character_controller.gd", "if not is_finite(delta) or delta <= 0.0:"),
        ("scripts/player/character_controller.gd", "clampf(value, 0.0, 40.0)"),
        ("scripts/main/camera/camera_math.gd", "static func is_finite_transform(xform: Transform3D) -> bool:"),
        ("scripts/main/camera_rig.gd", "func _apply_follow_position(next_pos: Vector3, weight: float) -> void:"),
        ("scripts/main/camera_rig.gd", "if cam_origin.distance_squared_to(look_target) < 0.0004:"),
        ("scripts/main/camera/camera_shake_controller.gd", "if CameraMath.is_finite_transform(rolled):"),
        ("scripts/main/camera/camera_fov_controller.gd", "func _bounded(fov: float) -> float:"),
        # Arena hazards: the optional visual and the non-finite epicentre are the two
        # guards this subsystem exists to keep. They used to be pinned by requiring
        # `func _hazard_emission(h: Dictionary)` to exist, which pinned the *shape* of a
        # weak design (an untyped Dictionary record) rather than the safety property.
        # Arena world authoring (theme / landmark / obstacles). These four are the guards that
        # turn an authored mistake into a no-op instead of a broken world: a non-finite blocker
        # is skipped rather than poisoning the grid, a landmark that was refused (unknown kind)
        # says so instead of quietly building the default silhouette, and a footprint that was
        # never built must not block cells the player can walk into.
        ("scripts/arena/arena_nav_grid.gd", "if not (is_finite(p.x) and is_finite(p.z) and is_finite(s.x) and is_finite(s.z)):"),
        ("scripts/arena/arena_landmark.gd", 'push_error("ArenaLandmark: kind'),
        ("scripts/arena/arena.gd", "if landmark_box.has_area():"),
        # A device without the imported .hdr must still get the theme's procedural sky, not a
        # load error: ResourceLoader.exists is what keeps the panorama a soft reference.
        ("scripts/arena/arena.gd", "if not theme.panorama_path.is_empty() and ResourceLoader.exists(theme.panorama_path):"),
        ("scripts/arena/hazard_instance.gd", "if marker == null or not is_instance_valid(marker):"),
        ("scripts/arena/arena_hazards.gd", "if not instance.position_is_sane():"),
        ("scripts/arena/arena_hazards.gd", "if not is_finite(delta) or delta <= 0.0:"),
        ("scripts/utilities/radius_spatial_index.gd", "clampi(cell, 0, cells_x - 1)"),
        ("scripts/player/player_animation.gd", "if anim == null or not is_finite(anim.length) or anim.length <= 0.0:"),
    ]
    for path, needle in checks:
        check(path, needle)

    print("-- wave rules: authored mutators, one folded record, no Dictionary channels --")
    wave_checks = [
        ("scripts/enemies/spawn_manager.gd", "var _wave: WaveModifiers = WaveModifiers.neutral()"),
        ("scripts/enemies/spawn_manager.gd", "func set_wave_modifiers(mods: WaveModifiers) -> void"),
        ("scripts/enemies/spawn_manager.gd", "manager.apply_effect(_wave.status_effect, _wave.status_stacks, self)"),
        ("scripts/enemies/spawn_manager.gd", "_wave.elite_bonus"),
        ("scripts/enemies/spawn_manager.gd", "_wave.explode_chance"),
        ("scripts/waves/wave_manager.gd", "WaveMutators.fold_into(mods, _active_mutators)"),
        ("scripts/waves/wave_manager.gd", "apply_count_nudge(queue, _wave_mods.count_bonus)"),
        ("scripts/waves/wave_manager.gd", "run.set_wave_modifiers(mods)"),
        ("scripts/waves/difficulty_director.gd", "func next_wave_multipliers() -> WaveModifiers"),
        ("scripts/waves/wave_modifiers.gd", "func clamp_bounds() -> void"),
        ("scripts/waves/wave_modifiers.gd", "func fold_mutator(cfg: WaveMutatorConfig) -> void"),
        ("scripts/core/run_scorekeeper.gd", "_run.modifiers.score_mult"),
        ("scripts/core/run_scorekeeper.gd", "_run.modifiers.currency_mult"),
        ("scripts/weapons/weapon_manager.gd", "run.modifiers.player_damage_mult"),
        ("scripts/core/run_state.gd", "active_modifiers = modifiers.mutator_ids.duplicate()"),
        ("scripts/core/content_loader.gd", '_load_typed(&"res://data/mutators", &"mutators", tables, errors)'),
        ("scripts/core/content_loader.gd", "no WaveMutatorConfig resources"),
        ("scripts/core/content_registry.gd", "func get_wave_mutator(mutator_id: StringName) -> WaveMutatorConfig"),
    ]
    for path, needle in wave_checks:
        check(path, needle)
    # The absences are the same length as the presence list, because the shapes below are what
    # made five authored knobs silently unreadable; a "cleanup" that reintroduces one must fail
    # this file, not only the python suite (see tests/python/test_regress_wave_mutators.py).
    wave_absences = [
        ("scripts/enemies/spawn_manager.gd", "_wave_mods"),
        ("scripts/enemies/spawn_manager.gd", "var _difficulty"),
        ("scripts/enemies/spawn_manager.gd", '_difficulty.get('),
        ("scripts/waves/wave_manager.gd", "set_difficulty_scalars("),
        ("scripts/waves/wave_mutators.gd", "match mutator_id"),
        ("scripts/waves/wave_mutators.gd", "static func definition("),
        ("scripts/waves/wave_mutators.gd", '"hp_mult"'),
        ("scripts/waves/wave_mutator_config.gd", "func _definition"),
        ("scripts/core/run_scorekeeper.gd", '_wave_mods.get("'),
        ("scripts/weapons/weapon_manager.gd", '_wave_mods.get("'),
        ("scripts/meta/daily_challenge.gd", "WaveMutators.ALL"),
        ("scripts/save/save_schema.gd", "hp_mult"),
    ]
    for path, needle in wave_absences:
        txt = (ROOT / path).read_text(encoding="utf-8", errors="ignore")
        # Comments may name the banned shape on purpose (every file here explains what it replaced).
        body = "\n".join(l for l in txt.splitlines() if not l.lstrip().startswith("#"))
        if needle in body:
            FAILED += 1
            print(f"FAIL {path}: reintroduced {needle!r}")
        else:
            PASSED += 1
            print(f"OK   {path}: no {needle[:40]!r}")

    print("-- run definitions: modes, the prestige ladder, and the arena's own voice --")
    meta_checks = [
    	('scripts/meta/game_mode.gd', 'static func resolve(mode_id: StringName) -> GameModeConfig'),
    	('scripts/meta/game_mode.gd', 'static func definition(mode_id: StringName) -> GameModeConfig'),
    	('scripts/meta/game_mode.gd', 'push_error("GameMode: unknown mode id'),
    	('scripts/meta/game_mode.gd', 'cfg.plan_for_wave(w)'),
    	('scripts/meta/game_mode.gd', 'out = WavePlanner.extended_queue_for_wave(asked, seed)'),
    	('scripts/meta/game_mode.gd', 'DirAccess.open("res://data/game_modes")'),
    	('scripts/meta/game_mode_config.gd', 'func overrides_planner() -> bool'),
    	('scripts/meta/game_mode_config.gd', 'func plan_for_wave(wave_number: int) -> GameModeWavePlan'),
    	('scripts/meta/game_mode_wave_plan.gd', 'func has_beat() -> bool'),
    	('scripts/meta/prestige.gd', 'static func ladder() -> PrestigeLadderConfig'),
    	('scripts/meta/prestige.gd', 'static func clamp_rank(rank: int) -> int'),
    	('scripts/meta/prestige.gd', 'return &"unavailable"'),
    	('scripts/meta/prestige.gd', 'return cfg.tier_for_rank(rank) if cfg != null else null'),
    	('scripts/meta/prestige_ladder_config.gd', 'func tier_index_for_rank(rank: int) -> int'),
    	('scripts/meta/prestige_ladder_config.gd', 'func title_for(rank: int) -> String'),
    	('scripts/meta/challenge_tier.gd', 'func validate() -> Array[String]'),
    	('scripts/meta/narrator.gd', 'static func beat_text(mode_id: StringName, wave_number: int) -> String'),
    	('scripts/meta/narrator.gd', 'var beat := beat_text(mode_id, wave_number)'),
    	('scripts/meta/narrator.gd', 'static func _arena(arena_id: StringName) -> ArenaConfig'),
    	('scripts/arena/arena_config.gd', '@export_multiline var lore_intro: String = ""'),
    	('scripts/arena/arena_config.gd', 'func _lore_field(field: String) -> String'),
    	('scripts/core/content_loader.gd', '_load_typed(&"res://data/game_modes", &"game_modes", tables, errors)'),
    	('scripts/core/content_loader.gd', 'Missing prestige ladder'),
    	('scripts/core/content_loader.gd', 'no GameModeConfig resources'),
    	('scripts/core/content_loader.gd', 'which is not an authored weapon'),
    	('scripts/core/content_loader.gd', 'spawns unknown archetype'),
    	('scripts/core/content_registry.gd', 'func get_game_mode(mode_id: StringName) -> GameModeConfig'),
    	('scripts/core/content_registry.gd', 'func get_prestige_ladder() -> PrestigeLadderConfig'),
    	('scripts/meta/meta_progression.gd', 'Prestige.clamp_rank(_prestige_rank + 1)'),
    	('scripts/ui/run_setup_panel.gd', 'arena.lore_intro'),
    	('scripts/ui/armory_panel.gd', 'Prestige.armory_completion_required()'),
    	('scripts/ui/armory_panel.gd', 'Prestige.score_bonus_per_rank() * 100.0'),
    	('scripts/save/save_schema.gd', 'Prestige.clamp_rank('),
    ]
    for path, needle in meta_checks:
        check(path, needle)
    # And the shapes that made the mode layer untrustworthy are refused here too: a Dictionary
    # catalogue, an id-keyed fallback, a per-mode queue builder, a table the loader cannot see.
    meta_absences = [
    	('scripts/meta/game_mode.gd', 'const CATALOG'),
    	('scripts/meta/game_mode.gd', 'static func def('),
    	('scripts/meta/game_mode.gd', 'CHALLENGE_MUTATOR_POOL'),
    	('scripts/meta/game_mode.gd', 'static func boss_interval'),
    	('scripts/meta/game_mode.gd', 'static func narrator_id'),
    	('scripts/meta/game_mode.gd', 'static func _survival_queue'),
    	('scripts/meta/game_mode.gd', 'static func _defend_queue'),
    	('scripts/meta/game_mode.gd', 'match mode_id'),
    	('scripts/meta/game_mode.gd', '"score_mult":'),
    	('scripts/meta/prestige.gd', 'const TITLES'),
    	('scripts/meta/prestige.gd', 'const CHALLENGE_TIERS'),
    	('scripts/meta/prestige.gd', 'const MAX_PRESTIGE'),
    	('scripts/meta/prestige.gd', 'const PRESTIGE_COST_BASE'),
    	('scripts/meta/prestige.gd', '.get('),
    	('scripts/meta/narrator.gd', 'const ARENA_LORE'),
    	('scripts/meta/narrator.gd', 'const MODE_INTRO'),
    	('scripts/meta/narrator.gd', 'const CAMPAIGN_BEATS'),
    	('scripts/meta/narrator.gd', 'const ENEMY_BLURBS'),
    	('scripts/meta/narrator.gd', 'default_arena'),
    	('scripts/meta/narrator.gd', 'GameMode.MODE_'),
    	('scripts/meta/narrator.gd', 'match mode_id'),
    	('scripts/meta/game_mode_config.gd', 'func _definition'),
    	('scripts/meta/game_mode_config.gd', '"unlock_prestige"'),
    ]
    for path, needle in meta_absences:
        txt = (ROOT / path).read_text(encoding="utf-8", errors="ignore")
        body = "\n".join(l for l in txt.splitlines() if not l.lstrip().startswith("#"))
        if needle in body:
            FAILED += 1
            print(f"FAIL {path}: reintroduced {needle!r}")
        else:
            PASSED += 1
            print(f"OK   {path}: no {needle[:40]!r}")

    print("-- @export_range editor enforcement on content configs --")
    export_checks = [
        ("scripts/enemies/enemy_config.gd", "@export_range(0.0, 10000.0, 0.5) var max_health"),
        ("scripts/enemies/enemy_config.gd", "@export_range(0.05, 60.0, 0.05) var attack_cooldown"),
        ("scripts/weapons/weapon_config.gd", "@export_range(0.0, 10000.0, 0.5) var base_damage"),
        ("scripts/weapons/weapon_config.gd", "@export_range(0.0, 1.0, 0.01) var crit_chance"),
        ("scripts/waves/wave_config.gd", "@export_range(1, 60) var maximum_simultaneous_enemies"),
        ("scripts/waves/wave_spawn_entry.gd", "@export_range(0.0, 1.0, 0.01) var elite_chance"),
        ("scripts/skills/skill_config.gd", "@export_range(0.05, 300.0, 0.1) var cooldown"),
        ("scripts/status/status_effect_config.gd", "@export_range(0.0, 300.0, 0.05) var duration"),
        ("scripts/pickups/pickup_config.gd", "@export_range(0.0, 100.0, 0.1) var drop_weight"),
        ("scripts/audio/audio_config.gd", "@export_range(-80.0, 6.0, 0.1) var volume_db"),
        ("scripts/arena/arena_config.gd", "@export_range(0.0, 100.0, 0.1) var enemy_spawn_min_player_distance"),
        ("scripts/arena/hazard_config.gd", "@export_range(0.25, 12.0, 0.05) var radius"),
        ("scripts/arena/hazard_config.gd", "@export_range(0.0, 60.0, 0.05) var period"),
        ("scripts/arena/hazard_placement.gd", "@export_range(0.0, 1.0, 0.01) var phase_jitter"),
        # The authored world: fog past a readable density, a landmark scaled into a wall, an
        # obstacle flattened to a plane and a zero-energy sun are all inspector-visible mistakes
        # the ranges below make undraggable.
        ("scripts/arena/arena_theme_config.gd", "@export_range(0.0, 0.2, 0.001) var fog_density"),
        ("scripts/arena/arena_theme_config.gd", "@export_range(0.2, 3.0, 0.01) var brightness"),
        ("scripts/arena/arena_landmark_config.gd", "@export_range(0.25, 4.0, 0.05) var scale"),
        ("scripts/arena/arena_obstacle_placement.gd", "@export_range(0.05, 8.0, 0.05) var half_size_x"),
        # Wave mutators: every knob is a bounded export, so "elite bonus 40%" or a multiplier of
        # 0 is unauthorisable in the editor rather than clamped away after the fact.
        ("scripts/waves/wave_mutator_config.gd", "@export_range(0.05, 8.0, 0.05) var hp_mult"),
        ("scripts/waves/wave_mutator_config.gd", "@export_range(0.1, 8.0, 0.05) var score_mult"),
        ("scripts/waves/wave_mutator_config.gd", "@export_range(0.1, 8.0, 0.05) var currency_mult"),
        ("scripts/waves/wave_mutator_config.gd", "@export_range(0.1, 8.0, 0.05) var player_damage_mult"),
        ("scripts/waves/wave_mutator_config.gd", "@export_range(0.0, 0.5, 0.01) var elite_bonus"),
        ("scripts/waves/wave_mutator_config.gd", "@export_range(0.0, 1.0, 0.01) var explode_chance"),
        ("scripts/waves/wave_mutator_config.gd", "@export_range(0, 64) var roll_order"),
        ("scripts/waves/wave_mutator_config.gd", "@export_range(1, 1000) var min_wave"),
        # Run definitions: a mode's multipliers, a ladder's costs and a tier's wave cap are bounded
        # in the inspector, so the authored file cannot carry a value the code would have to clamp.
        ('scripts/meta/game_mode_config.gd', '@export_range(0.05, 10.0, 0.01) var score_mult'),
        ('scripts/meta/game_mode_config.gd', '@export_range(0.05, 10.0, 0.01) var currency_mult'),
        ('scripts/meta/game_mode_config.gd', '@export_range(0, 200, 1) var max_waves'),
        ('scripts/meta/game_mode_config.gd', '@export_range(0.0, 3600.0, 1.0) var target_seconds'),
        ('scripts/meta/game_mode_config.gd', '@export_range(0, 500, 1) var collect_target'),
        ('scripts/meta/game_mode_config.gd', '@export_range(0, 20, 1) var upgrade_every'),
        ('scripts/meta/game_mode_config.gd', '@export_range(-20, 20, 1) var planner_wave_offset'),
        ('scripts/meta/game_mode_config.gd', '@export_range(1, 200, 1) var planner_wave_floor'),
        ('scripts/meta/game_mode_config.gd', '@export_range(0, 20, 1) var every_n_waves'),
        ('scripts/meta/game_mode_wave_plan.gd', '@export_range(1, 200, 1) var wave_number'),
        ('scripts/meta/prestige_ladder_config.gd', '@export_range(1, 1000000, 1) var cost_base'),
        ('scripts/meta/prestige_ladder_config.gd', '@export_range(1, 40, 1) var max_rank'),
        ('scripts/meta/prestige_ladder_config.gd', '@export_range(0.0, 1.0, 0.001) var score_bonus_per_rank'),
        ('scripts/meta/prestige_ladder_config.gd', '@export_range(0.0, 1.0, 0.001) var currency_bonus_per_rank'),
        ('scripts/meta/prestige_ladder_config.gd', '@export_range(0.0, 1.0, 0.01) var armory_completion_required'),
        ('scripts/meta/challenge_tier.gd', '@export_range(0.05, 20.0, 0.01) var score_mult'),
        ('scripts/meta/challenge_tier.gd', '@export_range(0.05, 20.0, 0.01) var currency_mult'),
        ('scripts/meta/challenge_tier.gd', '@export_range(0, 12, 1) var mutator_count'),
        ('scripts/meta/challenge_tier.gd', '@export_range(1, 200, 1) var max_waves'),
        ('scripts/meta/prestige_unlock.gd', '@export_range(1, 40, 1) var unlock_rank'),
        ("scripts/enemies/boss_phase_config.gd", "@export_range(0.01, 1.0, 0.01) var threshold"),
        ("scripts/player/health_component.gd", "@export_range(1.0, 100000.0, 1.0) var max_health"),
    ]
    for path, needle in export_checks:
        check(path, needle)

    print("-- the theater stays dead --")
    theater = 0
    for gd in (ROOT / "scripts").rglob("*.gd"):
        txt = gd.read_text(encoding="utf-8", errors="ignore")
        for pattern in (r"^\s*func _validated_", r"^\s*func _guarded_", r"^\s*func _safe_emit"):
            if re.search(pattern, txt, re.M):
                print(f"FAIL {gd.relative_to(ROOT)}: theater function returned ({pattern})")
                FAILED += 1
                theater += 1
    if theater == 0:
        PASSED += 1
        print("OK   scripts/: no _validated_/_guarded_/_safe_emit functions")

    print(f"\nPassed {PASSED}, Failed {FAILED}")
    return 1 if FAILED else 0


if __name__ == "__main__":
    sys.exit(main())
