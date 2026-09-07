# Changelog

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
