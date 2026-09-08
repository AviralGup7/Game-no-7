# Changelog

## [Unreleased] — Enemy/encounter ecosystem pass (Agent 2, 2026-09-08)

- **Roster models + animations integrated**: every archetype mounts its catalogued
  model via the new `EnemyAnimator` (ModelVisual fitting, untouched physics), with
  idle/run loops, windup-scaled attack clips, hurt and death one-shots
  (Skeleton Minion/Rogue/Warrior/Mage, Rat, Spider, Demon, BlueDemon).
- **Distinct combat identities**: Dashers telegraph a straight-line charge with a
  single contact hit and a vulnerable recovery (new `EnemyDashState`); Exploders
  plant and blink inside fuse range before self-detonating through the normal
  exactly-once death path (new `EnemyFuseState`); Fast skirmishers back-pedal after
  each sting; Heavies/Bosses gained poise so telegraphed swings are not
  perma-staggered; melee windups now abort cleanly when the target escapes.
- **Ranged polish**: kiting when crowded, windup telegraphs (flash + sound), and
  target-leading volleys through the existing ProjectilePool.
- **Splitter burst**: children burst around the parent's death position with
  outward scatter and extend the SpawnLedger plan (`register_direct_spawn`), with a
  queue fallback when direct spawning is impossible — accounting stays exact.
- **Boss encounter**: warlord phases authored as `BossPhaseConfig` resources on the
  BossController node; deterministic (run-seeded) ability picks; real telegraphs,
  travelling charge, recovery windows and a phase-transition stagger; UI stays
  event-driven through the existing `boss_spawned`/`boss_phase_changed` contracts.
- **Elite affix behavior completed**: VAMPIRIC heals from damage dealt, FRENZIED
  attacks faster below half health (both via EnemyBase hooks, configs untouched).
- **Spawn/anti-overlap**: opening burst pacing, deterministic per-marker jitter,
  per-enemy approach offsets (fan-out), and enemy/enemy collision so packs cannot
  stack in one body.
- **Feedback/audio**: telegraph flash, longer death window for death animations,
  and three new CC0 synthesized cues (`enemy_windup`, `enemy_dash`,
  `enemy_explosion`) auto-registered from `data/audio/`.
- **Robustness**: enemy scripts resolve EventBus/AudioManager through the tree
  (null-safe under the bare headless harness), unblocking real enemy integration
  tests; fixed a duplicate-member block in `enemy_config.gd`.
- **Tests**: new `test_enemy_behaviors.gd` unit suite (ledger direct-spawn
  accounting, boss phase math, phase/config validation) plus the
  `_run_enemy_encounter_integration` section in `run_tests.gd` covering state
  transitions, attack timing/whiff, poise, dash, fuse, ranged kiting, vampiric /
  frenzied hooks, boss phases + deterministic abilities, and the full SpawnManager
  wave cycle (burst, failed-spawn distinction, splitter bursts, no false clears).

## [Unreleased] — Asset audit and medium-detail upgrade (2026-09-08)

- Verify all 191 prior downloads; add 31 licensed/locked files (~10.30 MiB),
  including 23 models and detailed stone maps. Total: 222 files, 81 models.
- Cover all current character, weapon, pickup, skill and arena roles in the catalogue.
- Replace live flat arena materials and identical pickup prisms; retain physics,
  collection rules and missing-art fallback. Character/equipment integration pending.
- Validate complete content-ID coverage, runtime source references and shared
  licence notices; add material/model import checks and normalization tests.
- Document upstream upgrade decisions and remaining integration in ASSET_AUDIT.md.


## [Unreleased] — Arena build-out · weapons, skills, arenas, enemies, meta

### Release engineering
- **v0.4.0 published** (2026-09-08) — first release via the tag-push path; CI run
  #34171607635 built, tested and attached `LastStandArena-debug.apk` (ARM64,
  debug-signed) + `SHA256SUMS.txt` to the Release.
- Workflow now also triggers on **`release: published`**, so creating a Release in
  the GitHub UI runs the full build + publish pipeline (previously only tag pushes
  or manual dispatch did — and manual dispatch needs elevated token permissions).
- New `scripts/release.sh vX.Y.Z`: one-command, guardrailed release (refuses dirty
  trees, duplicate tags, and version drift between the tag, `export_presets.cfg`
  `version/name`, and the CHANGELOG; then pushes the tag for CI to publish).

