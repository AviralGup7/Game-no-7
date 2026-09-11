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

## Determinism

Gameplay outcomes are reproducible from a per-run seed so they can be verified
headlessly and replayed:

- `RngService` owns salted per-stream generators — `STREAM_WAVES`, `STREAM_DROPS`,
  `STREAM_CRITS`, `STREAM_AI`, `STREAM_UPGRADES`, `STREAM_ARENA`, `STREAM_AUDIO`
  (plus `STREAM_COSMETIC`). No gameplay system may call global `randi()` directly
  (pinned by `test_integration_wave_boss.py`).
- Wave generation, upgrade selection, spawn order/placement and scoring are pure
  functions of `(run_seed, wave_number)`; boss RNG derives from the run seed.
- Combat is math, not physics (see above), so hit results are stable across frame
  rates and hardware.
- Only presentation may be non-deterministic; where a seed is convenient for
  reproduction it is still used.

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

## Arena hazards (the reference example of "content, not code")

`ArenaHazards` is the subsystem this project's one rule was most often broken against, so
it is documented in full and pinned from both sides. It models **two mechanics**, and
everything else about a hazard is authored data:

| Field on `HazardConfig` | Mechanic | Examples |
| --- | --- | --- |
| `pulse` + `trigger = periodic` | detonates on a period, with optional `telegraph` | fire vent |
| `pulse` + `trigger = proximity` | detonates when something steps on it, then re-arms on `fire_cooldown` | pressure plate |
| `field` | applies while a victim stands in it, throttled per victim by `victim_cooldown` | spike bed, healing ward, ichor pool |
| `field` + `orbit_radius_fraction` | the same field, travelling a circle around its authored position | ember mover |

Three structural decisions carry the rest:

1. **Authored data, typed all the way down.** Behaviour lives in
   `res://data/hazards/*.tres` (`HazardConfig extends ValidatedConfig`), placement in
   `ArenaConfig.hazard_layout` (`HazardPlacement`, with a `mirror` that expands one line
   into a symmetric set), and per-mode pressure in `res://data/hazard_modes/*.tres`. No
   arena id, no radius and no damage number appears in the hazard system's source —
   `tests/python/test_regress_hazard_subsystem.py` fails if one comes back. Per-placement
   *mutable* state never lives on a config (resources are shared between every placement
   of a kind); it lives in `HazardInstance`, a typed `RefCounted` record.
2. **Polled math, once per tick, shared by every hazard.** No Area3D volumes: combat,
   pickups and the minimap all read positions from the tree, and a physics-monitoring
   volume per disc costs more on a phone than the squared-distance test it replaces — and
   cannot be tested headless. What changed is *how often*: `_physics_process` now takes one
   victim snapshot (positions, team bits, per-body hit padding via
   `Damageable.get_hit_radius()`) lazily — only if a hazard actually wants victims this
   tick — and buckets it into `RadiusSpatialIndex`, a uniform grid whose buckets are two
   `PackedInt32Array`s (head per cell, next per element), so a rebuild is a fill, not an
   allocation. A grid rather than a quadtree because the contents move: rehashing is O(n)
   and a tree rebuild is O(n log n) with cells that churn every tick. Cell size follows
   the ~2×-largest-query-radius rule so a query visits a handful of buckets. The storage split is deliberate: `Array[Node3D]` for the gameplay references (typed arrays
   are for objects) and `Packed*Array` for the raw numeric buffers — flat contiguous ints
   for the linked lists, flat contiguous vectors for positions — because that is where
   GDScript keeps its cache locality and pays no per-element `Variant` overhead.

   Eleven hazards
   over forty enemies used to be ~460 distance tests *plus two fresh Arrays and a lambda
   filter* every 60 Hz tick; it is now one bucketing pass plus an O(nearby) visit per
   hazard, and a periodic vent scans nothing at all between its bursts.
3. **Game time, not wall time.** `HazardInstance` timers accumulate `delta` on the
   node's own `_game_time`. They previously compared `Time.get_ticks_msec()` against
   gameplay intervals, which meant a 1 s spike immunity could be spent during a hitstop
   that scales the world to 0.05x, and a vent's telegraph shimmer ran ahead of the burst
   it was warning about. Heal is *integrated* over the time a field actually covered, so
   changing a hazard's `scan_interval` changes its cost and not its total. See "Timing
   contract" above.

Optional visuals follow the same discipline: `HazardMarker` is built from the same radius
the gameplay uses (one number, so the disc and the hitbox cannot disagree), and the only
way gameplay reaches it is `HazardInstance.visual()`, which validates the reference before
returning it. Node metadata carries no gameplay state at all — the old per-victim
`set_meta("spike_cd_…")` cooldown keys were slow in the hot path and got serialized into
the scene.

