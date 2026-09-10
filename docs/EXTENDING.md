# EXTENDING.md — How to add content without rewriting core systems

Content is added through **data resources + registries + scenes**, not core rewrites.
The `ContentRegistry` autoload discovers `.tres` files under `res://data/<kind>/`,
validates them, and caches them. Broken content is a hard authoring error: in debug /
test builds a resource that fails to load, has the wrong script type, or fails its own
`validate()` **halts startup** (see the registry's `_ready()`), so a bad `.tres` cannot
silently ship a game missing that content. Release builds report every problem and
continue with the degraded-but-usable tables. This file shows each common extension.

## 1. Add a new enemy archetype

1. Create `res://scenes/enemies/<name>_enemy.tscn` as a **child scene that instances
   `res://scenes/enemies/enemy_base.tscn`** — like all eight shipped archetypes — and
   override only what is archetype-specific (collision shape / `Body` mesh + material /
   `TargetingOrigin` + `AttackOrigin` offsets, and for the boss, `NavigationAgent3D`
   distances). **Never copy the base tree**: a copy re-declares the shared wiring and
   silently diverges from it (the pre-2026-09-08 state the QA audit flagged). The
   contract is enforced by `tests/python/test_regress_enemy_scene_inheritance.py` and
   `tests/unit/test_enemy_scene_inheritance.gd`.
2. Create `res://data/enemies/<name>_enemy.tres` with `class EnemyConfig`:
   `archetype_id`, `display_name`, `blurb`, `scene`, stats, `color_tint`, `tags`, `unlock_wave`.
   `blurb` is the line the announcer reads the first time that archetype appears in a run
   (`Narrator.note_enemy_spawned` → one `EventBus.announcement`, never repeated until
   `Narrator.reset_run()`); leave it empty for a grunt that needs no introduction. An empty blurb is
   "this one is never announced", not a fall-through to a default line — `Narrator` holds no enemy
   copy of its own, so there is nothing to fall back to.
3. Restart/refresh — the registry validates it (missing scene, bad values, duplicates)
   and exposes `ContentRegistry.get_enemy(&"<name>")`.
4. Add it to wave data so it can appear, plus a `WaveSpawnEntry`.

5. Give it a **detection tuning + presence in waves**: if it should only show up later,
   add it to the deterministic composition in `wave_planner.gd` (`_counts_for_wave`) and
   give it an `unlock_wave` in its `.tres`; the `SpawnManager` and `WavePlanner` read the
   queue composition, so a new archetype is exercised the moment it is queued.
6. **Model + animation**: add an `EnemyAnimator` child to the scene with `model_scene`
   (the role's GLB from `docs/ASSET_CATALOG.md`), `model_extent` (fit height in meters)
   and an `animation_map` (`idle`/`run`/`attack`/`hurt`/`death` clip names). The
   animator is a no-op without a model, so primitive scenes keep working.
7. **Identity hooks (all optional, data-driven on `EnemyConfig`)**: `poise`
   (uninterruptible windups), `attack_retreat_time` (hit-and-run), `dash_*` fields
   (telegraphed charge via `EnemyDashState`), `fuse_range`/`fuse_time`
   (self-detonation via `EnemyFuseState`), `split_burst` (children at death site).
8. **Boss archetypes**: add a `BossController` child and author its `phase_plan`
   as `BossPhaseConfig` entries (threshold/damage/speed/abilities/interval) —
   phases ride `EventBus.boss_spawned` / `boss_phase_changed` / `boss_slain`, which
   the BossHealthBar already binds. Ability selection is seeded from the run seed.

No core script changes.

## 2. Add a new upgrade

1. Create `res://data/upgrades/<name>.tres` (`class UpgradeConfig`).
2. Set `upgrade_id`, `display_name`, `description`, `rarity`, `max_stacks`,
   `stat_modifiers` (use the stable modifier keys listed in `upgrade_config.gd`),
   `prerequisites`, `exclusions`, `unlock_wave`, `weight`, `disabled`.
3. Validation checks modifier keys/prerequisites/exclusions/rarity automatically.
4. The `ContentRegistry` auto-discovers it; the `UpgradeSelector` includes it in the
   valid pool (respecting `unlock_wave`, `disabled`, prerequisites/exclusions/max stacks
   and `weight`); `GameRoot.present_upgrade_selection_for_wave()` offers it after an
   upgrade wave and `ProgressionComponent` applies its modifiers.

The upgrade panel (in `scripts/ui/ui_root.gd`) renders whatever the selection system
returns and sends the click only to `GameRoot.request_upgrade_selection()` — no UI
rewrite and no direct progression mutation from the UI. The selection is **deterministic**:
for the same run seed + wave + current stacks the same choices are produced, so headless
tests can assert exact upgrade flow.

### Modifier semantics (single documented model)

`ProgressionComponent` uses one consistent model. Author values in **decimal domain**
(`0.15` == `+15%`), and stacking is additive in that domain. Consumers read one of:

| Family | Keys | Formula |
|---|---|---|
| multiplicative | `move_speed_multiplier`, `attack_damage_multiplier`, `knockback_multiplier`, `skill_damage_multiplier`, `area_radius_multiplier`, `area_damage_multiplier`, `status_duration_multiplier`, `status_damage_multiplier` | `base * (1 + Σ)` |
| cooldown | `attack_cooldown_multiplier`, `dodge_cooldown_multiplier`, `skill_cooldown_multiplier` | `base * (1 + Σ)`, clamped `>= 0.05` (a *negative* Σ is a reduction) |
| additive | `max_health_add`, `attack_range_add`, `healing_on_kill`, `score_multiplier_add`, `currency_multiplier_add`, `crit_chance_add`, `crit_multiplier_add`, `projectile_count_add`, `projectile_pierce_add`, stamina/pickup/xp keys | `base + Σ` |
| chance/status forwarding | `status_chance_add` | copied to weapon/skill proc resolvers and clamped at use |
| resistance | `damage_resistance_add` | `base + Σ`, clamped `[0, 1]` |

Examples: two `+15% damage` stacks → `base * 1.30`. One `-10% cooldown` → `base * 0.9`
(it can never *increase* cooldown). `max_health_add +20` from `100` → `120` (and if the
player was already at full health the current HP is topped up to the new max, so
`100/100 → 120/120`). Resistance is consumed by the player as `damage *= (1 - resistance)`
so a `1.0` resistance floors at 0, never negative damage.

## 3. Add a new arena

An arena is a scene plus one `.tres`. The scene provides geometry and markers; the
`ArenaConfig` provides gameplay *and* the world — hazards, look, centrepiece, cover. Nothing
in `scripts/arena/` knows your arena's id (the one documented exception is the prop scatter,
step 7).

1. Create `res://scenes/arena/<name>_arena.tscn` following the canonical arena tree:
   `PlayerStart`, `SpawnPoints`/markers in group `enemy_spawn_point`, colliders,
   `Lighting/Sun`, a `WorldEnvironment` named `Environment`, floor/wall meshes, and a
   `Geometry` parent if you want the theme to tint them. `arena.gd` handles marker discovery
   generically and builds obstacles/landmark/nav floor at `_ready()`.
2. Create `res://data/arenas/<name>.tres` (`class ArenaConfig`) pointing at the scene,
   with a `default_camera_profile` and `background_music_cue`. Author its hazards in the
   same file (`hazard_layout`, see §11) — an arena that authors none still gets the four
   compass vents `ArenaHazards.fallback_layout_positions()` describes, so a new level is
   never hazard-less just because nobody got to it.
   **Author its voice** in the same file: `lore_intro`, `lore_mid` and `lore_late` are the three
   lines `Narrator` prints on wave 1 (only when the mode authored no `intro_line` of its own), wave
   5, and every tenth wave after that. The announcer knows no arena ids to fall back on, so an arena
   that leaves them empty is simply not narrated — a milestone wave with nothing to say emits no
   announcement at all rather than an empty banner.
3. **Author its look** as `res://data/arena_themes/<arena_id>.tres` (`ArenaThemeConfig`) and
   point `theme` at it. Copy a shipped file and change numbers: sky/horizon/ground colours,
   `panorama_path` (a `res://` `.hdr`; a soft *path*, not an `ExtResource`, so a device without
   that import still gets your procedural sky), fog colour + density, sun colour + energy,
   ambient colour + energy, `brightness`/`contrast`, the glow triple, and the floor/wall tints
   with `floor_node_path` + `wall_node_prefix` naming what to tint. `theme_id` must equal the
   file name; `theme = null` is a valid choice meaning "keep the scene's own look".
4. **Author its centrepiece** as `res://data/arena_landmarks/<name>.tres`
   (`ArenaLandmarkConfig`) and point `landmark` at it. `kind` selects the silhouette
   `ArenaLandmark` knows (`obelisk`, `forge`, `crystal`); `shape` (`box` or `cylinder`) +
   `footprint_half` are the collision body *and* the nav blocker — one vector, so physics and
   AI cannot disagree — and the rest is tint, roughness, accent colour, `emissive_energy` and
   one authored `OmniLight3D` (`light_*`). A `kind` with no builder is refused at load and
   builds nothing at runtime rather than quietly becoming an obelisk. `landmark = null` is an
   open floor.
5. **Author its cover** by appending `ArenaObstaclePlacement` entries to `obstacle_layout`:
   `position` in *this arena's* metres, three `half_size_*`, and `mirror` (`"x"`, `"z"`,
   `"rot180"`, `"both"`) — the same vocabulary `hazard_layout` uses, so "a pillar on each
   flank" is one line. Positions are never rescaled to the floor size; an arena that authors no
   layout at all gets `ArenaObstacles.fallback_layout(half)` (The Pit's corner ring and gate,
   scaled). A placement whose centre lands inside the landmark footprint is a validation error.