### Added
- **Data-driven weapon loadout** — `WeaponConfig` resources (`data/weapons/`, 6 shipped:
  gladius, sentinel_spear, stormhammer, sunbow, twinfangs, warreaxe) auto-discovered by
  `ContentRegistry`; `WeaponManager` owns the 2-slot loadout + cooldowns + switching
  (Tab / gamepad Y / touch button), `MeleeResolver` scores arc hits, `ProjectilePool`
  serves pooled projectiles for volleys and enemy ranged attacks.
- **Active skills + status effects** — `SkillConfig` resources (`data/skills/`, 5 shipped:
  bladestorm, frost_nova, phantom_rush, seismic_slam, warcry), `SkillController`
  (charges/cooldowns, Q/E/R + tappable HUD skill bar), `StatusManager` (bleed/burn/
  guard/regen/shock/slow/stun/warcry with refresh/stack rules), `AreaDamage` helper.
- **2 new arenas** — `ember_crucible` + `frost_hollow` configs (share the arena scene)
  with `ArenaDecorator` (deterministic props), `ArenaHazards` (floor fields),
  per-arena music cue (consulted by `MusicManager`), and unlock waves.
- **5 new enemies** — dasher, exploder, ranged, splitter (spawns fast mites on death),
  warlord (3-phase boss via `BossController`); stun gating + slow scaling in `EnemyBase`,
  elite affixes (`EnemyEliteAffix`), hit-flash/death-sink juice via `EnemyFeedback`.
- **Combat depth** — `RunScorekeeper` combo (4s window, score events, kill feed in
  `CombatLog`), `DamageNumberLayer` crit popups, `HitstopManager` (hitstop + trauma
  shake), `PickupManager` (6 drops: antidote/coin_cache/health_orb/magnet_core/
  stamina_brew/xp_gem).
- **Wave director** — 7 static mutators (`WaveMutators`: swift_horde/iron_hide/
  elite_surge/glass_cannon/bounty_hunt/volatile_mix/ember_winds) resolved per wave,
  wave + mutator banner announcements, adaptive `DifficultyDirector`, endless planner
  scaling.
- **Run flow** — pause overlay + settings-from-pause, game-over run summary,
  `SettingsPanel` (volumes, mute, motion, vibration, contrast, FPS cap, quality tier,
  persisted remapping via `InputRemapper`), `TutorialManager` first-run coach speaking
  through the HUD announcement banner.
- **Meta game** — `MetaProgression` wallet (banks half the run currency) + 8-item armory
  (5 stat tracks, 2 weapon unlocks, Bladestorm manual) with a spendable `ArmoryPanel`
  shop; `Achievements` (19 achievements, persistent); playable `DailyChallenge` (shared
  daily seed, fixed mutators + starter weapon).
- **Audio** — `MusicManager` (menu/calm/battle/battle/boss/victory states, heat-driven
  intensity layers, crossfades); `ProceduralSfx` synthesizes every referenced cue
  (10 SFX + 5 music beds) so the game is never silent — real drops in `data/audio/`
  (`.tres`/`.ogg`/`.wav`/`.mp3`) always take precedence.
- **HUD/widgets** — skill bar, tactical minimap, boss HP frame, announcement banner,
  damage numbers, combat-event kill feed, armory + daily-challenge menu entries.
- **Debug tooling** — `PerformanceMonitor` (rolling FPS + auto quality scaling, feeds
  the damage-number budget).
- **Unit tests** — 9 new suites (`test_rng_tables`, `test_weapons`, `test_status_skills`,
  `test_area_combat`, `test_drops_elites`, `test_director_mutators`, `test_meta_misc`,
  `test_planner_extended`, `test_procedural_sfx`); ~200 checked assertions, all
  autoload-independent.

### Changed
- `EnemyBase` integrates `StatusManager` (stun pauses AI, slow scales motion);
  `SpawnManager` supports elites/affixes and wave-modifier scaling (hp/damage/speed/
  score/elite/explosive); `WaveManager`/`WavePlanner` apply mutators + endless scaling.
- `SaveManager` schema 3: tutorial completion, achievements, meta wallet/ranks.
- `SettingsData` gained getters; `HealthComponent` gained `get_max()`;
  `ProgressionComponent` accepts `skill_cooldown_multiplier` + `add_permanent_bonus()`.
- `Main` builds per-run systems (projectiles, pickups, hitstop, perf, decor, hazards)
  and persistent directors (music, achievements, meta, tutorial).
- New `skill_1/2/3` input actions (Q/E/R + joypad shoulder/trigger).

### Fixed (audit + fix pass)
- Pause soft-lock: `PAUSED` had no outgoing transitions, so resume/restart/menu
  from pause were rejected; added `PAUSED` transitions and made `GameRoot`
  process while paused so the keyboard toggle works (UI already ran always).
