# Architecture — Typed Component Model

This describes the architecture after the duck-typing overhaul
(docs/REFACTOR_PLAN.md). It is the reference for how new code should be
written; `tool/check_typed_arch.py` enforces the rules that can be checked
mechanically.

## The one rule

**Every component reference is typed, every call is direct.**

```gdscript
# YES — resolve once, as the concrete type, call directly
var _health: HealthComponent = get_node_or_null("HealthComponent") as HealthComponent
_health.take_damage(payload)

# NO — string dispatch (banned by the gate)
if node.has_method("take_damage"):
    node.call("take_damage", payload)
```

Why (this is the industry/community consensus — Godot forums, r/godot,
Liblast, Godot Paradise): `has_method()` + `.call("...")` strips every
compile-time guarantee the engine offers. There is no autocomplete, no
IDE navigation, no parser diagnostics — a renamed method fails silently at
runtime instead of loudly at load. Static typing prevents the large majority
of type-related runtime errors in GDScript.

## Component model

### Protocols (Godot has no interfaces)

An "interface" is an abstract base class others extend:

- **`Damageable`** (`scripts/combat/damageable.gd`, extends `CharacterBody3D`) —
  anything that can take a hit: `apply_damage(payload) -> DamageResult`,
  `is_alive() -> bool`. `Player` and `EnemyBase` extend it; every combat seam
  (melee/ranged resolvers, projectiles, area damage, skills) accepts
  `Damageable` and calls directly.
- **`ValidatedConfig`** (`scripts/core/validated_config.gd`, extends `Resource`) —
  authored content configs with `validate() -> Array[String]`.
  `WaveConfig`, `EnemyConfig`, `WeaponConfig`, `UpgradeConfig`, `PickupConfig`,
  `ArenaConfig`, `AudioConfig`, `SkillConfig`, `StatusEffectConfig`,
  `BossPhaseConfig` extend it; ContentLoader registers any `ValidatedConfig`
  and runs its self-checks. Wrong-type resources are reported as hard
  authoring errors.

### Player (scripts/player/)

- Components are resolved **once** in `_resolve_components()` (called from
  `_ready()`), each with an `as` cast. A wrong script on a child node yields
  `null`, which the required-component check reports by name.
- **Required** (fail fast): HealthComponent, CharacterController,
  ProgressionComponent, TargetingComponent, DodgeController, StaminaComponent,
  ExperienceComponent, WeaponManager, StatusManager.
- **Optional** (nullable typed refs, guarded): SkillController, PlayerFeedback,
  PlayerAudio. (The legacy `AttackController`/`ComboChain` fallback was removed;
  `WeaponManager` is the single attack authority.)
- Public typed accessors are the cross-system API: `get_health_component()`,
  `get_weapon_manager()`, `get_skill_controller()`, `get_status_manager()`,
  `get_stamina_component()`, `get_experience_component()`.
- Children `_ready()` runs before the parent's, so components resolve their
  own siblings via `get_node_or_null`, never through the parent's accessors
  (see player_feedback.gd for the canonical comment).

### Enemies (scripts/enemies/)

- `EnemyBase extends Damageable` is the archetype root; `.tscn` archetypes
  carry the full child set (feedback/audio/status/navigator), while test-built
  enemies provide only HealthComponent + EnemyStateMachine (+ BossController
  for bosses) — those are the optional, nullable refs.
- `BossController` is a typed sibling node with the `summon_requested` signal;
  SpawnManager connects it **before** `begin_fight()` (immediate emits are not
  lost) and summons go through the authoritative SpawnLedger.
- Enemy states (`EnemyState` subclasses) receive the typed host and call it
  directly.

## Collision contract

`scripts/core/collision_layers.gd` (`CollisionLayers`) owns every 3D layer and mask
bit in the project. The bits themselves are authored as numbers in two `.tscn` files
(Godot scenes cannot reference GDScript constants), so the contract is closed by
`tests/python/test_regress_collision_contract.py`, which fails if:

- a script assigns a numeric `collision_layer` / `collision_mask` again,
- a scene's bits drift from the constants,
- an enemy archetype re-declares collision instead of inheriting `enemy_base.tscn`,
- one of the documented decisions flips (hero and enemies do not body-block; the
  camera queries geometry only; pickups are polled, not detected).

Two consequences worth knowing before you reach for a physics hitbox:

- **Combat hits are math, not collision.** `MeleeResolver` / `AreaDamage` /
  `CombatQuery` select victims by range + arc against a candidate list, and
  `Pickup` collects by radius. The physics bodies exist for *locomotion* only. That
  is deliberate (deterministic, headless-testable, no shape-authoring per weapon),
  and it is why `PlayerAttack` / `EnemyAttack` / `Pickup` are declared but
  unassigned: they are reserved so nothing else can take the bit while that is true.
- **Bodies block, peers steer.** Arena geometry is hard (`move_and_slide`), enemy
  crowding is soft (`EnemyPack` separation query, peers-only). Never move the
  boundary between the two without moving the pinned test with it.

## Timing contract (render tick vs physics tick)

Simulation is fixed 60 Hz (`physics/common/physics_ticks_per_second`); rendering is
not (120 Hz panels, and `PerformanceMonitor` steps `Engine.max_fps` down to 30 on a
device that is struggling). Two rules keep that mismatch from showing up as judder:

1. **Movement belongs in `_physics_process`.** Anything that integrates a body,
   a pickup or a hazard moves there, so `physics/common/physics_interpolation=true`
   can blend it for drawing. Gameplay reads (`global_position` inside
   `_physics_process`) still see the exact tick value — interpolation is visual
   only, so determinism is untouched.