6. Restart/refresh: `ContentLoader` registers the arena and `ArenaConfig.validate()` reaches
   `theme.validate()` / `landmark.validate()` and every placement, so a bad colour channel, a
   fog density that hides the far half of the floor, an unknown landmark kind, a flat box and
   an obstacle buried in the centrepiece are all startup errors. The look and the cover are
   referenced by hard resource reference, so a renamed or moved `.tres` is an editor error,
   not a runtime miss.
7. **The one remaining per-arena branch**: `ArenaDecorator.decorate()` still matches the arena
   id to choose its prop clutter (braziers vs ice shards vs the stone circle). That scatter is
   seeded from the id, so moving it to data would move every prop in a shipped arena — a visual
   change no headless test can sign off. A new arena gets the default coliseum decoration until
   someone adds a composition there. `tests/python/test_regress_arena_world_data.py` pins it to
   exactly one `match String(arena_id)` in the file and fails if a second one appears anywhere
   in `scripts/arena/`.
8. Unlock it via `SaveManager.unlock_arena("<name>")` (or ship pre-unlocked).

**Scattered decoration is physical.** Anything `ArenaDecorator` scatters as a floor prop gets a
`StaticBody3D` on `CollisionLayers.WORLD_BODY_LAYER` and publishes its axis-aligned footprint (an
`AABB`, rotated into world bounds first) through `ArenaDecorator.get_nav_blockers()` into
`Arena.register_decoration_blockers()`, so the nav grid the AI routes on and the physics the player
bumps into are derived from the same numbers. A prop added to the scatter lists is therefore solid
and pathable-around with no extra work; a prop whose box has no area is dropped at registration
rather than blocking a row of the grid.

