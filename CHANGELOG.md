# Changelog

## [Unreleased] — Arena build-out · weapons, skills, arenas, enemies, meta

### Added
- **Data-driven weapon loadout** — `WeaponConfig` resources (`data/weapons/`, 5 shipped:
  fists, sword, greatsword, bow, wand) auto-discovered by `ContentRegistry`;
  `WeaponManager` owns the loadout + cooldowns, `MeleeResolver` scores arc hits,
  `ProjectilePool` serves pooled projectiles for volleys and enemy ranged attacks.
- **Active skills + status effects** — `SkillConfig` resources (`data/skills/`, 4 shipped),
  `SkillController` (charges/cooldowns, Q/E/R), `StatusManager` (burn/poison/freeze/slow/
  stun/vulnerable with refresh/stack rules), `AreaDamage` + `ChainLightning` helpers.
- **3 new arenas** — `ember`, `frost`, `storm` configs + scenes with `ArenaDecorator`
  (deterministic props), `ArenaHazards` (lava/ice/storm-floor fields), camera profiles,
  music cues, unlock waves, and mutator affinities.
- **5 new enemies** — brute, dasher, spitter (ranged), splitter (spawns mites on death),
  warden (elite shield-bearer); `StatusComponent`-aware `EnemyBase` (stun gating + slow
  scaling), elite affixes (`EliteAffix`), buff totems and healers via `EnemySupport`.
- **Combat depth** — `ComboTracker` (ranked combo with score events), `DamageNumber`
  popups, `HitstopManager` (hitstop + trauma shake), `PickupManager` (health/energy/
  score/magnet drops), enemy `AttackTelegraph` + `SpawnEffect` + `DeathEffect`.
- **Wave director** — `MutatorConfig` resources (`data/mutators/`, 6 shipped: swift/
  brutal/ember-winds/fragile-rich/necrotic/splitter-surge) applied per wave,
  `WaveAnnouncer` banners, `DirectorHud`, endless scaling (`EndlessScaling`).
- **Run flow** — `RunTimer`, `PauseManager` (pause + settings-from-pause), `GameOverFlow`
  (summary + best-score fanfare), `SettingsPanel` (volumes, motion, remapping),
  `InputRemapper` (persisted bindings), `TutorialManager` (first-run coach).
- **Meta game** — `MetaProgression` wallet + 5 upgrade tracks (vitality/power/swift/focus/
  fortune) applied at run start; `Achievements` (12 achievements, persistent);
  `DailyChallenge` (seeded daily modifier); `RunHistory` (last-20 runs + aggregates).
- **Audio/UI/juice** — `MusicManager` (menu/calm/battle/intensity layers),
  `ArenaAmbience`, damage vignette + low-HP pulse, upgrade/level-up toasts, arena intro
  cards, boss HP bar, compass objective marker, touch controls (stick + buttons).
- **Debug tooling** — `DebugConsole` (`give/killall/god/wave/skill/wpn` commands),
  `PerformanceMonitor` (auto quality scaling), `SaveInspector`, `BalanceReport`.
- **Unit tests** — 8 new suites (`test_rng_tables`, `test_weapons`, `test_status_skills`,
  `test_area_combat`, `test_drops_elites`, `test_director_mutators`, `test_meta_misc`,
  `test_planner_extended`); 200+ new assertions, all autoload-independent.

### Changed
- `EnemyBase` integrates `StatusManager` (stun pauses AI, slow scales motion);
  `SpawnManager` supports elites/affixes/telegraphs and composition overrides;
  `WaveManager`/`WavePlanner` apply mutators + endless scaling + spillover queue.
- `SaveManager` schema 3: tutorial completion, achievements, meta wallet/ranks.
- `SettingsData` gained getters; `HealthComponent` gained `get_max()`;
  `ProgressionComponent` accepts `skill_cooldown_multiplier` + `add_permanent_bonus()`.
- `Main` builds per-run systems (projectiles, pickups, hitstop, perf, decor, hazards)
  and persistent directors (music, achievements, meta, tutorial).
- New `skill_1/2/3` input actions (Q/E/R + joypad shoulder/trigger).