- Splitter wave-stall: children extending the plan after the pacing timer stopped
  left the wave unwinnable; the timer restarts when the plan extends (same guard
  for boss summons).
- Enemies were immune to slows/stuns: `enemy_base.tscn` lacked the `StatusManager`
  node the warlord already had; added (auto-binds health).
- Boss summons never spawned (`summon_requested` unwired); the spawner now extends
  the plan on summon. New `boss_slain` signal resets boss music to battle.
- Payload status riders never applied: `apply_damage` on player/enemy now forwards
  `payload.status_effects` to the local `StatusManager`.
- Silent cues wired: pickup collection + enemy spawn sounds; level-ups announce on
  the banner; the adaptive director now receives player-damage events.
- Hitstop/trauma never triggered: crits/deaths now pulse the `HitstopManager`.
- Camera shake permanently drifted the lens; base position is captured + restored,
  reduced-motion initializes from save, and arena camera profiles apply at build.
- Arena validation errors surface at startup; save flushes on quit request.
- Touch buttons work with mouse (desktop parity) and draw centered; HUD seeds from
  the live run so fresh runs never render stale widgets; `reload_finished` forwards
  from weapon instances; `AUDIO_MANIFEST.md`/README status updated.

### Modularized
- Split the 10 largest scripts into focused modules (public APIs unchanged):
  `ui_root` → `UiText` + `UiFactory` + `GameHud` + `UpgradePanel` (658→363);
  `player` → `PlayerLocomotion` + `PlayerBuild` (617→489);
  `enemy_base` → `EnemyLocomotion` + `EnemyNavigator` + `EnemyStriker` (548→392);
  `spawn_manager` → `SpawnLedger` + `SpawnPlacer` (466→353);
  `game_root` → `RunScorekeeper` + `UpgradeService` (442→359);
  `skill_controller` → `SkillExecutor` (398→200);
  `save_manager` → `SaveSchema` (352→241);
  `attack_controller` → `ComboChain` (321→298);
  `content_registry` → `ContentLoader` (310→210);
  mutator resolution → `WaveMutators.resolve_for_wave` (317→305).
- `DamagePayload.with_amount()` clone helper (mitigation/shield pipelines).
- New `test_extracted_modules` suite (ComboChain/SpawnLedger/SaveSchema/UiText/payload).
- Fixed: `ContentRegistry.refresh_all()` now rebuilds fresh tables, so repeated
  refresh/validate no longer reports every id as a false duplicate.

## [Unreleased] — 2026-09-07 · Core 3D asset kit

### Added
- **178 downloaded asset files + 13 preserved source notices (24.75 MiB):**
  4 rigged KayKit characters with embedded animation libraries, 11 weapon/shield
  models with their buffers/textures, 37 arena models, 6 pickup models, 15 particle
  textures, 55 UI/upgrade images, 2 Rajdhani fonts, 29 SFX and 2 Ogg music loops.
- **Asset catalogue** (`docs/ASSET_CATALOG.md`, `assets/catalog.json`) mapping the
  player, Basic/Fast/Heavy enemies, all 10 upgrades, effects, props and audio cues
  to actual downloaded files. Exact clip names and integration notes included.
- **Per-file source lock** (`assets/manifest.json`): reviewed creator/licence,
  immutable source commit, exact download URL, original/local path, size, SHA-256
  and acquisition date. Updated visual/audio manifests and stored licence notices.
- **Offline format/dependency/coverage validation**, 28 Python tests, optional
  Khronos glTF validation, and a native Godot import smoke test for CI/builds.

### Changed
- Replaced the empty downloader scaffold with an approved-source-only restorer:
  mandatory size/hash checks, read-only `--verify`, explicit `--repair`, safe paths,
  atomic writes and pack selection. No credentials or runtime downloads required.
- Android export presets retain asset/font licence notices. `.gitattributes`
  prevents line-ending conversion from invalidating source checksums.
- Build/CI paths verify assets and exercise native Godot resource imports.

### Scope / validation
- **Downloads only, not an art/gameplay integration milestone.** Live character,
  arena, UI and audio wiring remain unchanged. No combat/camera/progression changes.
- 191 file checks, 28 Python tests and 25 existing resource structural checks pass.
  All 58 models pass Khronos validation with 0 errors; 32 upstream skinned-hierarchy
  warnings are documented. All 31 audio files decode and contain sound.
- Godot/Android execution was unavailable locally (engine not installed; release
  download host unreachable). Native import checks were added but not run here.

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