**Known gap, deliberately not papered over.** `ContentLoader._register_resource()` runs
`validate()` only on resources that *are* a `ValidatedConfig`. `ArenaConfig` now is (an
authored hazard layout is worthless if nothing checks it), but `SkillConfig`,
`StatusEffectConfig`, `WeaponConfig`, `AudioConfig` and `BossPhaseConfig` still extend
`Resource`, so their `validate()` runs in the CI harness and not at load. Converting them
is one line each, and it cannot be done blind: `ContentRegistry` **halts startup** on a
validation error in a debug build, so each conversion needs one real (or CI) run proving
the shipped `.tres` files pass. `test_regress_hazard_subsystem.py` pins that list as a
set that may only shrink.

Coverage: `tests/unit/test_hazards.gd` (pure — validation, mirror expansion, layout parity
with the coordinates the deleted code hand-tuned, cooldown/burst arithmetic, grid vs brute
force), `tests/unit/test_hazards_live.gd` (in-tree fixtures driven tick by tick — who gets
hit, how often, on which clock, with the marker freed), and the python suite above.


## Status effects (the fold cache)

`StatusManager` is a per-entity component, and its answers are the most-queried numbers in
the game after position: `move_speed_factor()` and `is_stunned()` are read by the player *and*
by every enemy on every physics tick, `incoming_damage_factor()` and `absorb_direct()` on
every hit. All five of them — speed, outgoing damage, incoming damage, stun/root, shield
pool — are folds over the entity's active effects.

Before the rebuild each read *recomputed the fold*: a walk of an untyped `Dictionary`, an
`as StatusEffect` cast per element, a `pow()` per axis; roughly 80 walks per tick at a full
wave, plus (inside the tick) a `.keys().duplicate()` per entity and a re-run of the config's
14-rule authoring audit per effect. Every one of those costs was spent re-deriving values
that change a few times per second at most.

Now: **derive once, invalidate on change.**

