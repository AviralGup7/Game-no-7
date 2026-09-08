# EXTENDING.md — How to add content without rewriting core systems

Content is added through **data resources + registries + scenes**, not core rewrites.
The `ContentRegistry` autoload discovers `.tres` files under `res://data/<kind>/`,
validates them, and caches them. This file shows each common extension.

## 1. Add a new enemy archetype

1. Create `res://scenes/enemies/<name>_enemy.tscn` instancing/deriving the enemy base
   contract (added in the enemy phase) with its own stats/model/animation.
2. Create `res://data/enemies/<name>_enemy.tres` with `class EnemyConfig`:
   `archetype_id`, `display_name`, `scene`, stats, `color_tint`, `tags`, `unlock_wave`.
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

1. Create `res://scenes/arena/<name>_arena.tscn` following the canonical arena tree:
   `PlayerStart`, `SpawnPoints`/markers in group `enemy_spawn_point`, colliders,
   environment. `arena.gd` handles marker discovery generically.
2. Create `res://data/arenas/<name>.tres` (`class ArenaConfig`) pointing at the scene,
   with a `default_camera_profile` and `background_music_cue`.
3. Unlock it via `SaveManager.unlock_arena("<name>")` (or ship pre-unlocked).

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
3. The legacy `AttackController` remains a fallback for older scenes. New loadouts use
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
2. New statuses are `StatusEffectConfig` resources under `res://data/status/` with
   `effect_id`, duration, max stacks, `stack_mode` (`refresh`, `add`, `reset`), DoT/HoT,
   speed/damage factors, `stuns`/`roots`, `shield_amount`, and tint. The registry
   validates cross-resource ids, and `StatusManager.apply_effect(...)` copies caster
   duration/status power into runtime `StatusEffect` instances without mutating the
   shared `.tres`. Cleansing and expiry remove unspent shield layers.
3. `SkillController.set_current_wave()` and `unlock_skill()` are the public gate for
   ordinary runtime unlocks; both the resource's level and wave gates must be met.
   `unlock_available()` reconciles a level-up and a later wave-up. `get_assigned_skill_ids()` is the serialization mirror;
   UI should only call `try_cast_slot()` and never mutate configs or progression.

## 11. Add arena hazards / mutators

1. Hazards: extend the per-arena `match` in `ArenaHazards.configure(...)` with a
   branch for the new `arena_id` (field layout, tick damage, visuals); shared
   tick/damage logic stays in `ArenaHazards`. Field tuning lives in the branch,
   not the arena `.tres`.
2. Mutators are static data + logic in `WaveMutators` (`ALL`, `resolve_for_wave`,
   per-id `apply_to_wave_mods` scalars): add the id, its display name/banner
   text, and its scalar block. `WaveManager` resolves them per wave (authored
   declarations win, the `DifficultyDirector` may veto into a breather, daily
   runs force one pair); `SpawnManager` reads the resulting wave mods at spawn.
   Past the authored waves the planner scales endlessly.

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
| `attack_controller.gd` | `ComboChain` | combo steps/window → Chain |
| `save_manager.gd` | `SaveSchema` | defaults/normalize/migrate → Schema |
| `content_registry.gd` | `ContentLoader` | scanning/registration → Loader |

Pure modules (`ComboChain`, `SpawnLedger`, `SaveSchema`, `UiText`) are covered by
`tests/unit/test_extracted_modules.gd` — extend that suite when you change them.

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