2. **A node written from `_process` must opt out.** The engine blends between
   physics-tick snapshots, so a node whose transform is assigned during idle would
   be smoothed twice and trail by a tick. `CameraRig`, its `Camera3D` and
   `DamageNumberLayer` set `physics_interpolation_mode =
   Node.PHYSICS_INTERPOLATION_MODE_OFF`, and the rig instead follows
   `get_global_transform_interpolated()` — the interpolated *target*, an
   un-interpolated camera. `tests/python/test_regress_physics_timing_and_ccd.py`
   fails on any new `_process` transform writer without the opt-out.

Teleports are the third case: pool re-entry (`Projectile.launch` / `pool_reset`,
`Pickup.drop` / `pool_reset`), enemy spawn and split burst, and the non-finite
position repairs in `CharacterController` / `PlayerLocomotion` all call
`reset_physics_interpolation()` **after** writing the position (before is a no-op
that still slides across the jump).

Hot-path rule that came out of the same pass: **never allocate a query object per
frame.** `PhysicsShapeQueryParameters3D` / `PhysicsRayQueryParameters3D` are read by
the server at call time, so `CameraCollisionSolver` and `Projectile` build theirs
once and mutate them; the camera additionally gates its spatial pass on a clock plus
an arm-displacement test, so a 120 Hz panel does not pay 120 spring-arm solves.

## Autoload policy

Autoloads (EventBus, SaveManager, AudioManager, ContentRegistry, GameRoot,
SceneRouter, RunAnalytics, TestHarness) are referenced **directly by name** in
GameRoot/main/UI code — they are project singletons.

Two deliberate, documented **autoload-optional seams** exist so the same
scripts run in-game and under the hermetic, autoload-free headless harness
(`tests/run_tests.gd` is autoload-free by design):

1. **Gameplay objects** resolve EventBus/AudioManager lazily through the tree
   (`get_node_or_null("/root/EventBus")`) — see `EnemyBase._eb()`,
   `enemy_audio._am()`, `character_visuals`, `spawn_manager`'s ContentRegistry
   fallback. When the node exists it IS the autoload; no `has_method` probe is
   needed.
2. **GameRoot null checks** (`if GameRoot != null`) guard the few gameplay
   paths that read the run while the harness is driving.

Everything else — UI panels, managers, GameRoot itself — uses the autoload
identifiers directly.

## Run state

`GameRoot.get_run() -> RunState` is **typed**. All consumers (HUD, minimap,
music, meta, upgrades, summary, wave manager, arena) read `run.score`,
`run.arena_id`, `run.selected_upgrades`, … directly. The old
`run is Dictionary` / `"seed" in run` probing branches were deleted — a
Dictionary run can no longer be injected accidentally.

## UI

- **`UiCommands.action`** is a closed, typed command set
  (request_attack / request_dodge / request_weapon_switch / request_skill),
  dispatched directly on `Player`; unknown commands warn and return `false`.
  TouchControls and SkillBar go through it — input has exactly one path.
- Panels use their public intent API + named children; boss bar and minimap
  cast to `EnemyBase`/`BossController`/`Pickup`/`Arena` for their queries.
- `UiRoot` casts group members to their concrete types
  (`HitstopManager`, `PerformanceMonitor`).

## Runtime guards (what replaced the `_validated_*` theater)

The 168 `_validated_*` helpers (141 dead) are gone. The guards that were real
are **inlined at their use sites** (`clampf`/`is_finite`/null checks) and
authored content ranges are enforced by **`@export_range`** in the editor.
`tool/validate_guards.py` pins those real invariants; reintroducing
`func _validated_*` / `func _guarded_*` / `func _safe_emit` fails CI.

## Enforcement (the two gates)

Run both from the repo root; both must exit 0:

```bash
python3 tool/check_typed_arch.py   # architecture gate
python3 tool/validate_guards.py    # real-guard contract
```

`check_typed_arch.py` (every `class_name` in `scripts/` + the 8 autoloads checked):

1. Bans string dispatch: `.call("...")` with a literal first argument, and
   `has_method(` — except one allowlisted assertion in `test_harness.gd`
   whose job is to probe GameRoot's API surface so a deleted method fails
   the check loudly.
2. Verifies `as <T>` casts resolve to a declared `class_name` (catches typos
   like `as WeaponManger` that gdparse cannot).
3. Verifies `Class.member(...)` calls exist on the class or its project
   `extends` chain (a mini type-checker over the parsed sources).

Callable *references* are fine: `attack_buffer.tick(dt, player._try_attack)`,
`ObjectPool` create/reset Callables, `run_scorekeeper`'s stat provider,
`settings_panel` toggles, `ui_root`'s deferred `_layout`. The ban is on
**string** dispatch, not on Callables.

## Verification ladder (no Godot binary needed)

1. `gdparse` — syntax for every touched script.
2. `tool/check_typed_arch.py` — duck-typing ban + typed-ref resolution.
3. `tool/validate_guards.py` — real guards present, theater stays dead.
4. `python3 -m unittest discover tests/python` — source-contract regressions,
   including `test_regress_collision_contract.py` (bits/decisions) and
   `test_regress_physics_timing_and_ccd.py` (interpolation opt-outs, no per-frame
   query allocation, swept projectile steps, teleport resets).
5. CI (with Godot): `godot --headless --script res://tests/run_tests.gd` +
   `scripts/ui/run_ui_validation.sh`.