- `_effects` is `Dictionary[StringName, StatusEffect]`, so a read is a field fetch and a
  mis-cast is not expressible. It stays runtime-only: Godot 4.4 cannot serialise a typed
  Dictionary whose values are Resources inside a `.tres` (godot#100889) and will not accept
  one assigned from `JSON.parse_string` (godot#97137), so it must never become an `@export`
  or a save field.
- The fold runs lazily behind `_aggregates_dirty` — the Dirty Flag pattern, which is what
  Godot itself does for a body's global transform and what Unreal's GameplayEffects does
  with a per-attribute aggregator (`FOnAggregatorDirty`), rather than re-evaluating per
  frame. The flag is set by exactly the four events that can change a fold: an application
  (which may add stacks), a removal, an absorbed shield layer, and the tick in which
  `remaining` crosses zero. `StatusEffect.reapply()` returns whether it changed anything a
  fold depends on, so a duration-only refresh — a weapon that re-applies burn every swing —
  costs nothing at read time.
- `get_debug_snapshot()` exposes `recomputes` and `aggregate_reads`, and
  `tests/unit/test_status_manager.gd` asserts 90 reads cost one fold. A cache with no
  observable counter is a cache nobody can test, and a cache that is never refuted is how
  you get a stale stun.
- A shield layer lives on the `StatusEffect` that grants it. There used to be a second
  Dictionary keyed by effect id, re-summed with `.values()` on every apply, removal and hit.
- An idle manager is not ticked at all: `set_physics_process(false)` while the table is
  empty. With 40 enemies alive, "no effects" is the common state and used to cost a
  `_physics_process` call plus an `is_empty()` test anyway.
- Authoring is validated at load (`StatusEffectConfig extends ValidatedConfig`, so
  `ContentLoader` audits every `data/status/*.tres` and `ContentRegistry` halts on a
  problem) and once per application for a config built in code. The per-tick variant guarded
  "an old save with bad numbers"; status state has never been serialized.

Two existing semantics the fold has to preserve, both pinned by tests: the multiplicative
axes *include* an effect that expired this tick but has not been removed yet (that is what
the per-read scans did, and it self-corrects inside the same tick), while the stun/root
locks *exclude* it — a stale lock freezing the player one extra frame is the bug the old
code guarded against. And because a listener can `cleanse_all()` from `HealthComponent.damaged`
mid-tick (the Purge pickup path), the tick iterates a reused scratch array rather than the
live Dictionary — erasing while iterating is undefined in Godot — and re-checks `has(id)`.

`StatusEffect.SOFT_LOCK_CAP_SECONDS` is the companion to `validate()`'s rule that a
*permanent* stun/root is illegal: `validate()` refuses duration 0, the cap refuses a long
one. The comment claiming that hard stop existed before the rebuild, but it was written as a
`maxf` floor, so `duration = 30` next to `stuns = true` was a 30-second freeze with a
comment saying it was capped at 3. Now both the initial duration and every re-apply go
through the ceiling.


## The authored world (theme, landmark, obstacles)

An arena's *identity* — what the sky looks like, what stands in the middle, what you can hide
behind — was the last place where content lived as code. Three tables keyed by arena id string
decided it: `Arena.THEMES` (colour/energy presets per id), `Arena.PANORAMA_SKIES` (the HDRI per
id) and `ArenaObstacles.layout_for()`'s `match String(arena_id)` (hand-tuned pillar
coordinates, with a `_:` arm handing any arena nobody added *The Pit's* layout). Obstacles then
travelled between systems as `{"pos", "half_size", "kind"}` Dictionaries, read with
`.get("pos", Vector3.ZERO)`. Every one of those failed the same way: **wrong was identical to
missing**, and both looked like success.**

Now `ArenaConfig` owns three more authored fields, and `arena.gd` shrank from 533 lines to 354 with no arena id left in it at all:

> `arena.gd` is 556 lines now. That is features, not tables coming back: solid decoration props
> publish their nav footprints (`ArenaDecorator.get_nav_blockers()` → `Array[AABB]` →
> `Arena.register_decoration_blockers`, so AI paths around a barrel), hazard markers were
> rebuilt on the authored hazard data, and the three former arenas became one multi-room dungeon
> — `DungeonGenerator` builds interior walls (each a body + mesh + nav footprint) and
> `ArenaConfig.extra_landmarks` mounts the forge and crystal centrepieces in their wings. The
> 533 → 354 number above stays as the sweep reported it.
> (The last three lines are the engine-contract comment where `_apply_sky_and_light` sets
> `env.sky` — the canonical Godot-4 name the engine-api gate pins, not the Godot-3 compat alias
> `background_sky` that lived there before.)


| Field | Type | Replaces |
| --- | --- | --- |
| `theme` | `ArenaThemeConfig` (`data/arena_themes/<arena_id>.tres`) | `THEMES` + `PANORAMA_SKIES` |
| `landmark` | `ArenaLandmarkConfig` (`data/arena_landmarks/<name>.tres`) | the `match kind` + `_:` arms in `_spawn_landmark` / `_add_landmark_collision` |
| `extra_landmarks` | `Array[ArenaLandmarkPlacement]` (a shared landmark config + per-wing position) | the *second and third* arenas' centrepieces, now wings of one dungeon |
| `obstacle_layout` | `Array[ArenaObstaclePlacement]` | the `match String(arena_id)` table and its Dictionary records |

Four structural rules carry the rest:

1. **One vector, three consumers.** `ArenaObstaclePlacement.footprint()` and
   `ArenaLandmarkConfig.footprint()` (both `footprint_half * scale`) are *the* geometry: the
   collision body, the box mesh and the nav-grid blocker are all derived from it. Before this,
   the landmark's collision shape and its nav footprint were two hand-written numbers per kind
   that could disagree — and the landmark's `_hd_marble_mat` helper, which nothing called, was
   a third. `ArenaNavGrid.build()` takes `Array[AABB]` rather than (pos, half_size) pairs,
   because a misread of exactly that convention had already shifted every blocked cell once
   (the bug its old comment recorded).
2. **Silence is authored, never inherited.** `theme = null` means "keep the scene's look";
   `landmark = null` means an open floor; an empty `obstacle_layout` means
   `ArenaObstacles.fallback_layout()` (The Pit's pattern, the only place that still scales to
   the floor — it exists to serve an arena whose size nobody knows). An unknown landmark `kind`
   is a `push_error` plus *nothing built* (no mesh, no body, no blocker) instead of the old
   quiet obelisk, and `validate()` refuses it at load, so the runtime branch is unreachable for
   shipped data.
3. **Authored means validated.** `theme`/`landmark` are hard resource references, not ids, so
   there is no table to keep in sync with a folder — and a reference that goes stale is a
   `[ext_resource] referenced nonexistent resource` parse error at import, which CI greps for.
   (This is the shape Unity settled on for the same problem: a Volume's `PostProcessProfile` is
   a shareable asset of look settings whose *absent* overrides defer to the scene, exactly what
   `theme = null` and a per-field default do here.) Because themes are not registry rows,
   `ArenaConfig.validate()` calls `theme.validate()` and `landmark.validate()` itself —
   including a cross-check neither can do alone: a placement centre inside the landmark's
   footprint is refused, since it draws nothing, is still solid, and blocks the AI away from a
   wall nobody can see.
4. **Absolutes, not proportions.** An authored obstacle position is in *that arena's* metres
   and is never rescaled; only the fallback scales. That is a deliberate behaviour change from
   the deleted table, which multiplied whichever arena fell through to `_:` by
   `half / 12.0` — so a bigger floor silently got a bigger *pattern* of cover than it was
   designed around.

What stays code is what must: the silhouettes (`ArenaLandmark` builds a forge's basin, a
crystal cluster's prisms, an obelisk's shaft — mesh construction is not a thing a `.tres` can
express), the material recipes, and the geometry that turns a footprint into a body. One
per-arena branch remains on purpose: `ArenaDecorator.decorate()` still matches the arena id to
choose its prop scatter, because that scatter is seeded from the id and re-keying it would move
every brazier and banner in a shipped arena — a change nobody can sign off without a running
game. `tests/python/test_regress_arena_world_data.py` pins that to exactly one `match
String(arena_id)` in `scripts/arena/`, audits every shipped theme/landmark/obstacle number
against the values the tables held, and fails if a Dictionary record comes back.


## Wave rules (mutators, the director, and the one folded record)

A wave's difficulty is the product of three sources, and for as long as each of them handed the
next one a Dictionary, the boundaries were where the game lost features. `WaveMutators` held the
seven shipped mutators as a `match` over hand-written Dictionaries ending in a **neutral**
fallback for unknown ids; `SpawnManager` had two Dictionary records (`_difficulty` for the plan,
`_wave_mods` for modifiers) and its setter copied four named keys, keeping "missing keys default
to neutral; unknown keys are ignored"; the director's `next_wave_multipliers()` returned a record
whose `score_mult` nobody read. Grepped key by key, that meant `currency_mult`,
`player_damage_mult`, `score_mult`, `burn_tick` and the folded `severity` were computed and
discarded — three of seven mutators advertised on their banner more than they did, and
`RunState.active_modifiers`, which the save and the run summary both read, was never written by
anyone.

Now: mutators are `WaveMutatorConfig` resources under `res://data/mutators/` (registered by
`ContentLoader`, referenced by id from `WaveConfig.arena_modifier_ids`, `GameModeConfig.forced_mutators` (loaded from `res://data/game_modes/`)
and the challenge pool — all four checked at load). The fold's result is one typed value object,
`WaveModifiers`, built by `WaveManager._fold_modifiers()` in a documented order — plan scalars,
then the director's bounded nudge, then the mutators — and bounded once by `clamp_bounds()`.
`SpawnManager`, `RunScorekeeper`, `WeaponManager` and the banner read fields off it; the only
Dictionaries left in the pipeline are `WavePlanner.calculate_difficulty_scalars()`'s (a
test-pinned scalar function, absorbed by `apply_plan_scalars`) and `debug_dictionary()`, which
exists for the debug snapshot. Clamping lives on the record rather than in each consumer, so a
consumer cannot forget it, and `WaveMutators` holds no numbers: selection and resolution only,
with the pool's order authored as `roll_order` because the daily challenge's mutator pair is
`pop_at(index)` over that order.

The wave's status (Ember Winds) is an ordinary `StatusEffectConfig` stamped through
`StatusManager.apply_effect()` — a mutator does not get its own damage path, and `DoT →
DamagePayload → take_damage` stays the only route a status can hurt by. Multipliers are never
saved: `RunState` keeps the ids (`active_modifiers`, serialized) plus a live, transient
`modifiers` record that `reset()` clears, so a resumed run re-derives the numbers for the wave it
is about to launch instead of replaying a stale fold.

`tests/python/test_regress_wave_mutators.py` mirrors the shipped mutator numbers, scans every
consumed key for a reader, pins the fold order, and refuses the old shapes;
`tests/unit/test_wave_mutators.gd` covers the arithmetic and the refusal paths headlessly.


## Run definitions (modes, the ladder, and the announcer's voice)

A run's *rules* are now data too. `GameMode`'s docblock had promised for as long as the mode list
existed that adding a mode was data-only; it was not, because `CATALOG` was a Dictionary in code,
thirteen accessors each carried their own `.get(key, default)`, and `def()`/`validated()` answered an
unrecognised id with Standard. A renamed mode id was therefore not an error — it was an endless 1.0×
run wearing another mode's name. Four of the seven modes also fell through a `match` for their
victory copy, `collect_target` was authored on two of seven, `upgrade_every` was `maxi(…, 1)`-wrapped
so "no upgrades" could not be authored, and `narrator_id`, `boss_interval` and `unlock_prestige` were
authored on all seven and read by nothing.

Now a mode is `res://data/game_modes/<id>.tres` (`GameModeConfig`, 21 exported fields) and its
scripted waves are `GameModeWavePlan` rows inside it. `GameMode` resolves and reads; it no longer
decides anything by name. Composition differences are fields — `planner_wave_offset`,
`planner_wave_floor`, `every_n_waves` + `every_n_append`, `wave_plans` — which is why five per-mode
queue builders and the campaign's `match wave_number` over literal archetype lists are gone, and why
`Narrator`, `ObjectiveDirector` and the setup panel ask a mode's fields instead of matching its id:
`scripts/` contains no comparison against a mode id at all, only the seven `MODE_*` handles callers
use to name the files.

The same shape took the rest of `scripts/meta/`'s tables out:

- `Prestige`'s titles, cost curve, challenge tiers and cosmetic staircase are
  `res://data/prestige/ladder.tres` — `ChallengeTier` and `PrestigeUnlock` rows validated by the
  config that owns them, so a gap in the ladder can no longer pay the top rank the easiest run.
- `Narrator` knows no arena id, no mode id and no archetype id. Arena flavour is three
  `ArenaConfig.lore_*` fields authored in the arena's own `.tres`; wave flavour is the mode's beat
  row. `ARENA_LORE`, `MODE_INTRO`, `CAMPAIGN_BEATS` and `ENEMY_BLURBS` (which read nothing at all)
  are deleted, and `run_setup_panel` prints the arena's `lore_intro` instead of guessing from tags.
- UI copy that had been a constant is now computed: the armory panel's armory gate is
  `Prestige.armory_completion_required()`, and a mode's victory line comes from `victory_line`.

**A migration must not change what the player reads.** The four modes that used to fall through the
old `match` still emit `"Victory. The stand holds."`; that, and every other string in the seven mode
files and the ladder, is mirrored in `tests/python/test_regress_run_modes.py`.
`tests/unit/test_game_modes.gd` covers the resolvers and each `validate()` refusal path, and
`tests/integration_stages.gd::_run_run_definition_integration` proves the wire in a live tree: a real
`Narrator.announce_wave` emits the campaign row's own text, a cold `Prestige.ladder()` still finds
the content folder when the harness booted no registry, and a run's payout is the mode's own
multiplier and nothing else — with the boot-less harness that is a standard run, so the ladder must
not reach in at all, and the rung a challenge run gets at rank 8 is checked against the row the
ladder's `tier_index_for_rank` selects rather than a literal index (the rungs unlock at 0/2/4/6/8).

## Autoload policy

Autoloads (EventBus, DebugErrorHandler, SaveManager, AudioManager,
ContentRegistry, GameRoot, SceneRouter, RunAnalytics, TestHarness) are
referenced **directly by name** in GameRoot/main/UI code — they are project
singletons.

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
- **Touch buttons fire on press-down** (`TouchActionButton._fire` on the down
  event, hold tracked until release for anti-repeat), matching the engine's
  own `TouchScreenButton.pressed`; menu `Button`s intentionally stay
  release-activated. `TouchControls._ready` (never the press handler) owns the
  `resized`/`visibility_changed` wiring — wiring layout per-press re-connected
  signals on every declined tap and stomped the safe-area plan mid-combat.
- **OS interruption routing.** `project.godot` sets
  `application/config/quit_on_go_back=false`, so Android Back arrives as
  `NOTIFICATION_WM_GO_BACK_REQUEST`, which `UiRoot` routes (modal > auxiliary
  screen > pause/resume/menu/guarded-quit, mirroring Esc). `GameRoot`
  auto-pauses on `APPLICATION_PAUSED`/`APPLICATION_FOCUS_OUT`/
  `WM_WINDOW_FOCUS_OUT`, strictly gated on pausable states (the engine does
  NOT pause the tree when the app backgrounds — without this a call taken
  mid-wave means returning to a corpse). No auto-resume anywhere.
- **Emulation contract.** `input_devices/pointing/emulate_mouse_from_touch`
  must stay `true` — every standard menu/skill/pause `Button` answers touch
  only through emulated mouse events — while `emulate_touch_from_mouse` stays
  `false` (the custom stick/buttons handle desktop mouse natively; synthesized
  touch would double-fire them).
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