## 4. Add a new weapon

1. Add a `WeaponConfig` resource under `res://data/weapons/`. Required tuning includes
   `weapon_id`, `kind` (`melee`, `ranged`, or `hybrid`), `attack_pattern`, `damage_type`,
   `base_damage`, `swing_cooldown`, `range`, `arc_degrees`, combo steps, crit tuning,
   and `unlock_wave`/`weight`. Ranged or hybrid weapons also set projectile speed,
   lifetime, count and pierce. The registry validates + caches it.
2. Melee and hybrid swings use `WeaponManager` → `MeleeResolver`; ranged and hybrid
   shots use the same manager → `RangedResolver` → fixed `ProjectilePool` path.
   `attack_pattern` and tags describe identity while numeric fields tune geometry and
   cadence; no new resolver branch is needed for normal content.
3. `WeaponManager` is the single attack authority (the legacy `AttackController`
   fallback was removed) — equip through
   `WeaponManager.equip_by_id(id, slot, bypass_wave_gate=false)`. Ordinary calls reject
   unknown, disabled, invalid, and future-wave ids; only run setup may explicitly pass
   `true` for a starter/daily/meta loadout. `set_current_wave()` is driven by GameRoot.
4. `WeaponManager.get_loadout_ids()` is the stable serialization mirror. It never owns
   content discovery: callers must resolve configs through `ContentRegistry`.
5. Ranged enemies reuse the same `ProjectilePool` through `EnemyRangedState`; no
   separate projectile runtime is introduced.

## 5. Add a new audio cue

1. Drop an `.ogg` in `res://data/audio/<cue_id>.ogg` (registry auto-registers it with
   `AudioManager` keyed by file base name).
2. Play it anywhere via `AudioManager.play_sfx(&"<cue_id>")` (music via `play_music`).
3. Log its licence in `AUDIO_MANIFEST.md` and store the licence file in
   `ASSET_LICENSES/`.

Optional cues are safe: a missing cue logs a diagnostic and never crashes.
Accepted formats are `.tres`/`.res` streams and raw `.ogg`/`.wav`/`.mp3` drops.
(The 10 gameplay SFX + 5 music beds always resolve: `ProceduralSfx` synthesizes
any cue still missing after discovery, so the game is never silent. Real drops
take precedence — procedural fill never overwrites a registered cue.)

## 6. Add a new UI panel