## [0.4.0] — Phase 4 · Data-driven progression & upgrade loop

### Added
- **Real upgrade library** under `data/upgrades/` — 10 `UpgradeConfig` resources
  (`vitality`, `swift`, `power`, `haste`, `fortified`, `hunter`, `reach`, `force`,
  `scavenger`, `bloodlust`), auto-discovered and validated by `ContentRegistry`.
- **Deterministic upgrade selection** — new `UpgradeSelector` seeds a local RNG from
  `(run_seed, wave)`; returns exactly 3 valid choices (fewer when the pool is smaller),
  never duplicates, and respects disabled / unlock_wave / prerequisites / exclusions /
  max-stacks / weight. It never touches the global RNG.
- **GameRoot progression commands** — `present_upgrade_selection_for_wave()` and
  `request_upgrade_selection()` on the canonical state machine
  (`PLAYING → WAVE_TRANSITION → UPGRADE_SELECTION → PLAYING`). Only offered + still-legal
  ids can be selected; arbitrary ids are rejected.
- **WaveManager upgrade integration** — after a wave whose config sets
  `upgrade_after_completion`, the next wave is held until a valid upgrade is selected;
  otherwise waves continue through the normal inter-wave transition.
- **Explicit modifier semantics** (documented in `docs/EXTENDING.md`): multiplicative
  `base*(1+Σ)`, additive `base+Σ`, cooldown `base*(1+Σ)` with negative = reduction (clamped
  `>=0.05`), resistance clamped `[0,1]`.
- **Modifier → gameplay wiring**: max HP (with full-HP top-up 100→120), move speed,
  attack damage, attack cooldown, damage resistance, attack range, knockback, score /
  currency multipliers, and heal-on-kill all now change real behaviour.
- **Upgrade UI** — real selection cards (interactive buttons) with rarity colouring, stack
  counts, selection locking, and an applied-effect toast that respects reduced-motion.
- **Real dodge** with temporary invulnerability, burst movement, camera-relative direction,
  arena clamp and a proper cooldown.
- **Combo completion** — decays to 0 after a no-kill window, tracked in the run summary;
  no increase after death.
- **Authoritative spawn/wave accounting** — `SpawnManager` tracks planned/spawned/pending /
  active/defeated/failed explicitly; a failed spawn is retried up to a bound and counted as
  failed (never as a defeat) so it can't under-fill or falsely complete a wave.
- **`EventBus.enemy_damaged`** now emitted exactly once per accepted enemy damage.
- **Tests** — new headless suites `test_upgrades`, `test_upgrade_selection`,
  `test_progression`, `test_combo`; all existing + new suites pass in CI.

### Changed
- `ProgressionComponent` is the runtime source of truth; `RunState.selected_upgrades` /
  `active_modifiers` are a serializable mirror kept in sync by GameRoot.
- Fixes an existing UI bug where `_sync_from_state()` only ran once in `_ready`, so panels
  (HUD / pause / game-over / upgrade) never switched on state change.

### Notes / limitations
- Visual assets remain primitive Godot primitives; no external art/audio was introduced
  in this phase (none with verified licensing were sourced). Optional audio cues degrade
  gracefully to silence. See the Phase 4 report.

## [0.3.2] — Fix: Android APK export green in CI (build template + export-time compile)

### Fixed
- **Android build template installed into the project.** Godot's Gradle Android export
  (`gradle_build/use_gradle_build=true`) needs the Android build *source* template in the
  project, not just the runtime export templates in the user data dir. New
  `scripts/install_android_build_template.sh` mirrors Godot's own installer: it unzips
  `android_source.zip` into `res://android/build`, writes an empty `.gdignore`, writes the
  template identifier into `res://android/.build_version`, and restores the Unix
  executable bit on `gradlew` (Python's `zipfile` does not preserve exec bits, which
  caused `android/build/gradlew: Permission denied`). `docs/BUILD.md` documents it.
