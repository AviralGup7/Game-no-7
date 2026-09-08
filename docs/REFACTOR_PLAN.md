# Typed Architecture Overhaul — Working Plan

## Problem (verified numbers)
- `player.gd`: 87 `.call()` + 62 `has_method()` — all on components that ALREADY have `class_name`s
- `enemy_base.gd`: 30 + 30
- `game_root.gd`: 8 + 13
- Codebase total: 308 `.call()` / 297 `has_method()` / 139 `get_node_or_null` component lookups
- 168 `func _validated_*` definitions; **111 are dead** (never referenced), 57 are live guards
- `tool/validate_guards.py` + several python "regression" tests assert the theater exists

## Target architecture (informed by Godot community/industry practice)
1. **`Damageable` protocol** (`scripts/combat/damageable.gd`): `class_name Damageable extends CharacterBody3D`
   with virtual `apply_damage(payload) -> DamageResult` / `is_alive() -> bool`.
   `Player` and `EnemyBase` extend it; combat seams use `is Damageable` + direct calls.
   (Godot has no interfaces; abstract base class is the documented idiom.)
2. **Typed component references**: `var _health: HealthComponent = get_node_or_null("HealthComponent") as HealthComponent`
   resolved once in `_ready()` (no `@onready` — subclass test doubles override `_ready`).
3. **Required vs optional, fail fast**:
   - Player REQUIRED: HealthComponent, CharacterController, ProgressionComponent, TargetingComponent,
     DodgeController, StaminaComponent, ExperienceComponent, WeaponManager, StatusManager.
   - Player OPTIONAL: SkillController, PlayerFeedback, PlayerAudio, AttackController (legacy fallback).
   - EnemyBase REQUIRED: HealthComponent, EnemyStateMachine (all production + test paths provide them).
   - EnemyBase OPTIONAL: EnemyFeedback, EnemyAudio, StatusManager, NavigationAgent3D (tests omit them).
   - Failure = `push_error` + `assert` (debug fail-fast) + disable processing (release degrades loudly, once).
4. **GameRoot** holds `_active_player: Player`; typed getters on Player
   (`get_weapon_manager() -> WeaponManager` etc.).
5. **UI**: `GameRoot`/autoload guards dropped (autoloads are compile-time singletons in-project);
   `UiCommands.action` generic `callv` replaced by a typed, closed command dispatch.
6. **Theater removal**: delete the 111 dead `_validated_*`; keep the 57 live ones (real guards);
   inline meaningful guards where the dead helper claimed one; rewrite `tool/validate_guards.py`
   to enforce the NEW invariants; update python regression tests that assert theater strings.

## Compatibility contract (must not break; tests cannot be run locally — no Godot binary available)
- `player.tscn` node names are the component contract (keep names).
- test_player.gd touches privates: `_attack_buffer`, `_health_now`, `_gameplay_time`, `_locomotion`,
  `_try_attack`, `_cancel_combat`, `_on_died` — keep exact names/behavior.
- Tests construct bare `EnemyBase.new()` + HealthComponent + EnemyStateMachine children (feedback/audio/status absent).
- Test doubles implementing apply_damage/is_alive must be updated to `extends Damageable`:
  tests/run_tests.gd `_FakeTarget`, tests/integration/test_player.gd `Target`,
  tests/unit/test_area_combat.gd + test_weapons.gd inner classes.
- `tests/ui/ui_player_double.gd` becomes `extends Player` building required children + `super._ready()`.
- `soak/stress/verify_flow` use real scenes via `.call("initialize"...)` on Node vars — unaffected.

## Phases
- [x] A. Recon + inventory (this doc)
- [x] B. `Damageable` + Player + player satellites + EnemyBase + striker + combat seams
- [x] C. GameRoot + main + UI + systems (pickup/wave/meta/upgrade/skill/status/spawn/boss/music)
- [x] D. `_validated_*` purge (168 removed — the "57 live" turned out to be 27 real callers,
      141+ dead; real guards inlined) + tool/validate_guards.py rewrite + python regression
      test updates (5 theater files deleted, ~130 theater assertions stripped/rewritten)
- [x] E. docs/ARCHITECTURE.md (industry comparison) + CHANGELOG
- [x] F. Static verification: gdparse all scripts+tests, tool/check_typed_arch.py clean,
       tool/validate_guards.py exit 0, 353 python tests green, gdlint clean on changed files.

## Outcome (measured, post-refactor)
- `scripts/` duck typing: 308 `.call()` → 0 string dispatch; 297 `has_method` → 1 sanctioned
  assertion (test_harness API probe). Callable references remain by design (they are typed).
- `tool/check_typed_arch.py` verifies 133 project classes + 8 autoloads: no string dispatch,
  `as T` casts resolve, `Class.member()` calls exist on the extends chain.

## Verification without Godot
- `gdparse` (gdtoolkit 4.5) syntax-validates every touched .gd
- `tool/check_typed_arch.py` (new): no `.call("str")`/`has_method(` in scripts/, and a mini
  type-checker: member vars typed with in-project classes → every `ref.method(...)` exists
  on that class (incl. base classes), every `.signal_name.connect` exists.
- `python3 -m unittest discover tests/python` + validate_resources.py