1. Add a panel `Control` (or extend `ui_root.gd`'s `_build_screens`).
2. Drive it from `GameRoot` state via `EventBus.game_state_changed` and the panel
   switching in `ui_root.gd` — UI never mutates global state, it calls the narrow
   `GameRoot` command API.
3. Build widgets with `UiFactory` and style them from `UiTheme`. Use the shared
   spacing scale (`UiTheme.SPACE_S/M/L`) instead of ad-hoc pixel gaps, and never
   set an interactive control smaller than `UiTheme.TOUCH_MIN` (88px) — the
   factory clamps buttons and checks for you.
4. For a **gameplay overlay** (something drawn over the arena, not a full-screen
   modal), do not position it by hand. Add its rect to `UiLayout.compute()` in
   `scripts/ui/ui_layout.gd` and place it from `ui_root._layout()` with
   `UiLayout.place()`. `UiLayout` is a pure static solver: no tree, viewport or
   singleton access, so `_test_layout_solver` in `tests/ui/ui_test_runner.gd`
   can assert — across every Android resolution and text scale — that the new
   element stays inside the safe area, clears the touch controls and never
   overlaps another overlay. Handle `UiLayout.is_collapsed()` by hiding the
   element on screens that have no room for it.

## 7. Add a new test

1. Create `res://tests/unit/test_<area>.gd` exposing `static func suite() -> Array`
   of `{name, passed, why}` dictionaries (see existing tests).
2. Add the path to `UNIT_SUITES` in `res://tests/run_tests.gd`.
3. Run `godot --headless --path . --script res://tests/run_tests.gd`.

> **Harness boundary:** that command runs a bare `SceneTree` without the project's
> autoload singletons (`GameRoot`/`EventBus`/`ContentRegistry`/…), so a unit test there
> cannot drive the **real** GameRoot loop or instantiate scenes whose scripts reference
> those singletons (compiles fine in-game, fails under `--script`). Keep suites here
> pure / autoload-independent. For a real-singleton end-to-end test run a context where
> autoloads are live (e.g. `godot --headless --path .`) — see the note in `docs/BUILD.md`.

## 8. Tune the wave loop (counts, pacing, difficulty)

- Counts / first-wave appearance of each archetype live in `wave_planner.gd`
  (`_counts_for_wave`, `spawn_queue_for_wave`).
- Per-wave pacing (spawn interval, simultaneous cap), the completion bonus and the
  inter-wave `transition_delay` are produced by `WavePlanner.generate_wave(...)` into a
  typed `WaveConfig` and consumed by `WaveManager` / `SpawnManager`.
- Stat scaling over waves is `WavePlanner.calculate_difficulty_scalars(wave)` (hp /
  damage / speed, each clamped) and is applied per enemy at spawn via
  `EnemyBase.apply_difficulty(...)` — shared `.tres` configs are never mutated.

## 9. Add a new enemy AI state

1. Subclass `EnemyState` (`scripts/enemies/enemy_state.gd`) and implement `_init` calling
   `super(&"<state_id>")` plus any of `enter/exit/update/physics_update`.
2. Register the id + instance in `EnemyStateMachine._ready` and add the id to its
   `STATE_IDS`.
3. Mutate the host only through the `EnemyBase` command surface and request transitions
   with `host.state_machine_change_to(&"...")` (or `host.force_state(&"...")` for
   interrupts such as damage/hurt). Never reach into arbitrary nodes from a state.

## 10. Add a new skill / status effect

1. Create `res://data/skills/<name>.tres` (`SkillConfig`) with `skill_id`, one of the
   validated `behavior` ids (`slam`, `whirl`, `dash_strike`, `shockwave`,
   `chain_lightning`, `warcry`, `heal_surge`, `frost_nova`), cooldown/stamina,
   damage/radius/length tuning, optional victim/caster status ids, and
   `unlock_wave`/`input_action`. `SkillController` owns slots, unlock gates and
   cooldowns; `SkillExecutor` sends damage through `AreaDamage`, status through
   `StatusManager`, and shockwaves through `ProjectilePool`.
2. A new status is **one `StatusEffectConfig` resource** under `res://data/status/` — no
   code. `effect_id` (which must equal the file name), duration (`0` = permanent until
   cleansed), `max_stacks`, `stack_mode` (`refresh`, `add`, `reset`), DoT/HoT and their
   cadence, `move_speed_factor` / `damage_factor` / `received_damage_factor`,
   `stuns`/`roots`, `shield_amount`, tint and tags. Every axis is data, so there is nothing
   to branch on: `StatusManager` folds whatever is active into five cached numbers and
   `AreaDamage`/hazards/AI read them.
   The registry validates cross-resource ids (a weapon or skill naming a status that does
   not exist is a startup error), and `validate()` itself refuses the authoring traps that
   would break the game loop: a permanent stun or root, a permanent shield, a zero
   `tick_interval`, an unknown `dot_type`/`stack_mode`, a negative factor. That audit runs
   at load, because `StatusEffectConfig extends ValidatedConfig` — not per tick, which is
   what it used to cost.
   `StatusManager.apply_effect(...)` copies caster duration/status power into runtime
   `StatusEffect` instances without mutating the shared `.tres` (resources are shared;
   one `status_damage_multiplier` stat scales DoT and HoT together by design). Cleansing and
   expiry remove unspent shield layers; `add` grants only the newly acquired capacity, so
   refreshing at max stacks cannot farm shield. A stun/root longer than
   `StatusEffect.SOFT_LOCK_CAP_SECONDS` (3 s) is capped on apply *and* re-apply.
3. `SkillController.set_current_wave()` and `unlock_skill()` are the public gate for
   ordinary runtime unlocks; both the resource's level and wave gates must be met.
   `unlock_available()` reconciles a level-up and a later wave-up. `get_assigned_skill_ids()` is the serialization mirror;
   UI should only call `try_cast_slot()` and never mutate configs or progression.

## 11. Add arena hazards / mutators

1. **A hazard that reuses a mechanic is one `.tres`.** Copy `res://data/hazards/spike_bed.tres`,
   give it a `hazard_id`, and set the numbers. `mechanic` is `"pulse"` (a discrete burst) or
   `"field"` (applies while you stand in it); `trigger` is `"periodic"` (fires on `period`,
   with optional `telegraph` warning time) or `"proximity"` (fires when a victim enters
   `trigger_radius`, then re-arms on `fire_cooldown`). A field that travels gets
   `orbit_radius_fraction`; a field that heals gets `heal_per_second`; a pool that slows
   names a `status_effect_id` and lets the status own the speed number. Nothing under
   `scripts/` changes, and `radius` is used for the visual disc *and* the hitbox, so they
   cannot drift. The file name must equal the `hazard_id`: the loader keys the table by id.
2. **Place it in an arena.** Append a `HazardPlacement` to `hazard_layout` in
   `res://data/arenas/<arena>.tres`: `config` (a hard reference to the hazard `.tres`),
   `position`, and optionally `mirror` (`"x"`, `"z"`, `"rot180"`, `"both"`),
   `radius_override`, `phase_jitter`. `mirror` is why the shipped layouts read as six
   lines instead of eleven coordinates — "a vent on each flank" is one placement with
   `mirror = &"x"`. `phase_jitter` staggers a row of periodic hazards; at 0 they fire
   together, which is sometimes the point.
3. **Add pressure to a game mode** (optional) in `res://data/hazard_modes/<mode_id>.tres`
   (`mode_id` must match the file name and name a real `GameMode`). Mode layouts are
   *appended* to the arena's own, so a mode can raise the heat without rewriting a level.
4. **A genuinely new mechanic is the only case that touches code.** Add the id to
   `HazardConfig.VALID_MECHANICS` and a branch in `ArenaHazards._physics_process`; the
   validator refuses any `mechanic` outside that list, and
   `tests/python/test_regress_hazard_subsystem.py` requires the two lists to agree, so a
   mechanic nothing implements cannot be authored. (The pre-rebuild system had six
   per-kind tick functions and no such check, which is how "add a kind, forget a branch,
   the hazard silently does nothing" was possible.)
5. **All of it is validated at load**, not at first contact: `HazardConfig.validate()`,
   `HazardPlacement.validate()` and `ArenaConfig.validate()` run through
   `ContentLoader._register_resource()`, and `ContentLoader._validate_references()`
   additionally checks that a hazard's status exists and outlives its own re-stamp
   interval. A `trigger_radius` wider than the effect radius, a telegraph longer than the
   period, a beneficial hazard that also deals damage, a proximity pulse that cannot
   re-arm, and a fully transparent marker on a live hazard are all startup errors.
6. **Add a mutator without touching code.** `res://data/mutators/<id>.tres` is a
   `WaveMutatorConfig`, and the file name *is* the id (`validate()` refuses a mismatch, so a
   renamed file cannot be registered under a stale key). Author `display_name` and
   `description` (the daily card shows the name and tooltips the description), `severity`
   (`minor`/`major` — a major mutator escalates its wave banner to `danger`), `roll_order`
   (position in the deterministic pool: `DailyChallenge.mutators_for_stamp()` pops indices out
   of that order, so renumbering silently changes what a past date offered), `min_wave` (Glass
   Cannon's "wave 6+" is authored, not an `if` in the roller), the six `*_mult` knobs,
   `elite_bonus`, `explode_chance`, and optionally `status_effect_id` + `status_targets`
   (`none`/`enemies`/`player`/`all`) + `status_stacks` — Ember Winds' burning air is just a
   `StatusEffectConfig` stamped through the status manager. Every field has a reader and
   `tests/python/test_regress_wave_mutators.py` fails if one loses it; a mutator whose knobs are
   all neutral is refused at load, because the alternative is a banner that promises a rule and
   applies nothing.
7. **Say how it stacks.** `WaveMutatorConfig.FOLD` names the rule per field (`multiply` for
   stats, `add` for chances meant to accumulate, `max` for one-shot flags), because there is no
   generic answer to "how do two modifiers combine" and an order-of-operations decision made in
   one consumer's loop is invisible to the next. `WaveModifiers.fold_mutator` iterates that
   table, and `clamp_bounds()` bounds the whole folded set once (multipliers floor at 0.01 and
   cap at 8.0, elite bonus at 0.5, chances at 1.0, the count nudge at ±2) so no consumer has to
   remember its own clamp. Each consumer then reads a typed field: `SpawnManager`
   (hp/damage/speed/elite/volatile/status at spawn), `RunScorekeeper` (score and currency),
   `WeaponManager` (player damage), `WaveManager` (severity, spawn-count nudge, the run mirror).
   `RunState.active_modifiers` carries the *ids* into the save and the run summary; multipliers
   are derived per wave and never serialized.
8. **`WaveMutators` selects, nothing else**: `ordered_ids()`, `resolve()`, `resolve_status()`,
   `roll_for_wave()`, `resolve_for_wave()`, `fold_into()`, `display_name()`, `description()`,
   `banner_text()`. It has no mutator numbers and no id list. `WaveManager` resolves each wave
   (authored `arena_modifier_ids` win; generated waves roll — none before wave 4, one from 4, a
   second from 8 — and `DifficultyDirector` may veto into a breather or spice one up; daily and
   challenge runs force a set), folds plan scalars → director → mutators once per wave into one
   record, and hands that record over. Past the authored waves the planner scales endlessly.
   A new *mechanic* (something the fold cannot express, e.g. a knockback on spawn) is the only
   case that adds a field to `WaveMutatorConfig` + `WaveModifiers.FOLD_FIELDS` + a reader.


## 12. Add meta / achievements / dailies

1. Meta items: append an entry to the `ARMORY` dict in `meta_progression.gd`
   (`name`, `cost`, `requires`, `kind` stat/weapon/skill, `stat` + `per_rank` or
   `target`, `max_rank`, `blurb`). The `ArmoryPanel` shop renders entries
   generically; `MetaProgression.apply_all_to_run()` pipes owned stat ranks into
   `ProgressionComponent.add_permanent_bonus(...)` at run start, and `Main`
   applies owned weapon/skill unlocks to the loadout.
2. Achievements: append an entry to `Achievements.definitions()` (`name`,
   `description`, `rarity`, `hint`) and wire its predicate to the run-tracking
   callbacks (`_on_enemy_killed`, `_on_wave_completed`, ...); unlocking persists
   through `SaveManager.unlock_achievement(...)` and announces via `EventBus`.
3. Daily challenge: `DailyChallenge` derives `(seed, mutators, weapon)` from the
   calendar date; the menu surfaces it via `GameRoot.start_daily_run()`, which
   fixes the run seed, forces the mutator pair every wave, and equips the daily
   starter weapon.

## Module map (large-file splits)

Heads-up for contributors: the biggest scripts are thin orchestrators over focused
modules. Put new logic in the module, not the orchestrator:

| Orchestrator | Modules | Put new... |
|---|---|---|
| `ui_root.gd` | `UiText`, `UiFactory`, `GameHud`, `UpgradePanel`, `SettingsPanel`, `ArmoryPanel`, skill bar / minimap / boss bar / damage numbers / banner | strings → UiText, widgets → UiFactory, HUD → GameHud, cards → UpgradePanel, settings form → SettingsPanel, meta shop → ArmoryPanel |
| `player.gd` | `PlayerLocomotion`, `PlayerBuild` | input/bounds → Locomotion, upgrades/derived stats → Build |
| `enemy_base.gd` | `EnemyLocomotion`, `EnemyNavigator`, `EnemyStriker` | motion → Locomotion, nav → Navigator, melee → Striker |
| `spawn_manager.gd` | `SpawnLedger`, `SpawnPlacer` | queue/counters → Ledger, points → Placer |
| `game_root.gd` | `RunScorekeeper`, `UpgradeService` | score/combo → Scorekeeper, offers/apply → Service |
| `skill_controller.gd` | `SkillExecutor` | behaviors/scheduled hits → Executor |
| `weapon_instance.gd` | `WeaponConfig` combo steps/window | combo cadence + multipliers → Config |
| `save_manager.gd` | `SaveSchema` | defaults/normalize/migrate → Schema |
| `content_registry.gd` | `ContentLoader` | scanning/registration → Loader |

Pure modules (`SpawnLedger`, `SaveSchema`, `UiText`) are covered by
`tests/unit/test_extracted_modules.gd` — extend that suite when you change them.
(Combo chaining lives in `WeaponInstance`/`WeaponConfig` and is exercised by
`tests/unit/test_weapons.gd`.)

## Public progression/content contracts

These are the seams other branches should use rather than reaching into component
internals:

- `ContentRegistry` is the only discovery/lookup authority: use
  `get_weapon`, `get_skill`, `get_status_effect`, `get_upgrade`, and the corresponding
  `get_all_*` methods. Do not scan `res://data` from gameplay code.
- `ProgressionComponent` is the live source of truth. Apply with
  `apply_upgrade_by_id()` (or a validated `UpgradeConfig`), query with `get_stat()` and
  `get_upgrade_stack_snapshot()`, and restore with `restore_progression(snapshot, wave)`.
  `RunState.selected_upgrades` and `active_modifiers` are mirrors only.
- `GameRoot.record_current_wave()` is the wave command seam. It propagates the current
  gate to progression, weapons and skills. `GameRoot.request_upgrade_selection(id)`
  is the only UI-facing upgrade command and rejects stale/unoffered/dead-player picks.
- `WeaponManager` exposes `equip_by_id(id, slot, bypass_wave_gate)`,
  `request_attack()`, `get_loadout_ids()`, and `refresh_derived_stats()`.
  `SkillController` exposes `assign_skill_by_id`, `unlock_skill`, `try_cast_slot`,
  `set_current_wave`, and `get_assigned_skill_ids()`.
- `StatusManager` owns runtime status instances. Use `apply_effect`/`apply_effects`,
  `cleanse`/`cleanse_all`, `absorb_direct`, and aggregate query methods; never edit a
  shared status resource during a run. `ProjectilePool` is fixed-size and callers must
  tolerate recycled/released projectiles.
- Run persistence stores only normalized IDs, stacks, modifiers and build tags in
  `RunState.summary()`/`SaveSchema.last_run_build`; live Nodes are never serialized.

## Conventions

- Stable IDs as `StringName`; never magic numbers — put tuning in the relevant `.tres`.
- Validate new content resources (`validate()` returns problems).
- Prefer typed resources; keep large logic out of one script.
- **A `.tres` is not GDScript, and its reader is stricter in two places.** An authored value is a
  *flat, complete* constructor call — `Color(0.22, 0.42, 0.68, 1.0)`, alpha and all, because the text
  format calls the constructor itself and does not accept the three-component shorthand legal in code;
  a short one is a parse error, the resource loads as nothing, and every arena that references it fails
  with it. And the file must be ASCII: the reader is Latin-1 oriented, so non-ASCII copy is written the
  way Godot's own writer writes it, as `\u2014` escapes, which the reader unescapes on load. A raw em
  dash in authored copy is a "Unicode parsing error" and a string the game may not read as you wrote it.
  `tool/validate_resources.py` fails the build on both; six shipped arena resources had the first and
  thirteen lines across the data and material files had the second. Scripts are a different story —
  GDScript source is read as UTF-8, so a literal em dash in `narrator.gd` stays exactly that.
- **Collision bits come from `CollisionLayers`** (`scripts/core/collision_layers.gd`),
  for bodies *and* for queries. Do not write `collision_mask = 1` in a new script and
  do not re-declare collision bits in an enemy archetype scene; the contract test
  rejects both. If you need a new layer, add the constant, name it in
  `[layer_names]`, and say what it changes in the class docblock.
- **Move things in `_physics_process`.** A node whose transform is written from
  `_process` must set `physics_interpolation_mode =
  Node.PHYSICS_INTERPOLATION_MODE_OFF` (see `docs/ARCHITECTURE.md`, "Timing
  contract"), and any teleport — pool re-entry, spawn placement, a repaired
  transform — calls `reset_physics_interpolation()` *after* the position write.
- **No per-frame allocations on the render path.** Reuse
  `PhysicsShapeQueryParameters3D` / `PhysicsRayQueryParameters3D` (see
  `EnemyPack._sep_query`, `CameraCollisionSolver`, `Projectile`) — the server reads
  them at call time.
- **Engine member names are a checked-in contract.** `tool/check_engine_api.py`
  verifies every typed member access, bare global call and `.tscn`/`.tres`
  property against the pinned engine's ClassDB (`tool/godot_api_manifest.json`).
  A property rename or removal in a future engine bump is fixed by regenerating
  the manifest (`python3 tool/build_api_manifest.py`) and answering the gate's
  findings — never by weakening the gate. When the CI `GODOT_VERSION` moves, the
  manifest moves with it (the regression test fails the drift).

## 13. Add a game mode

A mode is one resource: copy `res://data/game_modes/standard.tres` to
`res://data/game_modes/<your_id>.tres`, set `mode_id` to the file stem, and edit. No script is
involved — `ContentLoader` scans `res://data/game_modes/`, `ContentRegistry` registers every
`GameModeConfig`, `GameMode.all_mode_ids()` reads that table, and Run Setup lists whatever it finds.
(This has only recently been true: the mode list used to be `GameMode.CATALOG`, a Dictionary in
code, and a `.tres` nobody loaded would have been ignored.)

Twenty-one exported fields, grouped by who reads them:

| Field | Read by |
|---|---|
| `display_name`, `blurb` | Run Setup's mode list |
| `intro_line`, `victory_line`, `wave_plans[].beat_title/beat_line` | `Narrator` (wave 1, the end of the run, and any wave that authors a beat) |
| `objective` + `max_waves` / `target_seconds` / `collect_target` | `ObjectiveDirector` and the HUD's objective line; `objective` is one of `GameModeConfig.OBJECTIVE_*` and `validate()` refuses an objective whose counter field is missing |
| `score_mult`, `currency_mult` | `RunScorekeeper` (which skips the flat per-rank prestige bonus for a mode that scales, so a rank is not counted twice) |
| `upgrade_every` | `WaveManager`'s upgrade cadence — `0` really means *never*, which was impossible while the accessor did `maxi(…, 1)` |
| `fixed_weapon`, `forced_mutators` | `GameRoot` / `WaveManager`; mutator id lists are duplicated on the way out, so a run cannot scribble on the definition |
| `planner_wave_offset`, `planner_wave_floor`, `every_n_waves`, `every_n_append` | `GameMode.spawn_queue()` when the mode has no scripted rows — that is how Survival (`+2`, floor 3, a `heavy` every 4) and Defend (`+1`, floor 2, a `heavy` every 3) differ from Standard without a line of per-mode code |
| `wave_plans` | scripted composition: Boss Rush's five rows and Campaign's fifteen (rows 1–10 and 14–15 script both enemies and the announcer's line; 11–13 leave the queue to the planner) |
| `scales_with_prestige`, `prestige_mutator_pool` | the challenge protocol — see §15 |

`GameMode` itself is only a resolver and a set of typed accessors. `resolve(id)` / `definition(id)`
return the config from the registry, falling back to the content folder when there is no registry
(that is how the headless harness and `tool/` scripts run); a miss `push_error`s and clamps to
Standard rather than handing back an invisible 1.0× run, which is what the old `.get(key, default)`
accessors did to a typo'd id.

Before a mode ships, `validate()` gets it: `ContentLoader` calls it on every file at startup, so a
bad mode is a startup error and `godot --headless --import` fails the build. It checks what a config
can see about itself (an empty id, a `wave_plans` row that spawns nothing and says nothing, an
objective without its target, `every_n_waves = 0` with an `every_n_append` that will never fire);
the cross-file rules — unknown mutator/weapon/archetype ids, tier 0 versus the ladder — are
`ContentLoader._validate_game_modes()`'s. The seven shipped modes are mirrored field by field in
`tests/python/test_regress_run_modes.py::SHIPPED`; change a number there and that table is where you
say so.

## 14. Add a transformative upgrade

1. Create `res://data/upgrades/<name>.tres` with `category = &"transform"` and
   `effect_tags` listing one or more of the keys in `UpgradeConfig.KNOWN_EFFECT_TAGS`
   (or add a new key and handle it in `scripts/progression/build_effects.gd`).
2. Optional small `stat_modifiers` still apply through ProgressionComponent.
3. BuildEffects is attached by Main on world build and listens to dodge / damage /
   kill signals — no UI or WaveManager changes needed.

## 15. Prestige / cosmetics

The ladder is data: `res://data/prestige/ladder.tres`, a `PrestigeLadderConfig` with `cost_base`,
`max_rank`, `score_bonus_per_rank`, `currency_bonus_per_rank`, `armory_completion_required`,
`titles` (index 0 … `max_rank`), `challenge_tiers` (`ChallengeTier` rows) and `cosmetic_unlocks`
(`PrestigeUnlock` rows, each keyed by the rank that grants it). Adding a rung means adding rows —
`Prestige` reads it through `ContentRegistry`, falls back to the content folder with no registry,
and caches; `Prestige.forget_ladder()` drops that cache when content is reloaded.

`PrestigeLadderConfig.validate()` refuses the ways a ladder can lie: titles that do not cover every
rank, a cost or bonus that does not increase, rungs out of order, a tier harder *and* shorter than
the one below it, a top rung `max_rank` cannot reach, a cosmetic id `Cosmetics` does not know. The
row types check what a row can see; the cross-row rules belong to the config that owns them — which
is why a sparse ladder no longer hands rank 10 the easiest run, the way the old
`min(rank / CHALLENGE_TIER_EVERY, size - 1)` plus a second `.get()` did.

`ContentLoader._validate_game_modes()` then joins the ladder to the modes: for every
`scales_with_prestige` mode, tier 0's `score_mult`/`currency_mult` must equal the mode's own base
(and its `mutator_count` must equal the length of `forced_mutators`), and each tier's `mutator_count`
must fit inside that mode's `prestige_mutator_pool`. That pair of rules is the whole challenge
protocol: which rung you are on picks how many mutators your run forces, in pool order.

`MetaProgression.perform_prestige()` spends the wallet, strips stat ranks (keeps weapon/skill
unlocks), bumps `prestige_rank` (save schema v5), and unlocks cosmetics via
`SaveManager.unlock_cosmetic`. Ranks loaded from a save go through `Prestige.clamp_rank()` — never a
reset to 0 — so a content-load failure costs you a title instead of your progress. Armory panel
shows the row automatically and quotes the ladder's own percentages and its armory gate.
