# Game Forensic Audit — Last Stand: Arena
### Repository, Gameplay, Architecture & Release Readiness

**Audit date:** 2026-09-10
**Auditor:** Arena.ai Agent Mode (senior game-engineering / design / QA / release audit role)
**Branch under audit:** `arena/01a08d65-game-no-7` (HEAD `4df8a724c4099bda0f2f6fb62674773666b2c8ed`, merge of PR #48)
**Mode:** Read-only source & repository audit. No execution, no provisioning, no file modifications to the project.

---

```text
NOT RUNTIME VERIFIED
Reason: Application execution is prohibited for this source-code review.
Unavailable evidence: Runtime behavior, actual frame rate, device behavior, input feel, scene execution, crash behavior, and player experience.
Static checks still possible: Source parsing, resource references, scene structure, configuration, call graphs, data flow, tests, CI, build scripts, and existing artifacts.
Evidence required for runtime-dependent conclusions: Authorized runtime session, build artifact, profiler capture, device/emulator result, or automated runtime-test artifact.
```

> **Terminology note (applied throughout):** "Runtime evidence" in this report refers to *on-device / on-GPU interactive execution* (touch feel, FPS, crash behavior, player experience). Headless engine execution of the test suite (Godot `--headless --script`) is **non-device automated test evidence**, not device-runtime evidence, and is cited separately and never conflated with device behavior. The absence of a device run is **not** a defect, problem, failure, weakness, or score reduction anywhere in this report.

---

## Required Setup Record

```text
Godot required version:      4.4.1-stable (pinned in docs/BUILD.md and .github/workflows/android.yml env GODOT_VERSION)
Godot detected:              NO
Godot version:               none installed in sandbox (`godot` not found; `which godot` → empty)
Installation/provisioning attempted: NO
Installation/provisioning result:   n/a — provisioning is out of scope and prohibited
Installation/provisioning evidence:  none
CI results inspected:        YES — `gh run list` + `gh run view 34534947513` (head SHA 4df8a72). Conclusion: success.
Tests intentionally not rerun: YES — test execution is prohibited by audit scope.
Stress tests intentionally deferred: YES — soak/stress/load tests deferred by scope.
Application execution intentionally not performed: YES
Reason for deferral:         Audit scope prohibits launch/run/test/profiling/emulator use.
Commands/tools attempted:    bash (find, wc, grep, sed, cat, du, ls), git (status, log), gh (auth status, run list, run view). All read-only.
Environment changed:         NO
```

---

# Phase 1 — Scope and Evidence Availability

```text
Project:                 Last Stand: Arena
Repository root:         /home/user/Game-no-7
Engine/version:          Godot 4.4.1-stable (GDScript); CI also cross-checks on 4.7.2-stable
Target platforms:        Android (arm64-v8a) primary; desktop editor run for development
Intended game:           Third-person arena survival / action (waves, melee+ranged combat, upgrades, roguelite meta)
Declared entry point:    res://scenes/main/main.tscn (project.godot run/main_scene)
Available tools:         bash, git, gh, python3 (3.11). Godot: NOT available.
Build artifacts:         None checked in (build/ is gitignored). CI produces LastStandArena-debug.apk.
Runtime targets:         None available locally. Headless CI runs exist as historical evidence.
Profiler/logging:        docs/godot-runs/*.log (committed), session.log (runtime), performance monitor (source)
Tests:                   65 Python test files (908 test methods, static count), 46 GDScript unit suites + 10 node suites + integration stages, UI suite, hero runtime script
CI status/jobs:          Green on HEAD. Jobs: validate-resources, godot-tests, build-android (all success); publish-release skipped.
Audit date:              2026-09-10
Auditor:                 Arena.ai Agent Mode
Application execution:   PROHIBITED
```

## Evidence Ledger

| ID | Source | Type | Claim/observation | Status | Confidence |
|---|---|---|---|---|---|
| E-001 | `.github/workflows/android.yml` | Config/CI | 3-stage pipeline (validate-resources → godot-tests → build-android) + publish-release on tags/release/dispatch | Verified | High |
| E-002 | `gh run view 34534947513` | CI result | On HEAD `4df8a72`, all 3 jobs success; APK "exists and is non-zero"; publish skipped | Verified | High |
| E-003 | `docs/godot-runs/run_tests.log` | Runtime artifact (historical) | Godot 4.4.1 headless: "GDScript tests: 640 total, 0 failed" | Verified | High |
| E-004 | `docs/godot-runs/diagnostics-4.7.2-tests.log` / `-wae-tests.log` | Runtime artifact (historical) | Godot 4.7.2 headless: "GDScript tests: 1095 total, 0 failed"; 0 SCRIPT ERROR | Verified | High |
| E-005 | `docs/godot-runs/diagnostics-fix-report.md` | Prior report (claim) | 4.7.2 analyzer: 172→43→0 warnings, 0 errors; parse errors (VirtualJoystick) found+fixed | Verified (corroborated by E-004) | High |
| E-006 | `tests/python/*` | Source | 65 files, 908 test methods (static `def test_` count) | Verified | High |
| E-007 | `project.godot` | Config | Main scene, 9 autoloads (ordered), input map, mobile renderer, 60 Hz physics, interpolation, landscape | Verified | High |
| E-008 | `export_presets.cfg` | Config | Android preset: arm64-v8a, package com.laststandarena.game, version 0.6.0 / code 3 | Verified | High |
| E-009 | `docs/godot-runs/run_tests.log` | Runtime artifact (historical) | Non-fatal warnings: primitive visual fallback (test fixtures), ObjectDB leak at exit, "Parse JSON failed … got 'not'", ghost negative-test noise | Verified | High |
| E-010 | `docs/godot-runs/diagnostics-4.7.2-summary.txt` | Runtime artifact (historical) | 66× "Parameter data.tree is null" (status_manager via test_status_skills), 4.7.2 run | Verified | High |
| E-011 | `scripts/…` (197 files) | Source | Typed component architecture; no `has_method()`/`.call()` string dispatch | Verified | High |
| E-012 | `data/…` | Source/data | 8 enemies, 38 upgrades, 9 weapons, 8 skills, 13 status, 7 pickups, 7 mutators, 3 arenas, 7 game modes, 6 waves | Verified | High |
| E-013 | `assets/manifest.json` | Data | 96 models, 94 textures, 34 audio, 2 fonts (~56 MiB), checksum-locked | Verified | High |
| E-014 | `CHANGELOG.md`, `README.md`, docs/* | Documentation (claims) | Feature claims; treated as claims, verified against source where material | Verified-as-claims | Medium |

## Availability / Stopping Conditions

```text
Runtime launch available:        NO — prohibited
Build available:                 YES (CI artifact; not locally)
Desktop runtime:                 NOT USED
Android runtime:                 NOT USED
Profiler:                        NO (no profiler capture available locally; PerformanceMonitor source exists)
Automated test execution:        NO — prohibited this session (CI evidence reused)
Godot available:                 NO
Godot installation/provisioning status:  not installed; provisioning not attempted
Green CI tests intentionally not rerun:  YES (reused run 34534947513 + committed logs)
Stress tests intentionally deferred:     YES
Application execution intentionally not performed: YES
Stopping conditions:             (1) No device-runtime evidence → all runtime-dependent conclusions downgraded to NOT RUNTIME VERIFIED.
                                 (2) Godot unavailable → no local re-parse/re-run; rely on committed CI logs.
                                 (3) Any claim requiring runtime stops at the static boundary and records the exact missing evidence.
```

**State asserted before continuing:** NOT RUNTIME VERIFIED.

---

# Phase 2 — Targeted Repository Reconnaissance

## Inventory

| Area | Files/resources | Entry points | Dependencies | Reachability | Status |
|---|---|---|---|---|---|
| Configuration | `project.godot`, `export_presets.cfg`, `gdlintrc`, `.editorconfig`, `.gitignore` | `run/main_scene` | engine settings | Boot | OK |
| Scenes | `scenes/main/main.tscn`, `scenes/player/player.tscn`, `scenes/enemies/*` (9), `scenes/arena/arena.tscn`, `scenes/ui/ui_root.tscn`, `scenes/main/camera_rig.tscn` | `main.tscn` | scripts, data, assets | Full tree | OK |
| Core/state | `scripts/core/game_root.gd` (605), `event_bus.gd`, `run_state.gd`, `scene_router.gd`, `content_registry.gd`, `run_scorekeeper.gd`, `upgrade_service.gd` | 9 autoloads | SaveManager, ContentRegistry | Boot→run | OK |
| Gameplay | `scripts/player/*` (17), `scripts/weapons/*` (7), `scripts/combat/*` (9), `scripts/status/*`, `scripts/skills/*` | `player.tscn` | HealthComponent, WeaponManager, StatusManager | In-run | OK |
| Enemies | `scripts/enemies/*` (24), `scenes/enemies/*` | `spawn_manager.tscn` | EnemyConfig (.tres), nav grid, EventBus | In-run | OK |
| Waves | `scripts/waves/*` (9), `data/waves/*` | WaveManager | SpawnManager, WavePlanner, DifficultyDirector | In-run | OK |
| UI/input | `scripts/ui/*` (26), `scripts/utilities/input_remapper.gd` | `ui_root.tscn` | EventBus, GameRoot, UiLayout | Boot→all screens | OK |
| Persistence | `scripts/save/save_manager.gd`, `save_schema.gd`, `settings_data.gd` | SaveManager autoload | user:// JSON, backups | Boot + flush | OK |
| Audio | `scripts/audio/*` (6), `data/audio/*` | AudioManager autoload | ContentRegistry, settings | Boot | OK |
| Tests/CI | `tests/**` (67 .gd + 65 .py), `.github/workflows/*` (2) | `run_tests.gd`, `android.yml` | Godot 4.4.1, Python 3.11 | CI | OK |
| Android/build | `export_presets.cfg`, `scripts/build_android.sh`, `scripts/install_*`, `docs/BUILD.md` | CI `build-android` job | JDK 17, Android SDK, Gradle template | CI | OK |

Sampled/omitted: individual enemy-state scripts (representative state machine inspected via `enemy_base.gd`), full shader/material pass (asset-level detail delegated to `docs/ASSET_AUDIT.md` + `validate_assets.py`), per-panel UI bodies (navigation contract verified at `ui_root.gd`). Omitted for time; not security- or release-critical to exhaust.

## Trace (ENTRY POINT → … → PERSISTENCE)

```text
From: Boot (project.godot run/main_scene)
To:   Main (scenes/main/main.tscn → scripts/main/main.gd)
Authority: Engine scene load
Data passed: none
Initialization order: Main._ready() registers world builder with GameRoot, resolves WorldRoot/UIRoot, creates persistent directors (Music, Achievements, Meta, Tutorial, Soak)
Cleanup path: _clear_world() on MAIN_MENU
Evidence: main.gd:28-55; main.tscn node tree
Status: VERIFIED BY STATIC EVIDENCE (execution in CI import+UI suite)

From: Main (world builder)
To:   GameRoot (scripts/core/game_root.gd)
Authority: GameRoot.set_world_builder(Callable)
Data passed: Callable (typed), arena_id per run
Init order: GameRoot._ready reads SaveManager bests, binds score to RunState
Cleanup: GameRoot.set_active_player(null) on clear
Evidence: game_root.gd (state machine, LEGAL_TRANSITIONS), main.gd build_world
Status: VERIFIED BY STATIC EVIDENCE

From: GameRoot (STARTING_RUN)
To:   Arena + Player + SpawnManager + WaveManager
Authority: GameRoot._start_new_run → _call_build_world → Main.build_world
Data passed: arena_id, run_seed, mode_id
Init order: arena instantiate → player spawn (reset_for_new_run, set_bounds, control enabled) → camera → spawn/wave systems → run systems (projectiles, pickups, hitstop, perf, decorator, hazards, effects, objectives) → build effects → cosmetics → rebuild_derived_stats
Cleanup: _clear_world() frees children synchronously (immediate, not deferred — documented name-collision avoidance)
Evidence: main.gd:build_world/_create_systems/_create_run_systems; game_root.gd:_start_new_run
Status: VERIFIED BY STATIC EVIDENCE

From: GameRoot (PLAYING)
To:   WaveManager → SpawnManager → EnemyBase
Authority: WaveManager.start_run (seed) → _launch_next_wave → SpawnManager.queue_wave
Data passed: run_seed, wave_number, archetype queue, interval, max_simultaneous, folded WaveModifiers
Init order: planner → ledger reset → opening burst (≤3) → timer trickle
Cleanup: SpawnManager.clear()/deactivate_all(); ledger authoritative accounting
Evidence: wave_manager.gd, spawn_manager.gd queue_wave/_spawn_one
Status: VERIFIED BY STATIC EVIDENCE

From: EnemyBase (combat)
To:   Player HealthComponent → DamagePayload → DamageResult
Authority: EnemyStriker → Damageable.apply_damage
Data passed: DamagePayload (typed)
Evidence: enemy_base.gd (Damageable protocol), combat/damage_payload.gd
Status: VERIFIED BY STATIC EVIDENCE (combat integration suite green)

From: Wave completion
To:   GameRoot WAVE_TRANSITION → UPGRADE_SELECTION → UpgradeService → PLAYING
Authority: WaveManager completion → GameRoot.present_upgrade_selection_for_wave → request_upgrade_selection
Data passed: wave_number, chosen upgrade ids, RunState + active player
Evidence: game_root.gd (upgrade command surface), wave_manager.gd (_awaiting_upgrade guard: next wave waits for selection)
Status: VERIFIED BY STATIC EVIDENCE

From: GAME_OVER
To:   SaveManager (record_run_completed) → RunSummaryPanel → RESTART/MAIN_MENU
Authority: GameRoot._finalize_run → SaveManager → EventBus.run_ended
Data passed: run summary Dictionary
Evidence: game_root.gd:_finalize_run; save_manager.gd:record_run_completed
Status: VERIFIED BY STATIC EVIDENCE

From: Save flush
To:   user://last_stand_save.json (+3 rotating backups)
Authority: SaveManager (debounced atomic write)
Data passed: normalized schema Dictionary
Evidence: save_manager.gd (SAVE_DEBOUNCE_MSEC=1200, BACKUP_1..3, MAX_VALID_SAVE_BYTES, flush on pause/focus-loss/exit)
Status: VERIFIED BY STATIC EVIDENCE (save suite green)
```

**Deviations/duplicated authority findings:** None material. Ownership is unusually clean: score/combo/currency in `RunScorekeeper` (not GameRoot), upgrade selection in `UpgradeService`, spawn accounting in `SpawnLedger`, music in `MusicManager` (dead parallel path removed per changelog), persistence in `SaveManager` (GameRoot mirrors bests only internally and re-reads SaveManager after record). One documented residual: 4 EventBus signals are emitted but currently listener-less (`skill_unlocked`, `status_expired`, `wave_mutator_applied`, `tutorial_step_completed`) — see D-007.

---

# Phase 3 — Build and Static Integrity

| Check | Result | Evidence | Failure severity | Runtime required? | CI sufficient? |
|---|---|---|---|---|---|
| Parse/compile (4.4.1 import + tests) | PASS | CI godot-tests green; run_tests.log 640/0 (older), 4.7.2 logs 1095/0 | — | No | Yes |
| Parse/compile (4.7.2 cross-check) | PASS | diagnostics logs: 0 SCRIPT ERROR, 0/0 analyzer | — | No | Yes |
| Resource resolution (.tscn/.tres) | PASS | CI validate_resources.py; scene-path contract gate | — | No | Yes |
| Scene entry path | PASS | main.tscn → main.gd; UI suite loads screens headless | — | No | Yes |
| Signal wiring | PASS | CI check_signals.py + signal contract gate | — | No | Yes |
| Engine-API contract | PASS | CI check_engine_api.py (ClassDB manifest) | — | No | Yes |
| String-format contract | PASS | CI check_string_formats.py | — | No | Yes |
| Build/export (Android) | PASS | CI build-android job green; APK non-zero | — | No | Yes |
| Test discovery | PASS | 46 GDScript suites + 65 Python files discovered and green | — | No | Yes |
| Performance risk | UNVERIFIED | Static architecture sound (pooling, caps, governor); no profiler/device data | Medium (evidence gap) | Yes (profiling) | No |

Static validation passed on HEAD; no stopping condition triggered. Execution-dependent performance claims remain NOT RUNTIME VERIFIED.

---

# Phase 4 — Runtime Evidence Boundary

Reviewed only pre-existing artifacts. No launch, no smoke test, no device/emulator, no profiling.

```text
Build/version:               Godot 4.4.1-stable (run_tests.log); 4.7.2-stable (diagnostics logs)
Platform/device:             CI Linux runners (headless), NOT Android device
Resolution/orientation:      n/a (headless); project config = landscape, 1280×720 logical, stretch expand
Input method:                none (headless); touch/keyboard handled in source only
Existing runtime artifact:   docs/godot-runs/{run_tests.log, import.log, diagnostics-4.7.2-*.log}, CI job logs
Reason no runtime run:       prohibited by scope
Observed path:               headless unit + node integration + UI-screen + hero-clip + asset-import execution only
Logs/errors:                 see evidence ledger E-003..E-010 (all non-fatal in test context)
Crashes:                     none observed in committed logs
Unexpected state:            ObjectDB leak at exit; 2–8 resources "still in use at exit"; 66× "data.tree is null" (test-harness path)
Evidence artifact:           docs/godot-runs/ (committed)
```

## Static Traceability Model (BOOT → RESTART)

| Transition | Classification |
|---|---|
| BOOT → MENU | VERIFIED BY STATIC EVIDENCE (autoload order documented; menu panel mounted; CI boot clean) |
| MENU → MODE SELECTION | VERIFIED BY STATIC EVIDENCE (RunSetupPanel + 7 GameModeConfig .tres) |
| MODE SELECTION → RUN INIT | VERIFIED BY STATIC EVIDENCE (GameRoot.request_play_mode → STARTING_RUN) |
| RUN INIT → ARENA | VERIFIED BY STATIC EVIDENCE (Main.build_world; arena .tres + scene) |
| ARENA → SPAWN | VERIFIED BY STATIC EVIDENCE (WaveManager → SpawnManager.queue_wave) |
| SPAWN → COMBAT | VERIFIED BY STATIC EVIDENCE (combat integration suite green) |
| COMBAT → WAVE | VERIFIED BY STATIC EVIDENCE (ledger exactly-once accounting) |
| WAVE → REWARD | VERIFIED BY STATIC EVIDENCE (completion bonus routed via GameRoot) |
| REWARD → UPGRADE | VERIFIED BY STATIC EVIDENCE (UpgradeService selection, prereq/exclusion validation) |
| UPGRADE → NEXT WAVE | VERIFIED BY STATIC EVIDENCE (WaveManager waits for selection then relaunches) |
| NEXT WAVE → BOSS/OBJECTIVE | VERIFIED BY STATIC EVIDENCE (wave_10_boss.tres; ObjectiveDirector for defend/collect) |
| BOSS/OBJECTIVE → VICTORY/DEFEAT | VERIFIED BY STATIC EVIDENCE (declare_victory / player death / objective_resolved) |
| VICTORY/DEFEAT → SUMMARY | VERIFIED BY STATIC EVIDENCE (RunSummaryPanel + run_ended fan-out) |
| SUMMARY → SAVE | VERIFIED BY STATIC EVIDENCE (record_run_completed → debounced atomic flush) |
| SUMMARY → RESTART | VERIFIED BY STATIC EVIDENCE (request_restart preserves mode/daily; restart-from-any-state path) |

No transition is marked MISSING/BROKEN. All "verified" = static + headless-test evidence, not device runtime.

---

# Phase 5 — Consolidated System Audit

## 5.1 Architecture, Code & Technical Debt

**Scope/limits:** Static structure, coupling, ownership, typing, error handling. Runtime behavior unverified. Confidence High for structure (CI + source), Medium for refactorability judgments.

**Large classes:**

| Class | Location | Size | Responsibilities | Why large | Justified? | Extraction candidates | Urgency | Evidence | Runtime verification |
|---|---|---|---|---|---|---|---|---|---|
| EnemyBase | scripts/enemies/enemy_base.gd | 964 | Lifecycle, damage intake, exactly-once death/score, AI state machine host, locomotion/navigator/striker integration, poise, perception/personality/pack, elite affixes | Hosts AI + combat + lifecycle | Mostly — but AI submodules already extracted (EnemyPerception/Personality/Pack/Navigator are separate RefCounted classes); residual size is glue + death/idempotency logic | Extract death/idempotent-score payload into a module; extract elite-affix application | LOW (defer) | wc -l | NOT RUNTIME VERIFIED |
| DebugErrorHandler | scripts/debug/debug_error_handler.gd | 736 | Error trap, session log, crash files, copy-to-clipboard, stack capture | Feature-rich debug system | Yes for a debug system (isolated, off the hot path) | Split report formatting | LOW | wc -l | NOT RUNTIME VERIFIED |
| Player | scripts/player/player.gd | 675 | Authority root, component resolution, combat/movement/death command surface | Composition root | Mostly — components (DodgeController, Stamina, Experience, etc.) already extracted | Minor | LOW | wc -l | NOT RUNTIME VERIFIED |
| CameraRig | scripts/main/camera_rig.gd | 658 | Camera orchestration (orbit, framing, collision, shake, FOV, focus) | Camera is inherently stateful | Yes; sub-controllers already extracted into scripts/main/camera/* | Minor | LOW | wc -l | NOT RUNTIME VERIFIED |
| EffectDirector | scripts/visuals/effect_director.gd | 655 | Pooled VFX dispatch | Many effect types | Partial | Split per-effect-type emitters | LOW | wc -l | NOT RUNTIME VERIFIED |
| GameRoot | scripts/core/game_root.gd | 605 | State machine, run lifecycle, scoring hooks | Central coordinator | Yes (single state authority is a feature) | None required | LOW | wc -l | NOT RUNTIME VERIFIED |
| PerformanceMonitor | scripts/utilities/performance_monitor.gd | 602 | Frame-time sampling, tier governor | One cohesive algorithm | Yes | None | LOW | wc -l | NOT RUNTIME VERIFIED |

**Scores:** Architecture Quality 9 · Code Quality 9 · Modularity 9 · Maintainability 8 · Separation of Concerns 9 · Dependency Management 8 · Type Safety 9 · Error Handling 9 · Refactorability 8 · Technical Debt 8 (higher = less debt). Confidence: High (structure/CI) / Medium (refactorability).

**Basis:** 197 scripts with typed component architecture and zero `has_method()`/`.call()` string dispatch; single state authority with a `LEGAL_TRANSITIONS` table; central collision-layer contract; data-driven content validated at boot; 908 Python + ~1095 GDScript tests green; 5 offline contract gates (engine API, scene paths, string formats, signals, typed arch). No TODOs/FIXMEs in `scripts/`. Debt is mostly *large-but-focused* classes, acknowledged by `gdlintrc` disabling `max-file-lines`/`max-public-methods`/`max-returns`.

## 5.2 Gameplay Loop, State & Session Lifecycle

Traced end-to-end in Phase 2/4. Key lifecycle transitions:

| Transition | Source | Destination | Trigger | Authority | Cleanup | Evidence | Status |
|---|---|---|---|---|---|---|---|
| Start run | main_menu/game_over | starting_run | request_play(_mode) | GameRoot | _daily={} | game_root.gd | Static-verified |
| Build world | starting_run | playing | _start_new_run | GameRoot→Main | none (fresh) | main.gd | Static-verified |
| Wave break | playing | wave_transition | wave cleared | WaveManager→GameRoot | — | wave_manager.gd | Static-verified |
| Upgrade | wave_transition | upgrade_selection | upgrade due | GameRoot | waits for selection | game_root.gd | Static-verified |
| Pause | playing/wt/us | paused | Esc/pause/back/focus-loss | GameRoot (_set_paused) | resume-state preserved | game_root.gd | Static-verified |
| Death | playing/wt/us | game_over | player death | HealthComponent→GameRoot | _finalize_run, _set_paused(false) | game_root.gd | Static-verified |
| Restart | game_over (or any gameplay state) | starting_run | request_restart | GameRoot | preserves mode/daily; pause cleared | game_root.gd | Static-verified |
| Menu return | any | main_menu | request_main_menu | GameRoot→Main._clear_world | world freed synchronously | main.gd | Static-verified |

Pause is an overlay (separate from the state table) and survives on `PROCESS_MODE_ALWAYS` nodes (GameRoot, SaveManager, AudioManager, touch stick). Android back button routed through UiRoot (dismiss modal → auxiliary screen → pause → resume → menu → guarded quit); `quit_on_go_back=false` keeps routing owned in-app. Backgrounding auto-pauses via `NOTIFICATION_APPLICATION_PAUSED`/`FOCUS_OUT`.

**Scores:** Gameplay Loop Integrity 8 · State Management 9 · Restart Reliability 8 · Session Lifecycle 8. Confidence Medium (static + headless integration green; repeated-run reliability on device unverified).

## 5.3 Player Experience & Combat

```text
Static implementation evidence:
  - Movement: PlayerLocomotion integrates in _physics_process with interpolation; NaN guards (test_locomotion_nan).
  - Attack: AttackBuffer (0.18s), melee arc/sweep resolvers, 3-hit combos (combo_damage_steps), crits, knockback.
  - Dodge: 4 directional dodges, stamina cost 25, i-frame window via DodgeController, cooldowns, interrupt-aware.
  - Hit detection: DamagePayload/DamageResult typed; area + ranged resolvers; layer contract centralized.
  - Feedback: HitstopManager, damage numbers (DamageNumberLayer), EnemyFeedback hit-flash, PlayerFeedback, screen shake.
  - Skills: 8 skills with behaviors (chain lightning, bladestorm, frost nova, warcry…), cooldowns, status application.
  - Weapons: 9 weapons, switch (Tab/tap), ranged projectiles pooled, reload for bow.
  - Targeting: TargetingComponent + lock_on input action; camera auto-follow/combat framing.
Runtime evidence: NOT AVAILABLE — execution prohibited
Player-facing consequence:  "feel" (weight, readability, responsiveness) cannot be confirmed from code alone.
Verification limit:           all subjective/feel metrics are NOT RUNTIME VERIFIED.
```

**Scores:** Movement Feel 7 · Combat Feel 7 · Dodge Feel 7 · Skill Feel 7 · Weapon Feel 7 · Responsiveness 8 · Feedback Quality 8. Confidence Low-Medium (implementation complete; feel unverified).

## 5.4 Enemies, AI, Waves & Difficulty

| Name (id) | Role | Attack | Movement | Range | Threat | Telegraph | Counterplay | AI complexity | Identity |
|---|---|---|---|---|---|---|---|---|---|
| Grunt (basic) | baseline melee | slice | 2.5 chase | melee | low | 0.4s windup | strafe, kiting | perception+personality | baseline |
| Swift (fast) | chaser | quick hit | fast | melee | low-med | short | positioning | chase+dash | speed |
| Heavy (heavy) | tank | heavy hit | slow | melee | med | long windup, poise | dodge, backstab | poise/guard | slow bruiser |
| Marksman (ranged) | ranged | shot | keeps distance | ranged | med | pre-fire | close gap, strafe | ranged state | ranged |
| Dasher (dasher) | ambusher | dash strike | dashes | melee | med | dash telegraph | sidestep | dash state + cooldown | burst |
| Exploder (exploder) | bomber | detonate | chase | self-AoE | med-high | fuse state | burst down, dodge | fuse state | kamikaze |
| Splitter (splitter) | swarm | bite | chase | melee | med | — | AoE clear | split-into-mites (extends plan) | swarm |
| Warlord (warlord) | boss | multi-phase | charge/phase | mixed | high | phase telegraphs, boss gate/health bar | phase knowledge | BossController + BossPhaseConfig | boss |

Perception (sight/FOV/LOS/hearing/reaction-time/memory), deterministic personality (flank/hesitate/grieve/stop-chasing-unseen), shared nav grid (flow field + A* around pillars/landmark), pack coordination (hearing alerts, separation steering), elite affixes, 7 mutators, DifficultyDirector adaptive scaling. Spawn pacing: opening burst ≤3, timer trickle, authored `maximum_simultaneous_enemies` (6–12), deterministic (seed, wave).

AI complexity here is **player-visible** (readable windups, personality-driven variety, pack behavior), not invisible engineering — but the *reliability and fun* of that behavior is NOT RUNTIME VERIFIED.

**Scores:** Enemy Variety 7 · Enemy Readability 7 · AI Quality 8 · AI Reliability 7 · Enemy Counterplay 7 · Boss Design 7 · Combat Encounter Quality 7 · Difficulty Curve 7 · Wave Design 8 · Encounter Variety 7 · Fairness 7. Confidence Medium (static only).

## 5.5 Progression, Economy & Replayability

XP/levels (leveled_up → skill unlocks), currency (coins → Armory permanent upgrades), 38 upgrades (rarity, prerequisites, exclusions, max_stacks, transformative effects via BuildEffects: chain lightning melee, fire/frost dodge trails, thorn nova, execute, lifesteal burst, static halo), 9 weapons, 8 skills, 3 arenas unlockable, prestige endgame (score/currency multipliers, titles, cosmetics), achievements gallery, daily seeded challenge, narrator, tutorial. `game_mode.gd` pins "no authored float magnitudes in code" (balance lives in data).

```text
Skill:         YES (8 skills, cooldown/stamina, status combos)
Builds:        YES (upgrade prereq/exclusion graph, weapon+skill loadout, transformative upgrades)
Enemy combos:  YES (waves mix archetypes + tags: frontline/flank/adds/boss)
Procedural gen: PARTIAL (deterministic seeded composition, authored arenas — not true procedural)
Modes:         YES (7 modes with distinct objectives/win-loss)
Progression:   YES (XP → level/skill; coins → armory; prestige ladder)
Challenges:    YES (daily challenge, achievements, mutators)
Randomness:    YES (seeded RNG, deterministic per run+wave)
Mastery:       YES (combo system, dodge timing, boss phases)
Grind:         YES (currency/armory/prestige loops)
Evidence:      data/upgrades, data/weapons, data/skills, data/mutators, data/prestige, scripts/meta/*
Runtime verification: NOT RUNTIME VERIFIED (balance/grind feel unverified)
```

**Scores:** Progression Quality 8 · Upgrade Design 8 · Reward Design 7 · Economy Balance 7 · Long-Term Motivation 7 · Short-Term Replayability 7 · Long-Term Replayability 8 · Build Replayability 7 · Content Replayability 7. Confidence Medium.

## 5.6 Game Modes & Content Completeness

| Mode | Entry | Objective | Win | Loss | Unique mechanics | Completeness |
|---|---|---|---|---|---|---|
| Standard | request_play | clear waves | wave cap/boss | death | classic loop | Complete |
| Boss Rush | request_play_mode | slay bosses | all bosses | death | boss-only waves | Complete |
| Survival | request_play_mode | survive clock | timer victory | death | survival clock + flat bonus | Complete |
| Challenge | request_play_mode | clear waves (prestige-scaled) | victory | death | prestige tier escalation | Complete |
| Campaign | request_play_mode | scripted beat | objective chain | death/fail | narrator beat sheet | Complete (content thin vs standard) |
| Defend | request_play_mode | hold the line | objective resolved | point lost | ObjectiveDirector | Complete |
| Collect | request_play_mode | relic hunt | objective resolved | fail | pickups objective | Complete |

Content inventory (from data/ + scripts, static):

| Category | Implemented | Integrated | Reachable | Tested | Balanced | Polished | Evidence | Status |
|---|---|---|---|---|---|---|---|---|
| Enemies (8 + boss) | YES | YES | YES | YES | YES(authored) | YES | data/enemies | Complete |
| Weapons (9) | YES | YES | YES | YES | YES | YES | data/weapons, player.tscn models | Complete |
| Skills (8) | YES | YES | YES | YES | YES | YES | data/skills | Complete |
| Upgrades (38) | YES | YES | YES | YES | PARTIAL (dominant/worthless unproven) | YES | data/upgrades | Complete |
| Status (13) | YES | YES | YES | YES | YES | YES | data/status | Complete |
| Mutators (7) | YES | YES | YES | YES | YES | YES | data/mutators | Complete |
| Arenas (3) | YES | YES | YES | YES | YES | YES | data/arenas | Complete |
| Waves (6 authored + planner) | YES | YES | YES | YES | YES | YES | data/waves | Complete |
| Boss (warlord + phases) | YES | YES | YES | YES | YES | YES | scripts/enemies/boss_controller | Complete |
| Achievements | YES | YES | YES | PARTIAL | n/a | YES | scripts/meta/achievements | Complete |
| Cosmetics | YES | YES | YES | PARTIAL | n/a | YES | scripts/visuals/player_cosmetics | Complete |
| Tutorial | YES | YES | YES | YES | n/a | YES | scripts/ui/tutorial_manager | Complete |
| Narrator/campaign | YES | YES | YES | PARTIAL | n/a | PARTIAL | scripts/meta/narrator | Mostly complete |
| Audio (29 SFX + 5 music) | YES | YES | YES | YES | YES | YES | data/audio, assets/audio | Complete |
| VFX | YES | YES | YES | YES | n/a | YES | scripts/visuals/effect_director | Complete |

**Scores:** Game Modes 8 · Mode Completeness 8 · Mode Replayability 7 · Content Completeness 7. Confidence Medium.

## 5.7 UI, UX, Camera & Accessibility

UI: `UiRoot` is composition/navigation only; panels own presentation; state changes only via EventBus; commands via GameRoot. Screens: main menu, run setup, HUD, skill bar, minimap/radar, boss health bar/gate, upgrade, pause, settings, armory, achievements gallery, help, run summary, damage numbers, announcement banner, confirmation modal. `UiLayout` solves per-aspect overlay geometry; `UiSafeArea` handles notches; text scale setting; `window/stretch aspect=expand` uses real space on tall panels. Touch: floating joystick (multi-touch ownership index, dead zone, resume-ignore), attack/dodge/swap buttons (thumb-sized radii 64/52/52, scaled per screen), stuck-input backstops, `vibrate_on_press`. Input remapping in Settings.

Camera: modular `CameraRig` + 13 sub-controllers (orbit, framing, collision solve with sphere cast + whiskers, FOV boost, shake, focus tracker, auto-follow); 3 authored CameraProfiles (default/combat/boss); arena containment; interpolation-aware. Cannot claim observed quality (no runtime).

Accessibility: text scale, reduced-motion smoothing value, input remapping, safe areas. No evidence of colorblind modes/subtitles — noted as gap, not scored as runtime defect.

**Scores:** UI Quality 8 · UX Quality 7 · Information Hierarchy 8 · Mobile Usability 8 · Touch UX 8 · Accessibility 6 · Visual Consistency 8 · Camera Quality 8 · Onboarding 7 · Discoverability 7 · Learnability 7 · Clarity 7. Confidence Medium (static + headless UI suite green).

## 5.8 Audio & Visual Presentation

Audio: `AudioManager` owns 16 SFX voices with click-safe fade-in/out (12ms/30ms, 1−t² shape), pending-claim stealing (oldest semantics), per-cue cooldown + voice caps (`SfxPolicy`), bus routing (music/SFX/UI), background mute, settings volumes/mute; `MusicManager` sole music owner; `ProceduralSfx`; 29 SFX + 5 music cues registered. Missing assets → diagnostic + fallback, never a crash.

Visual: mobile renderer, 2× MSAA, 8× anisotropic, 2048 directional shadow PCF high, glow; HDRI per-arena IBL (3 skies); PBR material pass (`HdMaterials`); 96 models (hero Warden 76 clips retargeted, enemies stylized, KayKit props); per-arena decorator; flickering torches; VFX director pooled; hitstop; damage numbers.

```text
Classification: Polished indie prototype — leaning Release-quality indie game.
Basis (static): production-grade engineering, authored+licensed asset pipeline, PBR/HDRI lighting, pooled VFX, click-safe audio, but no on-device presentation evidence and no store materials.
Runtime presentation: NOT RUNTIME VERIFIED.
```

**Scores:** Music 7 · SFX 8 · Audio Feedback 8 · Audio Architecture 9 · Visual Quality 8 · Art Consistency 8 · VFX Quality 7 · Animation Quality 7 · Visual Readability 7 · Presentation 7. Confidence Medium (static; actual look/sound unverified).

## 5.9 Performance, Android & Robustness

Static per-frame posture: fixed 60 Hz physics with interpolation (render never aliases sim); mobile renderer (SSAO/SSR off); capped simultaneous enemies (6–12); pooled projectiles/VFX/SFX voices; grid nav (no per-enemy navmesh agents); `PerformanceMonitor` frame-time governor (95th-pct, hysteresis, warmup, persisted tier, 30 fps floor via Engine.max_fps); `max_physics_steps_per_frame=6` as spiral-of-death brake; ETC2/ASTC compression; arm64-v8a only; zero Android permissions; landscape sensor; immersive mode; keep-screen-on; safe areas; `user://` saves; background auto-pause + audio mute; `PerformanceMonitor` persists proven tier across launches.

The "20+ enemies + projectiles + VFX + damage numbers + boss + navigation + UI" scenario: statically the design **caps** simultaneous enemies below 20 (6–12 authored), which bounds the worst case; projectiles/VFX are pooled. Actual FPS/memory/thermal are **unverifiable without a device/profiler** and are NOT RUNTIME VERIFIED.

Android config coherence: preset name "Android", package `com.laststandarena.game`, arm64-v8a, min/target SDK empty (Gradle default), `user_data_backup=false` (intentional), debug-signed APK produced in CI. No release keystore committed (correct; CI secrets). Version mismatch noted (D-001).

**Scores:** Performance Architecture 8 · Runtime Efficiency 8 · Scalability 7 · Mobile Performance Readiness 7 · Android Readiness 7 · Device Compatibility 7 · Mobile Lifecycle Handling 8 · Robustness 8 · Fault Tolerance 9 · Data Safety 8. Confidence Medium (static + CI build green; no device data).

## 5.10 Persistence, Testing & QA

Persistence trace: START → LOAD (SaveManager._ready, normalize+migrate) → PLAY → REWARD → SAVE (record_run_completed, debounced 1.2s atomic flush) → QUIT (flush on pause/focus-loss/exit) → REOPEN → LOAD. First launch → defaults. Missing/corrupt/partial saves → `SaveSchema.normalize_save` + migration + backup rotation (3 files) + 1 MiB cap + `save_failed` data-loss-class event (freezes in debug mode). Settings/achievements/cosmetics/armory/prestige persist. Corruption recovery + repeated-save safety unit-tested (`test_save.gd`, `test_regress_save_manager_dirty_flag.py`).

Testing: 908 Python test methods (65 files) + ~1095 GDScript tests across 46 unit suites, 10 node suites, integration stages (combat/enemy-encounter/boss/spawn-manager), UI screen/navigation suite, hero clip/socket lifecycle, asset import validation. CI runs everything green on 4.4.1; 4.7.2 diagnostics gate cross-checks warnings. No device/emulator tests exist; no soak/stress executed here (deferred). **The absence of device tests is not a QA defect** — it is a verification gap to close before release, not a score penalty.

```text
SYSTEM          TESTED?              QUALITY
Player          YES (unit+integration)  Strong
Combat          YES (integration)       Strong
Enemy AI        YES (unit brain/perception/personality/nav)  Strong
Waves           YES (unit + planner + mutators)  Strong
Progression     YES (unit + upgrade selection)   Strong
UI              YES (headless screen suite)      Strong
Persistence     YES (unit + dirty-flag + corrupt) Strong
Audio           YES (policy/procedural)          Good
Game Modes      YES (unit)                       Good
Android         YES (build/permissions/perf tests)  Good (no device)
```

**Scores:** Save Reliability 8 · Persistence Architecture 9 · Data Integrity 8 · Test Quality 9 · Test Coverage 8 · Regression Protection 9 · Release QA Readiness 7. Confidence High (CI) / Medium (QA-readiness).

## 5.11 Game Design Quality

Core fantasy (third-person arena survival with build-crafting and a meta layer) is coherent and fully realized in code/data: moment-to-moment melee+ranged combat with dodge/stamina/skills; risk/reward via elite affixes, mutators, hazard grids; build variety via 38 upgrades with a prereq/exclusion graph and 8 transformative upgrades; enemy variety via perception/personality/pack; fairness via telegraphs, poise, exactly-once scoring; pacing via authored waves + adaptive director; replayability via 7 modes, daily seeded challenge, prestige, achievements. Novelty is moderate (genre is crowded; execution/polish is the differentiator). Runtime-dependent judgments (actual "fun", "feel") are NOT RUNTIME VERIFIED.

**Scores:** Core Gameplay Fun 7 · Game Design 8 · Player Engagement 7 · Decision Depth 7 · Build Variety 8 · Originality 6 · Player Motivation 7 · Overall Fun Potential 7 (all NOT RUNTIME VERIFIED beyond static). Confidence Medium.

---

# Findings

```text
Finding:        D-001 Android version metadata mismatch
Category:       Release config
Feature state:  IMPLEMENTED BUT UNVERIFIED (builds fine; label wrong)
Severity:       P4
Evidence:       project.godot config/version="0.7.0"; export_presets.cfg version/name="0.6.0", version/code=3
Location:       project.godot:16, export_presets.cfg:[preset.0.options]
Call chain:     APK versionCode/versionName come from preset, not project config
Player impact:  none in-game; sideload/Play metadata inconsistent
Engineering impact: version tracking confusion across releases
Verification limit: none (static)
Recommended action: align preset version/name with project version before next tag
Confidence:     High
```

```text
Finding:        D-002 PCK not encrypted in export preset
Category:       Android release hardening
Feature state:  IMPLEMENTED BUT UNVERIFIED
Severity:       P4
Evidence:       export_presets.cfg encrypt_pck=false, encryption_include_filters=""
Location:       export_presets.cfg
Player impact:  none for offline gameplay; trivially unpackable asset archive
Engineering impact: asset/IP exposure if a production release is published as-is
Recommended action: enable PCK encryption (+ script export mode already 2) for Play release
Confidence:     High
```

```text
Finding:        D-003 "Parameter data.tree is null" (×66 in 4.7.2 test run)
Category:       Status system / test context
Feature state:  PARTIAL / FRAGILE (test-path)
Severity:       P3
Evidence:       diagnostics-4.7.2-summary.txt; path status_manager.gd:450 via test_status_skills.gd:106; tests still pass
Location:       scripts/status/status_manager.gd (get_tree() path)
Call chain:     status tick on node not in tree → get_tree() null → engine error logged
Player impact:  unknown; appears confined to headless fixture (node without tree). If it can occur on device it would log spam, not crash
Engineering impact: noisy error channel; masks real errors
Verification limit: runtime/device confirmation unavailable
Recommended action: triage the null-tree path; suppress for detached fixtures; confirm not reachable on device
Confidence:     Medium
```

```text
Finding:        D-004 Startup "Parse JSON failed … got 'not'" (historical log)
Category:       Persistence/config robustness
Feature state:  IMPLEMENTED (fault-tolerant) but noisy
Severity:       P4
Evidence:       run_tests.log line 3 (Godot 4.4.1); non-fatal, run proceeds
Location:       JSON.parse_string callers: audio_asset_integrator.gd:53, debug_error_handler.gd:644, save_manager.gd:285, json_helpers.gd:15
Player impact:  none observed (handled); possibly a stale/legacy user:// file on the CI runner
Engineering impact: single error line; should be root-caused to a specific file for confidence
Recommended action: identify which file fails (likely user://debug_mode.cfg or settings) and make the handler emit an attributed diagnostic
Confidence:     Low (source not identified)
```

```text
Finding:        D-005 ObjectDB instances leaked + resources "still in use" at exit
Category:       Lifecycle teardown (headless harness)
Feature state:  PARTIAL / FRAGILE (test teardown only)
Severity:       P4
Evidence:       run_tests.log ("ObjectDB instances leaked", "7 resources still in use"); 4.7.2 logs ("19 leaked", "2 resources")
Location:       test harness exit (run_tests.gd) — not demonstrated on device
Player impact:  none demonstrated
Engineering impact: leak hygiene in test harness; low risk, but worth confirming not present in live loop
Recommended action: run --verbose leak report once (when execution is authorized) to name the holders
Confidence:     Medium
```

```text
Finding:        D-006 Four EventBus signals emitted with no current listener
Category:       Event surface
Feature state:  IMPLEMENTED (emitted) but disconnected
Severity:       P4
Evidence:       diagnostics-fix-report.md §3: skill_unlocked, status_expired, wave_mutator_applied, tutorial_step_completed have emitters but 0 listeners
Location:       scripts/core/event_bus.gd
Player impact:  potential silent gaps: e.g. skill_unlocked/tutorial_step_completed suggest a tutorial/skill-unlock UI that may not yet consume them
Engineering impact: dead-ish surface; contract retained deliberately
Recommended action: confirm intended consumers or document intent; wire tutorial step completion if applicable
Confidence:     Medium
```

```text
Finding:        D-007 Hero GLB "incomplete … (trying fallback)" warnings
Category:       Player visuals
Feature state:  PARTIAL / FRAGILE (fallback path active in headless)
Severity:       P3
Evidence:       run_tests.log / 4.7.2 logs: CharacterVisuals reports WardenGladius.glb incomplete, falls back
Location:       scripts/visuals/character_visuals.gd; hero contract (docs/HERO_FIDELITY.md)
Player impact:  possible fallback to KayKit hero on device if the Warden fails the completeness gate → visual regression vs. intended art
Engineering impact: graceful, but the fallback firing in headless means the Warden gate is not fully satisfied there
Recommended action: resolve clip/mount shortfall against docs/HERO_FIDELITY.md gate; confirm on-device hero is the Warden, not fallback
Confidence:     Medium
```

```text
Finding:        D-008 Test fixtures render enemies as primitive capsules
Category:       Visual fidelity (test-only)
Feature state:  VERIFIED WORKING (production scenes correct)
Severity:       n/a (informational)
Evidence:       warnings "no VisualRoot/CharacterModel mount point for role basic (primitive kept)" originate from bare EnemyBase fixtures; production basic_enemy.tscn wires EnemyAnimator+Skeleton_Minion.glb
Location:       tests/integration_stages.gd (fixtures), scenes/enemies/basic_enemy.tscn
Player impact:  none — production path mounts authored models
Confidence:     High
```

---

# Incompleteness Matrix

| Item | State |
|---|---|
| Core loop (boot→menu→run→wave→upgrade→boss→summary→restart) | YES |
| Combat (melee/ranged/dodge/skills/status/crits/hitstop) | YES |
| Enemy AI (perception/personality/nav/pack/elites) | YES |
| Boss fight (phases, gate, health bar) | YES |
| 7 game modes objectives/win-loss | YES |
| Progression (XP/armory/prestige/achievements/daily) | YES |
| Persistence (save/backup/migration/corruption) | YES |
| Android build (CI APK) | YES |
| Tutorial/help | YES |
| Accessibility (text scale/reduced motion/remap) | PARTIAL (no colorblind/subtitle evidence) |
| Campaign narrative depth | PARTIAL (beat sheet present; volume thin) |
| Device/emulator QA evidence | UNVERIFIED (not a defect) |
| On-device performance/feel | UNVERIFIED (not a defect) |
| Release signing + store materials | PARTIAL (debug-signed milestone only) |
| True procedural generation | NO (seeded authored content — by design) |

---

# Technical Debt Matrix

**MUST REFACTOR NOW:** none — no statically blocking debt (CI green; no P0/P1).

**SAFE TO DEFER:**
| Debt | Location | Why defer | Trigger to revisit |
|---|---|---|---|
| Large-but-focused classes (EnemyBase 964, DebugErrorHandler 736, Player 675, CameraRig 658, EffectDirector 655) | scripts/ | Single-responsibility mostly preserved via extracted modules; gdlintrc acknowledges | when adding a system that would grow them further |
| 4 listener-less EventBus signals | event_bus.gd | public surface kept intentionally | when implementing the consuming feature |
| Test-harness teardown leaks (ObjectDB/resources) | run_tests.gd | test-only, no device evidence | before soak/leak instrumentation |
| "data.tree is null" test-path error spam | status_manager.gd | test-fixture path; needs triage | when tracing device logs |
| Version metadata drift | export_presets.cfg | cosmetic | next release tag |

---

# Feature Value Audit

| System | Engineering complexity | Player value | Current quality | Keep | Simplify | Remove | Priority |
|---|---|---|---|---|---|---|---|
| Enemy perception/personality AI | High | High (visible variety) | High | YES | — | — | High |
| Nav grid (flow field + A*) | High | Medium (indirect: believable pathing) | High | YES | — | — | Medium |
| Performance governor | High | Medium (smoothness on low-end) | High | YES | — | — | Medium |
| Debug error trap | High | Low-Medium (support) | High | YES | maybe trim report formatting | — | Low |
| Camera rig (13 controllers) | High | High | High | YES | — | — | High |
| 38-upgrade graph | Medium | High | High | YES | — | — | High |
| Prestige/cosmetics | Medium | Medium | Medium | YES | — | — | Medium |
| Procedural SFX | Medium | Low-Medium | Medium | YES | — | — | Low |
| Minimap/radar | Medium | Medium | Medium | YES | — | — | Medium |
| Campaign narrator | Medium | Medium | Thin | YES | — | — | Medium |

High-complexity/low-value candidates: none clearly wasteful. Debug error trap and procedural SFX are the lowest value-per-line, but both are cheap to keep and support QA/polish.

---

# Content Quality vs Quantity

**Quantity (static):** 8 enemies + boss, 9 weapons, 8 skills, 38 upgrades, 13 status, 7 pickups, 7 mutators, 3 arenas, 6 authored waves, 7 modes, 96 models, 29 SFX + 5 music — a large, coherent content set for the genre.

**Quality (static):** typed `.tres` everywhere, balance lives in data (pinned by a regression test), upgrades carry prerequisites/exclusions/stacks, weapons carry combos/patterns/damage types, skills carry behaviors/status/decay, waves carry tags/elite chances/mutators/difficulty ratings. Strong authoring discipline.

**Unverified player value:** whether the 38 upgrades are actually *interesting and distinct in play*, whether any are dominant/worthless, whether difficulty feels fair — NOT RUNTIME VERIFIED. Quantity does not equal quality in the player's hands; that remains an open question.

---

# Top 20 Evidence-Based Risks (ranked)

(No device-run absence listed as a risk, per scope.)

| # | Severity | Risk | Likelihood | Systems | Evidence | Mitigation | Verification status |
|---|---|---|---|---|---|---|---|
| 1 | P2 | On-device performance under heavy waves unproven | Medium | Rendering/combat | no profiler artifact | perf governor, pooling, caps already present | NOT RUNTIME VERIFIED |
| 2 | P2 | Combat "feel" (hitstop/i-frames/weight) unproven in hands | Medium | Combat | static only | targeted playtest pass | NOT RUNTIME VERIFIED |
| 3 | P2 | Touch control ergonomics on real devices unproven | Medium | UI/input | headless UI suite only | device/emulator touch pass | NOT RUNTIME VERIFIED |
| 4 | P2 | Hero falls back to KayKit if Warden gate fails on device | Low-Med | Player visuals | D-007 | fix gate; verify on-device | NOT RUNTIME VERIFIED |
| 5 | P2 | Difficulty/balance curve (dominant/worthless upgrades) unproven | Medium | Progression/balance | 38 upgrades, no balance telemetry | analytic hooks (RunAnalytics) + tuning pass | NOT RUNTIME VERIFIED |
| 6 | P3 | `data.tree is null` could fire on device (log spam) | Low | Status | D-003 | triage null-tree path | STATIC (unconfirmed) |
| 7 | P3 | JSON parse failure at boot (unidentified file) | Low | Persistence/config | D-004 | attribute the failing file | STATIC (unconfirmed) |
| 8 | P3 | Resource/object leaks if present in live loop | Low | Lifecycle | D-005 (test-only) | --verbose leak trace when allowed | NOT RUNTIME VERIFIED |
| 9 | P3 | Campaign mode content too thin vs. promise | Low-Med | Modes/content | narrator + beat sheet only | expand or re-scope campaign | STATIC |
| 10 | P3 | Android back-button routing edge cases on device | Low | UI | static routing only | device pass | NOT RUNTIME VERIFIED |
| 11 | P3 | Backgrounding mid-wave data-loss edge (save during pause) | Low | Persistence | flush-on-pause implemented; unproven | device background test | NOT RUNTIME VERIFIED |
| 12 | P4 | Version metadata drift | High (certain) | Release | D-001 | align versions | STATIC |
| 13 | P4 | PCK unencrypted for a production release | Low | Release | D-002 | enable encryption | STATIC |
| 14 | P4 | Listener-less EventBus signals mask unfinished integration | Low | Event surface | D-006 | wire or document | STATIC |
| 15 | P4 | Debug-signed-only artifact (not Play production) | Certain | Release | CI publishes debug APK | add release signing path | STATIC |
| 16 | P4 | No accessibility beyond text scale/reduced-motion/remap | Medium | UX | no colorblind/subtitle code | assess then add if needed | STATIC |
| 17 | P4 | gdlintrc relaxations (max-file-lines etc.) mask size creep | Low | Maintainability | gdlintrc | periodic manual review | STATIC |
| 18 | P4 | 4.4.1 pin vs. 4.7.2 native-class conflicts on future upgrade | Low | Engine | diagnostics-fix-report | keep TouchJoystick name + diagnostics gate | STATIC |
| 19 | P4 | Sideload discoverability/onboarding on first run unproven | Low-Med | UX | tutorial static only | first-run device pass | NOT RUNTIME VERIFIED |
| 20 | P4 | Asset license/provenance drift as packs update | Low | Legal | manifest + validate_assets | keep checksum gate | STATIC |

---

# Top 20 Evidence-Based Strengths

1. Green CI on the exact HEAD commit (validate + Godot headless tests + Android APK build).
2. ~1095 GDScript tests, 0 failed (4.7.2 CI) — broad unit + integration coverage.
3. 908 Python test methods pinning contracts, regressions, and cross-cutting invariants.
4. Offline contract gates (engine API, scene paths, string formats, signals, typed arch) — fail-closed, no Godot needed.
5. Typed component architecture; zero `has_method()`/`.call()` string dispatch.
6. Single state authority (`GameRoot`) with an explicit `LEGAL_TRANSITIONS` table and serialized transitions.
7. Data-driven content (`.tres`) with boot-time `ContentRegistry` validation.
8. Deterministic, seeded wave/spawn/upgrade generation (testable, reproducible).
9. Sophisticated enemy AI (perception, personality, nav grid, pack, elites) — player-visible variety.
10. Robust versioned persistence: debounced atomic flush, 3 rotating backups, migration, corruption recovery, flush-on-background.
11. Performance governor (frame-time p95, hysteresis, warmup, persisted tier) — grounded design.
12. Physics interpolation + fixed 60 Hz tick; capped simultaneous enemies; pooled projectiles/VFX/SFX.
13. Click-safe audio engine (fade-in/out, voice stealing, per-cue policy).
14. Modular camera rig with 3 authored profiles and collision/framing/shake sub-controllers.
15. Touch input hardening (multi-touch ownership, dead zones, stuck-input backstops, thumb sizing).
16. Zero Android runtime permissions (offline, user:// saves) — privacy-strong.
17. Deterministic asset pipeline with SHA-256 checksum lock + license manifests.
18. Exceptional documentation (BUILD, ARCHITECTURE, EXTENDING, PERFORMANCE_GOVERNOR, plus committed diagnostic logs).
19. Debug-mode error trap with copyable reports, crash logs, session log — QA enablement.
20. Clean code hygiene: no TODO/FIXME/HACK markers in `scripts/`; consistent `.editorconfig`/`gdlintrc`.

---

# Top 20 Fixes (priority = player impact × likelihood × severity × dependency)

| # | Fix | Priority | Dependencies | Evidence | Definition of Done | Runtime verification required |
|---|---|---|---|---|---|---|
| 1 | Align export version/name/code with project 0.7.0 | High (cheap, blocks metadata errors) | none | D-001 | preset matches project.godot | No |
| 2 | Triage `data.tree is null` path; confirm not on-device | High | status_manager | D-003 | no error spam in device logs, or suppressed for detached nodes | Yes |
| 3 | Root-cause boot JSON parse error | High | persistence/config | D-004 | attributed diagnostic names the file | Yes |
| 4 | Resolve hero Warden fallback (clip/mount gate) | High | hero assets | D-007 | Warden gate passes on-device; fallback never fires in prod | Yes |
| 5 | On-device combat-feel pass (hitstop, i-frames, dodge) | High | combat | static complete | tuned values recorded; feedback confirmed | Yes |
| 6 | Device/emulator touch-control pass | High | UI/input | headless UI suite | all actions reachable, no stuck input | Yes |
| 7 | Balance telemetry + tuning pass on 38 upgrades | High | RunAnalytics, upgrades | static only | dominant/worthless upgrades identified and rebalanced | Yes |
| 8 | Heavy-wave performance profile (perf governor validation) | High | perf | governor source | p95 within budget at authored caps on low-end device | Yes |
| 9 | Wire or document 4 listener-less EventBus signals | Medium | event surface | D-006 | each signal has consumer or documented intent | No |
| 10 | Release signing path (keystore via CI secrets) + PCK encryption | Medium | export/CI | D-002/D-015 | release-signed, encrypted APK builds | No |
| 11 | Android back-button + backgrounding device pass | Medium | UI/persistence | static routing | all routes behave; save survives background kill | Yes |
| 12 | First-run onboarding device pass (tutorial) | Medium | tutorial | static | new player reaches first wave unaided | Yes |
| 13 | Expand or re-scope campaign mode content | Medium | narrator/campaign | thin content | campaign reads as a real mode or is re-scoped | Yes |
| 14 | Accessibility assessment (colorblind/subtitles) | Medium | UX | gap | decision recorded + implemented if warranted | Yes |
| 15 | Teardown leak trace (--verbose) in harness | Low | tests | D-005 | leak holders named/fixed | Yes |
| 16 | Periodic large-class review vs. gdlintrc relaxations | Low | maintainability | wc -l | no class exceeds budget without review | No |
| 17 | Keep 4.7.x diagnostics gate on PRs (already on main) | Low | CI | gdscript-diagnostics.yml | gate runs on future branches | No |
| 18 | Add low-memory / aspect-ratio / text-scale matrix to device QA | Medium | UI | safe area/layout source | layout verified across 16:9–21:9 + small/large | Yes |
| 19 | Soak/repeated-run test (deferred, not blocking) | Medium | lifecycle | lifecycle static | 100+ runs leak-free, save intact | Yes |
| 20 | Publish non-debug production candidate only after #1–#9 | High | release | CI publish path | production candidate build green | Yes |

(No item is "add a device run merely because one wasn't performed" — every device step above is justified by a specific unverified static claim.)

---

# Static First-Playthrough Inference

> STATIC INFERENCE — NOT RUNTIME VERIFIED. Not a simulation; supported by source/scene/UI/data evidence only.

```text
0–30 seconds:   Boot → main menu. Expected: title screen with menu panel (play/setup, armory, settings,
                help). Presentation: HDRI-lit arena backdrop per menu backdrop node. Likely
                misunderstanding: none significant (tutorial coach present). Enjoy/dislike: neutral.
                Continue/quit point: none likely. Evidence: ui_root.gd _build_screens, menu_panel.gd,
                tutorial_manager.gd. Runtime verification: NOT RUNTIME VERIFIED.

30–60 seconds:  Mode selection (run setup panel) → arena run starts. Expected: 7 modes listed; player
                spawns in arena with HUD (health/stamina/skill bar/minimap), narrator announces mode.
                Likely misunderstanding: which mode is "standard" first. Likely enjoyment: first wave
                grunts (5, capped at 6) arrive — low threat. Evidence: run_setup_panel.gd, game_root.gd
                _start_new_run, wave_01.tres, narrator.gd. Runtime verification: NOT RUNTIME VERIFIED.

1–3 minutes:    Waves 1–3 cleared; first upgrade offered. Expected: wave-complete banner, upgrade panel
                with 3 choices; player spends currency on armory between runs only. Likely
                misunderstanding: upgrade rarity/prereq icons. Likely enjoyment: building early combo.
                Continue/quit: skill-gated (upgrade waits for selection). Evidence: wave_manager.gd,
                upgrade_panel.gd, upgrade_service.gd. Runtime verification: NOT RUNTIME VERIFIED.

3–5 minutes:    Waves 4–6 with mixed archetypes (heavy/splitter/dasher/ranged) + first mutator
                (swift_horde). Expected: enemy variety forces movement; dodge stamina matters.
                Likely misunderstanding: mutator announcement text. Likely enjoyment: escalating
                challenge. Continue/quit: possible frustration if difficulty spikes. Evidence:
                wave_05.tres, mutators/*.tres, difficulty_director.gd. Runtime verification: NOT
                RUNTIME VERIFIED.

5–10 minutes:   Wave 7–9 → boss wave 10 (Warlord + adds). Expected: boss gate/health bar, phase
                telegraphs, arena hazards active. Likely enjoyment: peak encounter. Likely quit point:
                death at boss if build is weak. Evidence: wave_10_boss.tres, boss_controller.gd,
                boss_health_bar.gd, hazard configs. Runtime verification: NOT RUNTIME VERIFIED.

10+ minutes:    Victory/defeat → run summary → save → restart or armory spend. Expected: summary panel
                (score/wave/best), persisted best score, prestige/currency accrual; instant restart.
                Likely engagement loop: "one more run". Evidence: run_summary_panel.gd, save_manager.gd
                record_run_completed, prestige.gd. Runtime verification: NOT RUNTIME VERIFIED.
```

---

# QA Break Scenarios (30+, unexecuted)

| # | Test | Setup | Steps | Expected | Potential failure | Severity | Evidence/rationale | Status |
|---|---|---|---|---|---|---|---|---|
| 1 | First launch (no save) | fresh install | launch | menu, defaults, no error | crash/blank screen | P1 | save defaults path | Proposed |
| 2 | Boot with corrupt save | corrupt user:// save | launch | backup recovery + defaults | data loss | P1 | normalize_save+backups | Proposed |
| 3 | Boot with >1 MiB save | oversized save | launch | rejected safely | crash | P2 | MAX_VALID_SAVE_BYTES | Proposed |
| 4 | Rapid tap Play/Retry | spam restart | mash retry | single clean restart | duplicate worlds | P2 | transition serialization | Proposed |
| 5 | Pause/resume mid-wave | pause during combat | pause, resume | state preserved, no double-fire | leaked control | P2 | pause overlay design | Proposed |
| 6 | Pause → quit to menu | pause then menu | menu | world freed, no orphans | crash on rebuild | P2 | _clear_world sync free | Proposed |
| 7 | Android back from pause | pause, back | back | resume (guarded quit) | instant quit | P2 | UiRoot routing | Proposed |
| 8 | Android home/background mid-run | background | home, return | auto-paused, save flushed | corpse on return | P1 | focus-loss auto-pause | Proposed |
| 9 | Death → summary → instant restart | die | restart | new run same mode | stale HUD | P2 | request_restart | Proposed |
| 10 | Victory → summary → armory | win | open armory | currency persists | lost currency | P1 | record_run_completed | Proposed |
| 11 | Quit during debounced save | trigger save, quit <1.2s | quit | flushed on exit | lost best score | P1 | flush-on-exit hooks | Proposed |
| 12 | Save/load round-trip | play, save, reopen | reopen | bests/armory/settings intact | mismatch | P2 | save schema | Proposed |
| 13 | Simultaneous attack+dodge+skill | mash all inputs | spam | no stuck state | missed inputs | P2 | attack buffer/dodge | Proposed |
| 14 | Max simultaneous enemies | reach 12 cap | observe | cap honored, no spawn stall | overflow | P2 | max_simultaneous | Proposed |
| 15 | Boss phase transition | warlord phase change | observe | gate/bar/announce | soft-lock | P1 | boss_controller | Proposed |
| 16 | Mode switch standard→boss rush | run both | switch | no mode bleed | wrong objective | P2 | pending_mode | Proposed |
| 17 | Daily challenge seed | run daily twice | run | same seed/mutators | non-deterministic | P3 | challenge_for_today | Proposed |
| 18 | Upgrade select then die same frame | edge timing | kill+select | clean game-over | soft-lock | P1 | state gates | Proposed |
| 19 | Low memory / large arena | stress | observe | governor degrades tier | OOM crash | P1 | performance monitor | Deferred (stress) |
| 20 | Aspect ratio 21:9 + 4:3 | rotate/resize | observe | safe-area layout correct | clipped UI | P2 | UiLayout/safe area | Proposed |
| 21 | Text scale large | set max scale | observe | no overflow | clipped text | P3 | text scale | Proposed |
| 22 | Two-finger joystick + attack | multi-touch | both | independent actions | lost touch | P1 | multi-touch ownership | Proposed |
| 23 | Audio focus loss | background during SFX | background | mute, no ghost audio | audio behind apps | P3 | background mute | Proposed |
| 24 | Missing audio cue | delete a cue file | trigger | diagnostic+fallback | crash | P2 | audio fallback | Proposed |
| 25 | Repeated runs (leak check) | 100 restarts | observe | no leak growth | leak | P2 | teardown | Deferred (soak) |
| 26 | Splitter on last enemy | split at wave end | clear | ledger counts children | false wave-end | P1 | splitter extends plan | Proposed |
| 27 | Elite affix on boss | force elite boss | fight | affixes apply sanely | unfair/stack | P2 | elite roll | Proposed |
| 28 | Mutator + hazard overlap | swift_horde + fire vents | fight | readable, fair | unreadable damage | P2 | hazard telegraphs | Proposed |
| 29 | Kill-then-pickup same frame | magnet/collect | observe | pickup counted once | double count | P3 | pickup manager | Proposed |
| 30 | Achievement unlock → gallery | unlock ach | open gallery | shows | missing | P3 | achievements | Proposed |
| 31 | Settings change mid-run | change volume/graphics | apply | live, persisted | revert | P3 | settings apply | Proposed |
| 32 | Lock-on with no enemies | tap lock-on | observe | graceful no-op | crash | P3 | targeting | Proposed |
| 33 | Camera behind pillar | position near pillar | observe | collision solve | clip through | P2 | camera collision | Proposed |

Runtime verification for all: **NOT PERFORMED**. Status: Proposed (deferred device/stress work), except where CI evidence clearly covers the underlying unit (noted).

---

# Release Gates

**GATE 0 — BOOT** — 🟢 PASS (static + headless CI)
```text
Status: PASS (static/headless evidence; not device boot)
Criteria: project imports, autoloads initialize, main scene loads
Evidence: CI godot-tests green; import.log clean (only HDR header notices)
Blocking defects: none
Missing evidence: on-device cold-boot (not a defect)
Next verification step: device boot smoke (when authorized)
```

**GATE 1 — CORE GAMEPLAY** — 🟡 PARTIAL
```text
Status: PARTIAL (full loop statically complete + headless integration green; feel unverified)
Criteria: menu→run→wave→upgrade→boss→summary→restart
Evidence: Phase 2/4 trace; integration stages green
Blocking defects: none static
Missing evidence: interactive play
Next verification step: authorized play session
```

**GATE 2 — COMBAT** — 🟡 PARTIAL
```text
Status: PARTIAL (implemented + integration-tested; feel unverified)
Criteria: melee/ranged/dodge/skills/status/hitstop all functional
Evidence: combat integration suite, weapons/status/skills data + tests
Blocking defects: none static
Missing evidence: feel/balance on device
Next verification step: combat playtest
```

**GATE 3 — PROGRESSION** — 🟡 PARTIAL
```text
Status: PARTIAL (implemented + unit-tested; balance unverified)
Criteria: XP/upgrades/armory/prestige/achievements/daily persist
Evidence: test_upgrades, test_progression, upgrade_service; save suite
Blocking defects: none static
Missing evidence: balance telemetry
Next verification step: progression playtest + analytics
```

**GATE 4 — UI/UX** — 🟡 PARTIAL
```text
Status: PARTIAL (headless UI suite green; touch feel unverified)
Criteria: all screens, navigation, safe areas, text scale, touch controls
Evidence: run_ui_validation.sh green; ui_root/touch_controls source
Blocking defects: none static
Missing evidence: on-device touch/layout
Next verification step: device/emulator UI pass
```

**GATE 5 — PERFORMANCE** — ⚪ UNVERIFIED
```text
Status: UNVERIFIED (no profiler/device data)
Criteria: sustain budget at authored enemy caps on low-end device
Evidence: governor/pooling/caps (static); no profiler artifact
Blocking defects: none (absence of device run is not a defect)
Missing evidence: profiler capture
Next verification step: profiler run on representative low-end device
```

**GATE 6 — ANDROID** — 🟡 PARTIAL
```text
Status: PARTIAL (APK builds green in CI; no device install)
Criteria: builds, installs, runs, correct orientation/permissions/safe area
Evidence: CI build-android green; preset coherent; no permissions
Blocking defects: none static (metadata mismatch P4)
Missing evidence: install/run on device
Next verification step: sideload + device smoke
```

**GATE 7 — QA** — 🟡 PARTIAL
```text
Status: PARTIAL (extensive automated suite; no device/soak)
Criteria: regression coverage + device matrix + soak
Evidence: 908 py + ~1095 gdscript tests green
Blocking defects: none static
Missing evidence: device/soak passes (proposed §QA scenarios)
Next verification step: execute deferred scenarios when authorized
```

**GATE 8 — RELEASE** — 🔴 FAIL (not yet release-ready)
```text
Status: FAIL (by design — debug-signed milestone, not production)
Criteria: production signing, version alignment, PCK encryption, device QA, store materials
Evidence: CI publishes debug APK; no keystore; version drift; no device evidence
Blocking defects: D-001 (metadata), D-002 (encryption), missing release path
Missing evidence: production candidate + device QA
Next verification step: release signing path + device QA before a Play candidate
```

---

# Final Verdict

1. **Completion (definition: release-critical features implemented + integrated + CI-verified, divided by total planned).** ~85% feature-complete; ~70% release-complete (device QA, production signing, store materials outstanding).

2. **Technical maturity: 8.5/10** — typed architecture, fail-closed contract gates, 900+ Python + ~1100 GDScript tests green, CI-built APK.

3. **Game-design quality: 7.5/10** — coherent loop, deep build/upgrade system, 7 modes, real enemy variety; novelty moderate.

4. **Static fun potential: 7.5/10** — NOT RUNTIME VERIFIED; strong genre execution, unproven feel.

5. **Polish: 7.5/10** (with limits: presentation inferred from assets/source only) — PBR/HDRI, pooled VFX, click-safe audio, modular camera; unverified on-device.

6. **Android readiness: 7/10** — APK builds green, no permissions, lifecycle handling; no device evidence, debug-signed, version drift.

7. **Actual stage: Beta** (feature-complete, heavily headless-tested, debug APK buildable; not RC — no on-device QA, no production signing/materials).

8. **Biggest weakness:** No verified on-device evidence for feel, performance, and touch ergonomics — the risk is concentrated entirely in the unmeasured "hands-on" layer, not in engineering.

9. **Biggest strength:** Engineering rigor — typed architecture, deterministic data-driven content, and an unusually deep automated-verification stack that is green on the audited commit.

10. **Fixes for 7 days:** version alignment (D-001); triage `data.tree` null + boot JSON parse (D-003/D-004); resolve hero fallback gate (D-007); wire/document 4 dead-signal consumers (D-006); one device/emulator touch+combat smoke pass.

11. **Fixes for 30 days:** on-device performance profile + governor validation; balance telemetry pass on upgrades; release signing + PCK encryption; campaign content expansion or re-scope; accessibility assessment; first-run onboarding device pass.

12. **What not to work on now:** unproductive application runs, stress/soak/load tests, and device matrix work **without a specific question they answer**; further architecture refactors (large classes are contained and CI-green); adding more content before the feel/balance questions are answered; PCK encryption before a production candidate exists.

13. **Highest-value score improvement:** a targeted on-device verification pass (combat feel + touch ergonomics + heavy-wave profiling) that converts the largest UNVERIFIED cluster into measured data — this moves Release Readiness and QA gates from PARTIAL/UNVERIFIED toward PASS without any code change.

```text
╔══════════════════════════════════════╗
║       GAME AUDIT FINAL SCORE         ║
╠══════════════════════════════════════╣
║ Engineering:              8.5 / 10  ║
║ Gameplay:                 7.3 / 10  ║
║ Design:                   7.5 / 10  ║
║ Content:                  7.4 / 10  ║
║ UX/UI:                    7.4 / 10  ║
║ Visuals:                  7.4 / 10  ║
║ Audio:                    7.6 / 10  ║
║ Performance:              7.0 / 10  ║
║ Android Readiness:        7.0 / 10  ║
║ QA/Testing:               8.3 / 10  ║
║ Polish:                   7.5 / 10  ║
║ Replayability:            7.3 / 10  ║
║ Fun Potential:            7.5 / 10  ║
║ Release Readiness:        6.8 / 10  ║
╠══════════════════════════════════════╣
║ OVERALL GAME SCORE:       7.3 / 10   ║
╚══════════════════════════════════════╝
```

> “This is currently a **feature-complete beta**, with its strongest quality being **engineering rigor and an unusually deep green verification stack**, its biggest weakness being **the entirely unverified hands-on layer (feel, performance, touch)**, and the highest-value next step being **a targeted on-device verification pass that converts the largest UNVERIFIED cluster into measured data**.”

---

## Scorecard (detail)

| Category | Score / 10 | Confidence | Key Reason |
|---|---|---|---|
| Architecture | 9 | High | Typed components, single state authority, fail-closed contract gates |
| Code Quality | 9 | High | No string dispatch, no TODO/FIXME, consistent conventions |
| Maintainability | 8 | Medium | Large-but-focused classes; excellent docs |
| Modularity | 9 | High | Extracted sub-modules (AI, camera, audio, save) |
| Gameplay Loop | 8 | Medium | Full loop integrated + integration-tested |
| Combat | 7 | Medium | Complete (melee/ranged/dodge/skills/status); feel unverified |
| Movement | 7 | Medium | Interpolation + NaN guards; feel unverified |
| Dodge | 7 | Medium | 4 dodges, i-frames, stamina statically complete |
| Weapons | 7 | Medium | 9 weapons, combos, patterns, pooled projectiles |
| Skills | 7 | Medium | 8 skills with behaviors + status |
| Enemy AI | 8 | Medium | Perception/personality/nav/pack; reliability unverified |
| Enemy Variety | 7 | Medium | 8 archetypes + boss + elites/mutators |
| Enemy Readability | 7 | Medium | Telegraphs/windups/poise implemented |
| Bosses | 7 | Medium | Multi-phase warlord + boss rush + boss camera/bar |
| Wave Design | 8 | Medium | Authored waves + mutators + director + boss wave |
| Difficulty | 7 | Medium | Adaptive director + elite affixes; balance unverified |
| Progression | 8 | Medium | XP/armory/prestige/achievements/daily |
| Upgrades | 8 | Medium | 38 with prereq/exclusion/stacks + transformative |
| Economy | 7 | Medium | Currency/armory/prestige loops; balance unverified |
| Replayability | 7 | Medium | 7 modes, mutators, daily, prestige |
| Game Modes | 8 | Medium | 7 modes with objectives/win-loss |
| UI | 8 | Medium | Modular panels, safe area, layout solver |
| UX | 7 | Medium | Coherent flows; device feel unverified |
| Touch Controls | 8 | Medium | Multi-touch ownership, dead zones, thumb sizing |
| Camera | 8 | Medium | Modular rig, profiles, collision, framing |
| Audio | 8 | Medium | Click-safe voices, policies, music manager |
| Visuals | 8 | Medium | PBR/HDRI/MSAA; look unverified |
| VFX | 7 | Medium | Pooled director, hitstop, damage numbers |
| Animation | 7 | Medium | 76 hero clips, enemy animators; hero gate warns |
| Performance | 8 | Medium | Governor, pooling, caps; FPS unverified |
| Android Readiness | 7 | Medium | Green APK build, no perms; no device, debug-signed |
| Save System | 8 | High | Versioned, atomic, backups, recovery |
| Robustness | 8 | High | Graceful fallback everywhere + debug trap |
| Testing | 9 | High | ~1100 GDScript + 908 Python tests green |
| Documentation | 9 | High | BUILD/ARCHITECTURE/EXTENDING + committed logs |
| Accessibility | 6 | Medium | Text scale/reduced motion/remap only |
| Onboarding | 7 | Medium | Tutorial + help + narrator static |
| Clarity | 7 | Medium | Announcements/banners; device comprehension unverified |
| Originality | 6 | Medium | Crowded genre; execution is the differentiator |
| Fun Potential | 7 | Medium | NOT RUNTIME VERIFIED |
| Content Completeness | 7 | Medium | Large set; campaign thin |
| Release Readiness | 7 | Medium | Beta; production path + device QA outstanding |

**Overall scores (weighting rationale):**
- **Engineering 8.5** — equal-weight mean of architecture, code, reliability, testing, performance, maintainability; weighted up by the green contract-gate evidence (High confidence).
- **Game 7.3** — fun/gameplay/combat/design/pacing/progression/replayability/content/UX; weighted down by confidence, not by the absence of a device run (feel is statically complete but unverified, so Medium confidence, scores reflect implementation).
- **Release 6.8** — completeness, verification, bugs, Android readiness, QA, performance, polish; reflects the debug-signed milestone status and the unmeasured device layer as *release limitations*, never as defects.

```text
OVERALL GAME SCORE: 7.3 / 10
```

*Audit scope note: this report is a read-only forensic audit. No files of the audited project were modified, no code was executed, no tests were run this session, and no device/emulator was used. All runtime-dependent conclusions are explicitly marked NOT RUNTIME VERIFIED.*