- **CI setup.** The `build-android` job now (1) installs runtime export templates
  canonically via `chickensoft-games/setup-godot` (`include-templates: true`) and verifies
  them with the idempotent `scripts/install_export_templates.sh`, (2) adds a Temurin
  JDK 17 (Godot's Gradle build needs a JDK), (3) installs the Android build template into
  the project, and (4) captures/annotates Godot export output for diagnosability.
- **Export-time GDScript compile errors fixed.** Android export compiles every script,
  which the headless unit runner/import do not, exposing latent problems now resolved:
  `targeting_component.gd` renamed `set_owner()` → `bind_owner()` (it overrode
  `Node.set_owner`); explicit types added in `character_controller.gd`, `attack_controller.gd`,
  `spawn_manager.gd` and `ui_root.gd` (Variant-inferred locals); `DisplayServer.FEATURE_HAPTICS`
  removed in `player_feedback.gd` / `touch_action_button.gd` (removed from the engine in 4.3+).
- **Result.** `.github/workflows/android.yml` `build-android` job is green end-to-end:
  headless unit tests, resource/asset validation, **`godot --export-debug "Android"`** and the
  non-empty-APK check all pass; the debug APK is uploaded as the `LastStandArena-android`
  artifact (milestone validation artifact). The Android build toolchain is not reachable
  from the authoring sandbox, so this was verified by running the real GitHub Actions CI.

## [0.3.1] — Fix: CI Android export templates not installed

### Fixed
- The CI "Install matching Android export templates" step could exit 0 without actually
  placing any templates (no `set -e`, silent `curl`/`unzip`/`cp` failures), so the later
  `godot --export-debug "Android"` step failed with *"Android build template not
  installed in the project"*. The install logic is now a shared, strict script
  `scripts/install_export_templates.sh` (used by both the `build-android` and
  `publish-release` jobs) that downloads with `curl --fail`, extracts with Python's
  `zipfile`, copies into `~/.local/share/godot/export_templates/<version-string>/`
  (dot before `stable`, e.g. `4.4.1.stable`), and fails loudly unless
  `android_debug.apk`, `android_release.apk` and `android_source.zip` are present.
- `docs/BUILD.md` documents the script and adds a troubleshooting entry for the
  "Android build template not installed" export error.

## [0.3.0] — Phase 3 · Integrated run loop (menu → waves → game over)

### Added (Phase 3)
- **Enemy AI state machine** (`EnemyStateMachine` + `EnemyState` base and concrete
  `Idle`/`Chase`/`Attack`/`Hurt`/`Dead` states). Lightweight `RefCounted` states mutate
  the host `EnemyBase` only through its public command surface and request transitions
  via `change_to()`; every route funnels through one `change_to()` so lifecycle and
  bookkeeping stay in one place.
- **EnemyBase movement + behaviour host**: real `CharacterBody3D` movement (desired
  dir/speed, gravity, navigation-aware steering via a `NavigationAgent3D`, decay + stuck
  recovery for knockback, arena-bounds clamping) driven by the state machine in
  `_physics_process`. Preserves the Phase 2 command API and the exactly-once death /
  `enemy_killed` / score guarantees. Adds `set_bounds`, `apply_difficulty`,
  `get_effective_speed/damage`, `perform_enemy_attack()` (one-queried melee through the
  player `HealthComponent`), `get_navigation_direction`, and a debug snapshot.
- **Two new archetypes**: `fast` ("Stinger", low HP / fast / short cooldown) and
  `heavy` ("Brute", high HP & damage / slow / high knockback resistance / long
  windup+cooldown), added to `data/enemies/` + `scenes/enemies/` and auto-discovered by
  `ContentRegistry`.
- **SpawnManager** (`scripts/enemies/spawn_manager.gd` + scene): owns flattened spawn
  queues, seeded deterministic point pick, max-simultaneous cap, pacing timer, active
  enemy registration/removal, `all_cleared` detection and run-end AI deactivation. Does
  NOT own score/waves.
- **WavePlanner** (`scripts/waves/wave_planner.gd`): pure deterministic composition
  table, `WaveConfig` builder and difficulty scalars for waves 1..N.
- **WaveManager** (`scripts/waves/wave_manager.gd`): drives `WavePlanner`, feeds
  rollouts + difficulty to the `SpawnManager`, listens for `enemy_spawned` /
  `all_cleared`, and moves through the GameRoot state machine for clean inter-wave
  transitions. Completion bonuses are announced via `EventBus.wave_completed` and scored
  centrally by GameRoot (exactly once) — WaveManager never owns score/saves/upgrades.
- **Main composition**: builds/tears down the world (arena + player + camera +
  `EnemyContainer` + SpawnManager + WaveManager) under `WorldRoot`, starts the wave
  director on `PLAYING`, deactivates AI and stops the director on `GAME_OVER`/`MAIN_MENU`.
- **GameRoot run hooks**: `record_current_wave`, `award_wave_completion_bonus`,
  `begin_wave_transition` / `end_wave_transition`, and elapsed-run-time tracking —
  keeping scoring/wave accounting centralized and exactly-once.
- **Headless unit suite** `tests/unit/test_waves.gd`: WavePlanner determinism / counts /
  scaling and validation of the three real archetype `.tres` resources.
- **TestHarness smoke** items for the Phase 3 loop (`enemy_spawns`, `enemy_takes_damage`,
  `enemy_dies`, `score_increases`, `wave_progresses`) flipped to deterministic green
  checks.

### Fixed / Notes
- Added `EnemyBase.state_machine_change_to()` facade (states were calling it but it was
  missing).
- `gdlintrc`: `max-public-methods` disabled because `EnemyBase` intentionally exposes
  >20 public methods.
- Deterministic arena navigation floor (flat convex `NavigationMesh`, no runtime baking)
  and bounds/min-spawn-distance APIs on `Arena`.
- Remaining known limitation: full menu→wave→game-over play-through and APK artifact are
  verified via Godot user runs and GitHub Actions (no Godot binary is reachable in this
  sandbox).

## [0.2.1] — Fix: Godot 4.4 compile errors (parse / type-inference)

### Fixed
- `save_manager.gd`: renamed the static `_get(...)` helper to `_dict_get(...)` — it
  collided with `Object._get(StringName)`, breaking the whole script ("function
  signature doesn't match the parent"). Declared `raw`/`previous` (read from
  `_read_raw`, which returns Variant) as explicit `Variant` instead of `:=`.
- Tests: replaced `var X := load(...).new()` with direct references to the registered
  `class_name` types (`DamagePayload`, `DamageResult`, `HealthComponent`,
  `CombatQuery`, `Scoring`, `EnemyConfig`, etc.) so `.new()` is statically typed and
  no longer triggers "cannot infer the type" / "inferred from a Variant value" errors.
- Added `class_name` to the `FakeClock` and `FakeSaveStorage` test doubles.
- `combat_query.gd`, `targeting_component.gd`, `character_controller.gd`: removed
  ternaries whose branches produced a Variant (`t is Node3D`, `c is Node3D`,
  `get_camera_3d() if ...`) that would fail type inference when those scripts load.

These were latent in Phases 1-2 and surfaced on the first real
`godot --headless --path . --script res://tests/run_tests.gd` run.
All notable changes are tracked per implementation phase.

## [0.2.0] — Phase 2 · Combat + first enemy (in progress)

### Added (Phase 2)
- **Combat query layer** (`scripts/combat/combat_query.gd`): pure, deterministic arc/
  range hit selection for melee swings (headless unit-testable).
- **Melee hit resolution** in `AttackController`: telegraph (`windup`) → arc query over
  the `enemies` group → validated `DamagePayload` → apply → `attack_hit`, with crit
  chance, knockback, and damage/range derived through the player `ProgressionComponent`.
- **Enemy base** (`EnemyBase` CharacterBody3D + scene): lifecycle, `initialize(config,
  target, seed)`, damage intake, idempotent death, exactly-once `enemy_killed` score
  payload, knockback seam, tinting via config.
- **Basic enemy archetype**: `basic_enemy.tscn` + `data/enemies/basic_enemy.tres`
  (`archetype_id = "basic"`, "Grunt").
- Enemy **feedback** (hit flash, death sink/fade, recolour) and **audio** wrappers.
- **GameRoot combat scoring**: on `enemy_killed` updates kills/combo/score/currency
  with score-multiplier from upgrades, emits `score_changed` / `currency_changed` /
  `combo_changed` exactly once per kill.
- Reused `HealthComponent` for enemies (damage, invulnerability, death).
- Deterministic **combat integration tests** in `tests/run_tests.gd` (damage,
  invalid payload rejection, invulnerability, heal cap, single death, arc query).
- CI: `publish-release` job builds + uploads the APK to a GitHub Release on tag/manual
  dispatch; `scripts/build_android.sh` supports `BUILD_TYPE=debug|release`.

### Verification status (Phase 2)
- GDScript static lint (`gdlint`): **passes** for scripts + tests.
- `.tscn`/`.tres` structural validation: **passes** (10 scene/resource files).
- Cross-reference audit: **clean**.
- Headless test execution + Android APK export: still **not runnable in the authoring
  sandbox** (no Godot/Android toolchain); wired into CI + build script for a real
  runner/local machine.

## [0.1.0] — Phase 1 · Foundation

Working title: **Last Stand: Arena**.

### Added (Phase 1)
- Godot 4.4 project configuration: `project.godot` with mobile renderer, landscape
  display/orientation, physics layers, and keyboard/controller InputMap actions.
- Canonical autoloads registered: `GameRoot`, `EventBus`, `AudioManager`,
  `SaveManager`, `SceneRouter`, `ContentRegistry`, `RunAnalytics`, `TestHarness`.
- Canonical main scene tree (`scenes/main/main.tscn`) + composition controller that
  builds/tears down the gameplay world.
- GameRoot state machine with documented legal transitions and a narrow command API.
- EventBus cross-system signal contract (per design).
- Content registry foundation with typed enemy/upgrade/arena/camera/weapon/audio data
  discovery + validation; default arena + camera `.tres` shipped.
- Player: CharacterBody3D movement (character controller), health component,
  attack/targeting/progression/feedback/audio components, stable command interface.
- Camera rig: data-driven profile follow camera with clip guard + bounded shake.
- Arena scene with floor/walls/collision, player-start + grouped enemy spawn markers,
  pickup points, lighting + environment.
- Basic UI shell: main menu, HUD (health/score/wave/combo/currency), pause, game over,
  settings, upgrade placeholder; floating virtual joystick + attack/dodge buttons;
  localization-ready text lookup.
- Save system: versioned schema v2, pure `normalize_save`, migration hooks, corruption
  recovery, backup + debounced atomic writes.
- Local-only run analytics.
- Headless test runner (`tests/run_tests.gd`) + unit suites (save, combat payloads,
  content validation, scoring) + test doubles (FakeClock, FakeSaveStorage).
- `TestHarness` smoke-test interface.
- Validation tooling (`tool/validate_resources.py`), build script
  (`scripts/build_android.sh`), asset downloader (`scripts/download_assets.py`),
  Android export preset, GitHub Actions `android.yml` CI.
- Documentation: README, `docs/BUILD.md`, `docs/ART_STYLE.md`, `docs/EXTENDING.md`,
  `THIRD_PARTY_ASSETS.md`, `AUDIO_MANIFEST.md`, `gdlintrc`.

### Not yet implemented (later phases)
- Combat/hitboxes, enemy AI + states, spawn manager, procedural waves (Phases 2–3).
- Enemy archetype scenes/data, run upgrade/selection loop, full scoring/combo wiring
  (Phase 4).
- Full audio assets, VFX, menus polish (Phase 5).
- Content unlocks, run summary polish (Phase 6).
- Optimization/pooling/profile + verified Android export + CI green on a real runner
  (Phases 7–8).

### Verification status (Phase 1)
- GDScript static lint (`gdlint`): **passes** (scripts + tests).
- Hand-authored `.tscn`/`.tres` structural validation (`tool/validate_resources.py`):
  **passes**.
- Headless unit tests + Android APK export: **not run in the authoring sandbox** (no
  Godot/Android toolchain available); wired into `.github/workflows/android.yml` and
  `scripts/build_android.sh` for execution on a real runner / locally. See the
  "known limitation" note in the Phase 1 commit message.
