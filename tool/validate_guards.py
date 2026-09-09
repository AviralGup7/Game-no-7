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
        ("scripts/arena/arena_hazards.gd", "func _hazard_emission(h: Dictionary) -> StandardMaterial3D:"),
        ("scripts/player/player_animation.gd", "if anim == null or not is_finite(anim.length) or anim.length <= 0.0:"),
    ]
    for path, needle in checks:
        check(path, needle)

    print("-- @export_range editor enforcement on content configs --")
    export_checks = [
        ("scripts/enemies/enemy_config.gd", "@export_range(0.0, 10000.0, 0.5) var max_health"),
        ("scripts/enemies/enemy_config.gd", "@export_range(0.05, 60.0, 0.05) var attack_cooldown"),
        ("scripts/weapons/weapon_config.gd", "@export_range(0.0, 10000.0, 0.5) var base_damage"),
        ("scripts/weapons/weapon_config.gd", "@export_range(0.0, 1.0, 0.01) var crit_chance"),
        ("scripts/waves/wave_config.gd", "@export_range(1, 60) var maximum_simultaneous_enemies"),
        ("scripts/waves/wave_spawn_entry.gd", "@export_range(0.0, 1.0, 0.01) var elite_chance"),
        ("scripts/skills/skill_config.gd", "@export_range(0.05, 300.0, 0.1) var cooldown"),
        ("scripts/status/status_effect_config.gd", "@export_range(0.05, 300.0, 0.05) var duration"),
        ("scripts/pickups/pickup_config.gd", "@export_range(0.0, 100.0, 0.1) var drop_weight"),
        ("scripts/audio/audio_config.gd", "@export_range(-80.0, 6.0, 0.1) var volume_db"),
        ("scripts/arena/arena_config.gd", "@export_range(0.0, 100.0, 0.1) var enemy_spawn_min_player_distance"),
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
