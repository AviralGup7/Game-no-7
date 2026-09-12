# Changelog

## [Unreleased] — Skill cast-focus prop set (2026-09-12)

- Author the eight missing skill visuals: one cast-focus prop per skill, matching the eight
  configs in `data/skills`, built by `tool/build_skill_foci.py` and the new stdlib-only
  `tool/skill_forge` geometry package (parametric primitives, PBR channel baking, GLB packing,
  and a rasterizer that renders the shipped file rather than the in-memory model).
- Give every focus one material on a 512² four-map atlas (albedo, normal, ORM, emission) with
  at most ten 128² islands, 2.0k–3.9k triangles, a ≤0.6 m footprint, its deck seated at Y=0 and
  `Socket/Cast`, `Socket/Flare` and `Socket/Base` nodes, so an effect can attach without knowing
  the mesh. Each prop's glow reuses the accent already in `EffectDirector.SKILL_COLORS`.
- Render the skill-bar icons from those same GLB bytes (128² RGBA) and wire `icon` into all eight
  `data/skills/*.tres`, so the bar can no longer drift from the model; `assets/catalog.json`
  `gameplay_skills` gains `model`, `icon` and `prop_scene` beside the existing cast-ring texture.
- Ship drop-in `scenes/props/skill_focus_<skill>.tscn` instances scaled through the existing
  `ModelVisual.create(scene, extent)` seam; no GDScript, pool cap or arena-prop table changed.
- Record provenance in `data/models/skills/build_report.json` (recipe, nine source hashes,
  every output hash, measured counts) and add `ASSET_LICENSES/skill-foci.md` plus
  `docs/agent_skills/05_skill_focus_asset_recipe.md` for the contract, the seams and the
  winding/inset/shading-group pitfalls a plausible render hides.
- Add `tests/python/test_skill_foci.py`: fifteen checks that re-parse every GLB (attributes,
  bounds, single material, UV range, unit normals with orthogonal tangents), re-hash every
  reported file against the build report, validate the prop scenes and resources, and assert
  the catalogue points only at files that exist. All asset gates and the Python suite pass.

## [Unreleased] — Continuous campaign world (2026-09-12)

- Make the shipping entry a fixed 352 × 272 m station with six connected districts,
  seven story objectives, safe checkpoints and a final return to the docks.
- Author 13 connected floor regions, 24 collidable landmarks, 15 interactions and
  eight finite encounters (29 enemies); no arena or world-seed setup in the app.
- Share world coordinates across physics, conservative navigation, route guidance
  and the station chart. Merge floor-union perimeter walls without sealing doors.
- Stream nearby living spawn IDs (18 active cap / two activations per tick), cull
  distant district batches (three cap) and use instanced modular floors. Cleared
  actors never respawn on checkpoint retry; the commander cannot summon untracked adds.
- Add native-touch Interact/Map/Pause, Continue/New confirmation, safe-area HUD,
  checkpoint retry, extraction/exploration and a campaign Armory/loadout screen.
- Add additive save schema 8: persistent objective/defeat IDs, checkpoint, build and
  XP; stage reward claims with wallet changes and avoid legacy run-end double banking.
- Add actual topology/clearance validation, reproducible SVG overview, native
  campaign/migration/integration suites, CI/build registration and APK map-content
  checks. Offline checks pass; native campaign/APK/device execution is still pending.

## [Unreleased] — Android-first follow-up (2026-09-12)

- Handle skill and pause buttons through native multi-touch, without requiring
  the mouse-emulation pointer; show touch-ready skill hints on Android.
- Clear Android canceled gestures for movement and camera, require a fresh
  touch-down to start camera look, and cancel held input when cutouts/layout move.
- Refresh notch/system-bar insets even for a 180-degree landscape flip; bound
  invalid platform rectangles and avoid unchanged-layout polling churn.
- Track activity pause and window/application focus independently for audio;
  preserve user mute and keep gameplay paused on return. Gate haptics to mobile.
- Keep Mobile rendering / ARM64 / 60 FPS on Android, with 2x startup MSAA.
  Host Compatibility rendering no longer applies to APK export.
- Verify the real APK's identity, SDK levels, ELF ABI, renderer metadata,
  permissions and signature. Exclude host reports/test data from APK assets.
- Make device QA explicit and serial-scoped: no missing-device false passes,
  ignored launch failures, uninstall or progression clearing. Add regressions
  and an Android-only validation checklist; see docs/ANDROID_HARDENING.md.

## [Unreleased] — Project correctness audit (2026-09-11)

- Repair save checksum round trips (integer/float and fractional-clock spelling),
  retain verified legacy recovery, preserve int64 daily seeds as decimal strings,
  and validate malformed settings/input/JSON without damaging working state.
- Resolve reload/skill/camera/controller conflicts with narrow schema-7 factory
  migration and atomic staged remapping.
- Fix hazard-overlapping player starts, split/forced spawn caps and navigation,
  objective lifecycle, reentrant death, dead-boss enrage, offensive proc ownership,
  chain targets, run-end effect isolation and freed delayed-damage sources.
- Re-arm spatial Foley for replacement players and validate expired emitters
  before casts. Fix HUD parenting, portrait menu orientation and theme members.
- Correct the historical ASCII-only resource rule: literal UTF-8 loads correctly;
  escaped high codepoints produced errors on the pinned engine.
- Add native regressions; repair stale flow/stress fixtures and test cleanup;
  enforce strict logs/results, safe profiles/timeouts, pinned staged installers,
  truthful failure reports and fully gated release publication. Use Xvfb/Mesa
  for official-engine CI validation rather than suppressing dummy-renderer errors.
- Evidence, remaining graphics/Android limits and reproduction steps:
  [PROJECT_AUDIT.md](docs/PROJECT_AUDIT.md).

## [Unreleased] — Documentation consolidation (2026-09-11)

`docs/` reduced from 34 to 20 markdown files. Canonical/reference docs (pinned by
regression tests or code comments) are kept; process artifacts, one-off research
notes and duplicates were deleted or merged.

- **Deleted (waste — historical/process artifacts, unreferenced):**
  `AGENT5_UI_HANDOFF`, `RECHECK`, `RELEASE_CANDIDATE_REPORT`, `QA_RELEASE_AUDIT`,
  `MILESTONES_2_7_SUMMARY`, `MILESTONE0_AUDIT`, `GAME_ROOT_LIFECYCLE_RESEARCH`,
  `INPUT_REMAP_RESEARCH`, `OBJECT_POOL_RESEARCH`, `WEIGHTED_TABLE_RESEARCH`.
- **Merged (duplicates → one doc):**
  - `CAMERA_MODULAR` + `CAMERA_PERFECT` → **`CAMERA.md`** (modules, coordinator loop,
    design principles, profiles, references).
  - `PLAYER_IMPLEMENTATION` + `MOVEMENT_STABILITY` + `STARTUP_STABILITY` → **`PLAYER.md`**
    (player contract + tuning, NaN-crash postmortem, boot/visibility postmortem).
  - `ENEMY_AI_ROBUSTNESS_RESEARCH` → appended as §5 of `ENEMY_AI_RESEARCH.md`.
  - `MILESTONE0_AUDIT` determinism contract → new `## Determinism` section in
    `ARCHITECTURE.md`.
- **Updated pointers:** `tool/validate_guards.py` (movement-stability rationale),
  `tests/python/test_regress_enemy_ai_hardening.py`, `tests/python/test_regress_milestones_2_to_7.py`,
  and the README repository map + documentation table.
- **Verification:** 910 Python tests, engine-API contract, typed-architecture gate,
  guard gate (201) and resource gate (159) all green. No runtime/device claims.

## [Unreleased] — Forensic-audit remediation: version alignment + detached-node error spam (2026-09-11)

Follow-up to the read-only game forensic audit (`GAME_FORENSIC_AUDIT.md`). Only the
two statically-actionable, non-duplicative defects were fixed; everything else in
the audit was triaged as intentional test noise, reserved public surface, or a
runtime/device-dependent gap (deferred — see below).

- **Android version metadata now matches the project version.** `export_presets.cfg`
  carried `version/name="0.6.0"` / `version/code=3` while `project.godot` declared
  `0.7.0`. Bumped to `version/name="0.7.0"` / `version/code=4` so `scripts/release.sh`
  tag matching and the APK manifest agree with the codebase. The milestone regression
  pin (`tests/python/test_regress_milestones_2_to_7.py`) was widened to accept `0.7.0`.
  Offline gates re-run green: 910 Python tests, engine-API contract, typed-architecture
  gate, guard gate (201), resource gate (159).
- **`StatusManager._autoload_node` no longer logs `Parameter "data.tree" is null`.**
  `Node.get_tree()` on a node outside the tree returns null *and* emits an engine error.
  Detached `StatusManager` fixtures (e.g. `test_status_skills.gd`) therefore produced
  66 identical error lines per headless run. The resolver now checks `is_inside_tree()`
  before calling `get_tree()` and keeps the `Engine.get_main_loop()` fallback, so
  behavior is unchanged but the error channel is clean.

Triage outcomes recorded so no future pass wastes effort re-investigating them:

- **"Parse JSON failed … got 'not'"** — produced by the deliberate negative test
  `JsonHelpers.parse_safe("not json", …)` in `test_meta_misc.gd`; all four `JSON.parse_string`
  call sites handle failure. Expected noise, not a defect.
- **"incomplete hero … WardenGladius.glb (trying fallback)"** — produced by
  `test_hero_rig.gd::_test_fallback`, which feeds a no-rig mesh to prove the
  `HeroRigContract` fallback gate. Expected noise, not a defect.
- **Listener-less EventBus signals (`skill_unlocked`, `status_expired`,
  `wave_mutator_applied`, `tutorial_step_completed`)** — all four are emitted with zero
  listeners today but are intentionally retained public surface (documented in the
  Godot 4.7.2 diagnostics report). Wiring fake listeners just to silence a warning
  was deliberately avoided.
- **PCK encryption** — left off: enabling `encrypt_pck` without a configured script
  encryption key fails the Android export. This is a release-signing-time step, not a
  pre-release bug.
- **ObjectDB/resources "leaked at exit"** — confined to the headless test harness and
  only nameable with `--verbose`; requires an authorized runtime trace before any fix.
## [Unreleased] — Fix pass: identity, haptics, remaps, pickers, tutorial, midgame waves (2026-09-11)

- **Version identity:** `project.godot`, `export_presets.cfg` and the example preset all ship `0.7.0` (version code 4). Android minSdk 24 / targetSdk 34 are authored instead of empty.
- **Haptics:** export preset declares `permissions/vibrate=true` so `Input.vibrate_handheld()` can fire on device; still gated on the vibration setting.
- **Input remaps persist** through `SettingsData.input_bindings` (save schema 6). Factory bindings are snapshotted before load so Restore Defaults works.
- **Run setup is real:** arena launch calls `GameRoot.request_arena_selection`; starter loadout calls `GameRoot.set_pending_weapon`. Locked arenas/weapons stay preview-only.
- **Tutorial coach** walks move → attack → dodge → winded → skill → upgrade → survive.
- **Authored waves 6–9** fill the midgame gap before the wave-10 warlord.
- **Settings debug chrome** (TRIGGER TEST ERROR / last-error viewers) is hidden unless debug mode is on or the build is a debug APK.
- README names all **7** playable modes. Diagnostics CI tracks this branch.

## [Unreleased] — Arena art pass: per-arena dressing, landmark floor art, hazard models (2026-09-10)

- **Downloaded 13 KayKit dungeon models** (same reviewed pack + pinned rev, CC0,
  blob-sha verified against the upstream tree): per-arena champion shield banners,
  decorated/stacked barrels and crates, candle trio + lit candle, sword trophies,
  trunk, open vent grate. Manifest grows 243 → 256 files / 96 models.
- **Hazard markers mount floor models** under an honest telegraph disc: spike bed,
  open vent and plate tile (the first two were locked but unused), plus a rim ring
  at the exact hitbox radius and an ember orb for the orbiting mover.
- **Landmarks enriched in code**: rotating lava with crust chips, five-prism cluster
  with heart shard, stepped obelisk with rune band; every silhouette gets a plinth,
  rim and wide floor ring plus a shared idle emission pulse. Torch sconces get a
  deterministic glow halo on the approved Kenney flare sprite.
- **Per-arena decorator compositions**: gate-flanking trophy pairs (Default), lit
  candle ring (Frost), crate depots + decorated barrel stacks (Ember). Default
  scatter spots shifted slightly (trophies route first); still deterministic.
- Pinned by `tests/python/test_regress_arena_art.py` (10 tests); the catalogue's
  "per-arena bespoke art" pending item is resolved.

## [Unreleased] — Debug mode: errors freeze the game with a copyable report (2026-09-10)

On-device debugging had no story: an APK failure meant a dead app and no
details. There is now a debug-mode error trap. A toggle on the main menu (and
in Settings > Debug) arms it; while ON, any error reported through EventBus —
the channel every critical boot/run system already uses — pauses the tree and
presents a copyable block (message, stack trace, device/game context, recent
log) instead of crashing, with copy-to-clipboard, save-to-file, prev/next
through stacked errors, resume, restart, and main-menu actions.

- **New `DebugErrorHandler` autoload, second after EventBus.** It taps the
  `diagnostic` signal, snapshots `get_stack()` synchronously at capture time,
  and presents deferred so reporting stays safe from any call stack. It owns
  its own flag file (`user://debug_mode.cfg`, never SaveManager) so it can sit
  that early and still persist; every diagnostic plus state/run/wave
  breadcrumbs always append to `user://logs/session.log` even with the flag
  off. Its own I/O failures use `push_warning` directly, so error handling can
  never report an error about itself (no recursion).
- **Freeze overlay, not a crash.** `DebugErrorOverlay` (layer 128,
  always-process, input-swallowing) shows the report in a read-only TextEdit;
  `COPY REPORT`/Ctrl+C copies the whole block with a verified round-trip and a
  manual-copy fallback hint, and each capture auto-saves a `crash_*.log` file
  (newest 5 kept). Resume restores the pause state by re-reading
  `GameRoot.is_paused()`, so an Android Back press behind the overlay cannot
  desync the tree pause.
- **Honest coverage.** GDScript-called failures freeze; hard native crashes
  cannot be intercepted from script, so each boot checks the previous
  session's exit flag and Settings > Debug offers the recovered log tail one
  click away (`VIEW LAST SESSION LOG`). Headless/CI runs never freeze (no
  screen) but still log and write crash files; `--no-debug-freeze` does the
  same for scripted device runs.
- **Self-test + docs.** `TRIGGER TEST ERROR` proves the freeze/copy pipeline
  on a device without waiting for a real bug; `docs/DEBUG_MODE.md` documents
  the toggles, overlay actions, files, and limits. Pure core
  (`ErrorReport`/`DebugLogBuffer`) is covered by
  `tests/unit/test_error_report.gd` in the synchronous suite; the startup
  contract test now pins nine singletons with the handler directly after
  EventBus.
- **Follow-up hardening, fixes, and integrations.** Frame #0 is now the true
  caller (`ErrorReport.drop_internal_frames` strips the EventBus/pipeline
  frames, unit-tested); every capture grabs a paired `crash_<stamp>.png`
  screenshot whose path lands in the report context; the overlay headlines
  each capture's title and its auto-saved path; a failed clipboard copy now
  selects the whole text for a one-gesture manual copy; the session log
  rotates off an in-memory byte counter instead of a probe open per line.
  Coverage widened: `save_failed` captures as data-loss class, the severity
  gate fails closed (any future non-info/warning severity freezes), and a
  background-aware stall watchdog breadcrumbs main-loop gaps over 1.5s.
  Integrations: real errors count into analytics (`note_error` → per-run rows
  + `session_errors`; pure increment, self-tests excluded) and the test
  harness exposes the `debug` snapshot plus a `debug_trap_ready` smoke step.
  `tests/python/test_regress_debug_mode.py` pins the trap's load-bearing
  shapes so refactors cannot silently break them.
## [Unreleased] — Godot 4.7 compatibility: the joystick class no longer hides a native class (2026-09-10)

Godot 4.7 added a **native** class named `VirtualJoystick`. A `class_name` that hides a native class
is a hard parse error, not a warning, so on 4.7.2 the project stopped loading with a three-deep
cascade that looked like three independent broken files:

```
SCRIPT ERROR: Parse Error: Class "VirtualJoystick" hides a native class.
          at: res://scripts/ui/virtual_joystick.gd:1
SCRIPT ERROR: Parse Error: Cannot infer the type of "value" variable ...
          at: res://scripts/ui/touch_controls.gd:79
SCRIPT ERROR: Compile Error: Failed to compile depended scripts.
          at: res://scripts/ui/ui_root.gd:0
ERROR: Failed to load script "res://scripts/main/main.gd" with error "Parse error".
```

- **`VirtualJoystick` → `TouchJoystick`.** `virtual_joystick.gd` keeps its path, its API
  (`radius`, `dead_zone`, `opacity`, `get_value()`, `is_active()`, `cancel()`, `set_rest_alpha()`,
  `value_changed`/`became_active`/`became_inactive`) and its behaviour; only the global class name
  changed. `TouchControls`, `tests/ui/ui_test_runner.gd` and `tests/unit/test_locomotion_nan.gd`
  were updated to match. `main.gd` and `ui_root.gd` needed no edits at all — their "parse errors"
  were the cascade, and they clear once the joystick script loads.
- **CI can now see this class of failure.** `gdscript-diagnostics.yml` runs the project through
  4.7.2-stable: full import, the headless suite, a per-script pass, an editor pass, and a
  warnings-as-errors pass (the engine's own escalation switch, injected in the runner only) so
  analyzer warnings that are editor-only still reach the log with a `res://` path and line number.
  Logs are committed to `docs/godot-runs/` because the Actions log endpoint is not reachable from
  every environment that has to read them.

## [Unreleased] — Editor-error sweep: the 4.7.2 report, fixed and verified offline (2026-09-10)

The project was opened in a Godot **4.7.2-stable** editor and reported three "Parse error"
toasts (`main.gd`, `virtual_joystick.gd`, `tests/unit/test_locomotion_nan.gd`) plus 107
analyzer warnings. The warning half was real and is now fixed tree-wide; the parse-error half
was investigated against the actual engine source and is documented below.

- **The parse errors are not code defects.** The three scripts were diff-checked against the
  real `4.4.1-stable` → `4.7.2-stable` GDScript sources (tokenizer, parser, analyzer, and the
  full warning table downloaded from the engine tags): no grammar rule tightened, no analyzer
  hard error added that any construct in those files uses (the only new hard errors in 4.7 are
  `@abstract`-class related), and the default warning-to-error levels are byte-identical
  between the two versions. All three files load green in the pinned 4.4.1 CI (main scene +
  the NAN-locomotion suite both execute them) and parse clean under gdparse/gdlint. The
  toasts match the known 4.6/4.7 editor first-load dependency-order bugs
  (godotengine/godot#120407, #119715, #119100): dependent scripts surface a generic
  "Parse error" while the editor's threaded import is still resolving their dependencies, and
  the error clears once loading completes. `docs/BUILD.md` (Troubleshooting) now says so.
- **UNUSED_SIGNAL ×47 silenced by annotation, not deletion.** Every one is a live cross-file
  contract (verified project-wide: each signal has an emitter and receivers somewhere in the
  tree) that the per-script analyzer cannot see. `event_bus.gd` wraps its declaration block in
  `@warning_ignore_start/restore("unused_signal")` with the rationale; `enemy_base.gd`
  (`state_changed`, `attack_started`, `attack_hit` — emitted by the state scripts) and
  `player.gd` (`move_started`, `move_stopped`, `upgrade_applied` — emitted by the locomotion /
  progression components) exempt exactly those signals at the declaration. The annotation is
  engine-verified present in both 4.4.1 and 4.7.2 and applies to `signal` members.
- **SHADOWED_* ×29 fixed for real.** A chain-aware offline detector (ClassDB manifest +
  project class graph, the same data the engine-API gate uses) enumerated exactly the
  identifiers the analyzer would flag, and each was renamed at the source: `seed` → `run_seed`
  in 18 functions (a `seed` parameter shadows the `@GlobalScope` function everywhere), plus
  `name`/`owner`/`text`/`size`/`position`/`control`/`mount`/`basis`/`floor`/`exp`/`log`/
  `capacity`/`world_xz`/`free` shadows across `audio_manager`, `announcement_banner`,
  `armory_panel`, `camera_rig`, `character_visuals`, `combat_log`, `dodge_controller`,
  `effect_director`, `enemy_feedback`, `minimap`, `test_harness`, `ui_gauges`, `ui_theme`,
  `virtual_joystick` and six test harnesses. Call sites are positional, so no behavior moved;
  the contract tests that pin signatures were updated to the new names in the same commit.
- **UNUSED_PARAMETER ×11 underscored** at genuine protocol/signal seams
  (`damageable.apply_damage`, `game_root._on_state_entered`, `enemy_animator._on_boss_telegraph`,
  `spawn_ledger.register_direct_spawn`, `player._on_weapon_attack_resolved`,
  `player_feedback.play_attack_feedback`, `effect_director._on_wave_started` /
  `_on_pickup_collected`, `arena_decorator._centerish`, two test helpers), and
  `enemy_idle_state._investigate` dropped its dead `cfg` parameter entirely.
- **UNUSED_VARIABLE ×2 removed** (`ui_theme.create`'s unread `surface`, a dead `g0` capture in
  the pickup-magnet stress check) and the **UNREACHABLE_CODE** `return 0` after the real
  return in `upgrade_panel._current_stack()` was deleted.
- **INTEGER_DIVISION ×5 made intent-explicit** without changing values: the mm:ss formatting in
  `game_mode.objective_label` (`int(left / 60)` — float division + truncation, identical for
  the non-negative operand, and it keeps the no-authored-magnitudes rule intact), the A* index
  math in `arena_nav_grid` (`int(i / float(width))`), and the mirrored-flank spacing in
  `spawn_patterns` (`float(int(i / 2.0))` — truncation preserved).
- **CONFUSABLE_LOCAL_DECLARATION ×1 fixed**: `arena_nav_grid.find_path` declared `i` inside the
  heap loop while the parent function declares `i` again below; the loop-local is now `idx`.
- **SHADOWED_VARIABLE ×1 fixed (screenshot 0:00:03:322)**: `RngService.chance(salt, chance)` had
  its probability parameter shadowing the member function of the same name (line 67 of
  `rng_service.gd`, exactly as the editor toast reported); the parameter is now `probability`.
  The three `INT_AS_ENUM` warnings in the same toast came from the pre-rebuild `game_mode.gd`
  checkout; the current tree assigns its `Maneuver`/`Status`/`Mode` enums only via constants,
  so there is nothing left to cast.
- Verification: 887 python tests green (four signature-pin needles updated to the renamed
  contracts), all seven offline gates green (typed-arch, guards, resources, engine-api,
  scene-path, string-format, signals), gdparse + gdlint clean over the whole tree, and the
  shadow detector re-run at zero.

## [Unreleased] — The signal contract became a gate: names and arities, pinned offline (2026-09-10)

Fourth pass of *what is the weakest section of an all-green tree?* The ClassDB, the node tree and
the `%` operator are pinned; the last big unpinned messaging surface was the game's own
**signals**: 133 declared across 39 scripts, an EventBus-centric architecture, ~210 calls through
autoload receivers, ~138 through implicit `self`, plus dynamic receivers and two legacy string
forms. Per the pinned engine's docs (4.4.1-stable `Object.connect` / `Signal.emit`), a nonexistent
signal name is a runtime error, a wrong emit arity is a runtime error, and the engine invokes a
connected Callable with exactly the signal's arguments — a method whose parameter list cannot take
them fails at emit time. gdparse/gdlint see none of it; the headless suites only exercise the
connections their flows happen to take.

- **The manifest grew signal arities.** `tool/build_api_manifest.py` now records every engine
  signal's parameter count alongside its name (regenerated from the same sha-verified
  4.4.1-stable tagball: 994 classes, 466 engine signals with arities — `Node.ready` = 0,
  `Area3D.body_entered` = 1), so inherited engine signals and their arities are part of the
  checked-in contract.
- **The gate is `tool/check_signals.py`** — stdlib-only, hermetic, wired into CI's
  `validate-resources` stage. It resolves every signal operation on its receiver: implicit `self`
  (walking the `extends` chain through project scripts into engine signals), autoloads (whose
  class is known exactly, so those checks are strict, arity included), legacy string forms
  (`emit_signal("x", ...)`, `connect("x", ...)`, receiver-aware), and connected callables — a
  same-file method must satisfy `required <= signal params <= total` (defaults widen the range,
  exactly as the engine's call will), and inherited engine methods are existence-verified.
  Severity follows the sibling gates: a name declared *nowhere* is a phantom and fails the build
  whatever the receiver; a dynamic receiver using a name declared elsewhere is the engine's
  UNSAFE-access analogue, reported as advisory warnings (244 today, `--verbose` lists them);
  `has_signal` probes are counted, never flagged. The tree's guarded duck-typing
  (`if _host.has_signal("state_changed"): _host.emit_signal(...)`) stays legal by construction.
- **First-run result: clean.** 138 self-signal ops, 210 autoload-receiver ops, 4 legacy string
  forms and 264 dynamic receivers checked — zero phantoms, zero arity mismatches. The value is
  the pin: the three defect classes this tree shipped before were all "name the pinned engine
  doesn't answer"; the fourth class — "signal the declaring class doesn't declare" — now fails
  the build before it can ship instead of at runtime on a flow the headless suites don't touch.
  (One false positive the gate caught in its own bring-up became a real fix to the gate:
  connected callables resolve through the class chain, so `resized.connect(queue_redraw)` on a
  `Control` is verified as CanvasItem's method, not flagged as a phantom.)
- **The gate is pinned by tests.** `tests/python/test_regress_signal_contract.py` (26 tests): the
  tree runs clean with real volume (>=130 self ops, >=200 autoload ops, >=4 string forms), the
  manifest carries engine signal arities, and one synthetic negative per error class — bare/chained/
  autoload phantoms, declared-elsewhere warning split, engine-inherited signals, emit arity
  (self and autoload), phantom callables, callable arity out of range, default-parameter ranges,
  inherited engine callables, legacy string forms (bare, dynamic-receiver, `has_signal` probes).
  871 python tests green (was 845).
- Docs: HARDENING tooling + checklist, EXTENDING conventions, BUILD validation list, README
  offline-gate commands.

## [Unreleased] — The string-format contract became a gate: sprintf's rules, pinned offline (2026-09-10)

Third pass of *what is the weakest section of an all-green tree?* The ClassDB is pinned, the node
tree is pinned; what remained was the tree's largest single runtime-error surface with zero
coverage: the **`%` format operator**. The tree formats ~833 messages with it — every `push_error`,
every authored-content validation problem, every combat-log line, every test `why` — and the pinned
engine's semantics (verified in the 4.4.1-stable source: `String::sprintf` in
`core/string/ustring.cpp`, `OperatorEvaluatorStringFormat` in `core/variant/variant_op.h`, the
parser's "Allow for trailing comma" in `gdscript_parser.cpp`) are strict: an Array operand must
match the placeholder count exactly, a scalar operand is wrapped to one element, `%d/%o/%x/%X/%f`
demand numbers, `%v` a vector, `%c` a number or single character, `*` consumes an extra value —
and any mismatch is a runtime `ERR_FAIL_MSG`, not a warning. The tree has even been stung by the
class's cousin already: `tests/integration_stages.gd` carries a comment explaining how a
concatenated format once printed its own placeholders because `"a" + "b" % [..]` binds as
`"a" + ("b" % [..])`.

- **The gate is `tool/check_string_formats.py`** — stdlib-only, hermetic, wired into CI's
  `validate-resources` stage. It tokenizes every `.gd` in `scripts/` and `tests/` (strings,
  escapes, comments, `&`/`^` StringName/NodePath literals all understood), finds every string
  literal followed by `%`, parses the format with the engine's placeholder grammar, counts Array
  operands element-by-element (trailing-comma-aware, nesting- and string-aware), and type-checks
  obvious literal arguments against their slots. Error messages quote the engine's own reasons.
- **First-run finding, fixed:** `tests/unit/test_wave_mutators.gd` fed two values to a
  one-placeholder format (`"one_sided=%s" % [enemies, player]`) — the engine raises
  "not all arguments converted during string formatting" on it and leaves the raw format text in
  the `why` string. It shipped because the test's assertion never reads `why`, so the error was
  logged silently on every headless run. Now `"one_sided=%s/%s"`.
- **The gate is pinned by tests.** `tests/python/test_regress_string_format_contract.py`
  (25 tests): the tree runs clean with all 833 uses checked, and one synthetic negative per error
  class — array too-few/too-many, scalar with zero or two placeholders, trailing-comma and
  multi-line forms, `%%` escape, `*` dynamic width, unknown type character, incomplete trailing
  `%`, string-into-number slot, number-into-`%v`, long-into-`%c`, plus the not-format lookalikes
  (integer modulo, StringName/NodePath literals, comment content) and the concatenation
  precedence trap. 845 python tests green (was 820).
- Docs: HARDENING tooling + checklist, EXTENDING conventions, BUILD validation list, README
  offline-gate commands.

## [Unreleased] — The scene-path contract became a gate: the tree's own node names, pinned offline (2026-09-10)

Second pass of the same question — *what is the weakest section of an all-green tree?* — after the
engine-API gate pinned the ClassDB. This time the answer is the game's **own** tree contract: the
scripts navigate scenes through string-literal lookups — `get_tree().current_scene
.get_node("WorldRoot")`, `player.get_node("WeaponManager")`, `shot.get_node("Visual/Mesh") as
MeshInstance3D` — and the pinned engine's own docs (4.4.1-stable `Node.get_node`) say a missing
path "generates an error and returns null". A renamed or removed node is therefore a runtime crash
(or, for `get_node_or_null`, a permanently dead lookup), and nothing offline could see it:
gdparse/gdlint have no scene awareness, and the headless suites only exercise the paths their flows
happen to touch. The ecosystem tools that do validate scenes (godot_doctor, the engine's own
regression project) all require a Godot binary, which this project's offline gates deliberately do
not depend on.

- **The gate is `tool/check_scene_paths.py`** — stdlib-only, hermetic, wired into CI's
  `validate-resources` stage. It indexes every `.tscn` node hierarchy (types, attached scripts,
  instantiated sub-scenes resolved recursively — the enemy-variant pattern instances
  `enemy_base.tscn` and overrides nodes inside its subtree, which a naive per-file check
  mis-reports), every runtime `.name = "..."` assignment, and the autoloads, then resolves every
  string-literal `get_node`/`get_node_or_null` in `scripts/` and `tests/` against that universe.
  Severity follows the engine gate's phantom model: a path that exists nowhere fails the build
  (hard lookups crash; soft ones are dead code); scene-authored `NodePath(...)` properties — the
  arena torches' `light = NodePath("Light")` — are resolved relative to the node carrying them;
  every `[node parent="..."]` is verified instance-aware; and `get_node("P") as T` is checked
  against the declared node class via the ClassDB inheritance chain in
  `tool/godot_api_manifest.json`, because `as` silently yields null on a mismatch. `%UniqueName`
  references are checked against `unique_name_in_owner = true` from day one (none exist yet).
- **First-run finding, fixed:** `scripts/weapons/projectile.gd` looked up a `"Trail"` child that
  exists in no scene and no code, wrote it to a `_trail` member nothing ever read — a feature
  stub orphaned somewhere in the projectile rebuild, exercised on every headless run without a
  peep because `get_node_or_null` never complains. Removed (projectiles are built by the pool
  with only a Visual node; cosmetic trails attach to the player, not to shots).
- **The gate is pinned by tests.** `tests/python/test_regress_scene_path_contract.py` (24 tests):
  the tree runs clean with all 18 scenes and the real contract indexed (`WorldRoot`, `UIRoot/UI`,
  `WeaponManager`, the runtime-named managers, the autoloads), and one synthetic negative per
  error class proves each is still caught: hard and soft phantoms, orphan parents, instance-subtree
  attachments both legal and broken, dead `NodePath` properties, impossible casts (engine-typed
  node vs script class included), and `%UniqueName` without a unique flag. 820 python tests green
  (was 796).
- Docs: HARDENING tooling + checklist, EXTENDING conventions, BUILD validation list, README
  offline-gate commands.

## [Unreleased] — The engine contract became a gate: twelve phantom references exorcised offline (2026-09-10)

The question this pass asked: *what is the weakest section of a tree where all 770 python tests,
the typed-architecture gate, the guard needles, gdparse and gdlint are already green?* The answer
was in the tree's own history — the one defect class that kept shipping is the one no static pass
here can see: **references to engine members the pinned Godot does not have**. `gdparse`/`gdlint`
are syntax checks with no ClassDB; the five phantoms documented in GODOT_HANDOFF_RESOLUTION.md
(`AABB.has_area()`, `fposmodf`, `get_surface_material_override_count()`,
`NavigationAgent3D.path_height_tolerance`, `PanoramaSkyMaterial.energy`) each survived at least one
review pass for exactly that reason.

- **The contract is now data.** `tool/godot_api_manifest.json` is the 4.4.1-stable ClassDB itself —
  994 classes, 114 `@GlobalScope` functions, 509 constants, every method with its static-ness and
  return type, every property (including the undocumented-internal ones like
  `NavigationMesh.vertices`, and the property-getter/setter methods GDScript can call), reduced
  from the official source tag by `tool/build_api_manifest.py` (zipball size-verified against the
  provenance note in GODOT_HANDOFF_RESOLUTION.md) and checked in, so the gate never needs a network
  or a Godot binary.
- **The gate is `tool/check_engine_api.py`** — stdlib-only, hermetic, wired into CI's
  `validate-resources` stage. It walks every `.gd` under `scripts/` and `tests/` with a small
  typed-dataflow pass (annotations, `:=` inference through constructors/casts/literals/typed
  calls, typed parameters, autoloads, `self`/`super`, chained return types) and every
  `.tscn`/`.tres` property assignment, and its severity is the engine's own: per the 4.4.1
  analyzer source, an unknown member on a **hard-typed builtin** receiver or an unknown
  scene/resource property is a compile/load error → gate fails; the same miss on an
  **Object-derived** receiver is the engine's UNSAFE_PROPERTY_ACCESS (resolved at runtime) →
  reported as `[unsafe]` warnings, which is why legitimate guarded duck-typing (the `bus: Node`
  signal wiring, `event is InputEventKey` handlers) stays legal and visible. A miss that names a
  member existing *nowhere* in engine or project fails whatever the receiver — a phantom is a
  phantom.
- **The gate's first run found twelve live phantom references — three distinct property names
  the pinned engine does not have — that the headless-only verification had never touched**,
  all fixed:
  1. `data/audio/*.tres` × 9 authored `randomization_type = 2` — **no such property in Godot 4**;
     the engine name is `playback_mode` (enum `PLAYBACK_SEQUENTIAL = 2`), so the authored playback
     mode was dropped on every load of every player SFX randomizer. Now `playback_mode = 2`.
  2. `scenes/arena/arena.tscn` authored `PanoramaSkyMaterial.energy = 0.9` — the exact property
     the handoff resolution removed from `arena.gd`, surviving in the scene copy; no such property
     exists (no compat `_set` in the 4.4.1 source either). Removed, matching the script-side
     rationale already documented there (HDRI exposure is governed by the Environment).
  3. `scenes/arena/arena.tscn` + `scripts/arena/arena.gd` authored `Environment.background_sky` —
     the Godot-3 name; the canonical 4.x property is `sky`. The engine source shows 4.4.1 answers
     the old name only through a compat path in `Environment._set`, so it *worked* — which is
     exactly why it survived every log-based pass. Both now set `sky`, the name the ClassDB pins.
- **The gate is pinned by tests, not by hope.** `tests/python/test_regress_engine_api_contract.py`
  (18 tests) re-derives that the manifest's version equals CI's `GODOT_VERSION`, that the tree
  runs clean, and — one negative test per historical defect — that `has_area`, `fposmodf`,
  `get_surface_material_override_count`, `path_height_tolerance`, `energy`,
  `randomization_type` and a builtin-receiver typo are all still caught in their `.gd`, `.tscn`
  and `.tres` shapes, while the corrected names pass. 788 python tests green (was 770).
- `docs/HARDENING.md` lists the gate in Tooling; `docs/ARCHITECTURE.md`'s live `arena.gd` count
  re-derived (439 → 442, the delta being the engine-contract comment). The 44 `[unsafe]` warnings
  are published by the run, not silenced: they are the engine's own dynamic-access category, each
  one a guarded `is`-check or `has_signal` probe.

## [Unreleased] — Mobile input & interruption: the weakest subsystem, rebuilt (2026-09-10)

Seventh architecture pass, same method: rank `scripts/` by structural weakness, read the winner
fully, check it against how the engine and the industry model the problem, rebuild, then pin the
weak shape out. Every gate was green (770 python, 195 guard needles, typed-arch clean, lint clean),
so the ranking went by blast radius × verification gap: the touch/input layer is the only subsystem
that is both player-critical on every frame and entirely device-unverified — and it carried a live
bug, a dead project setting, two missing OS behaviors, and a latency tax. All findings below were
verified against the Godot **4.4.1-stable** source (via the GitHub API — `main/main.cpp`,
`scene/main/scene_tree.cpp`, `scene/main/window.cpp`, `core/input/input.cpp`) and the 4.4 docs,
not from memory; two of my own intermediate conclusions were wrong and are retracted inline.

- **A `_ready` tail living inside a press handler stomped the layout on every declined tap.**
  `TouchControls._ready` ended after the button loop; the three lines that belong to it
  (`resized.connect(_layout)`, `visibility_changed.connect(_on_visibility_changed)`,
  `_layout.call_deferred()`) sat inside `_on_button_pressed`, after the declined-toast emit. So
  every declined touch press — dodge on cooldown, attack during stagger, the most common taps in
  combat — re-connected both signals (engine "already connected" errors) and recomputed a
  full-rect fallback layout over UiRoot's safe-area-aware plan, jumping the stick/buttons under
  notches mid-fight; meanwhile the `visibility_changed` stuck-input backstop was never armed.
  The three lines moved into `_ready` with `is_connected` guards. Pinned twice: the python
  contract asserts the wiring is in `_ready` AND that `_on_button_pressed` contains no
  `.connect(`/`_layout` at all — the exact bug shape.
- **A dead emulation setting, replaced with the two real keys.** `project.godot` carried
  `window/handheld/emulate_touchscreen_mouse=false`, which names a setting that does not exist
  anywhere in the engine source (code search: 0 hits) — the project's stated "no emulation"
  intent was silently inactive. The real keys are `input_devices/pointing/emulate_mouse_from_touch`
  (engine default true, `main/main.cpp`) and `emulate_touch_from_mouse` (default false), now
  stated explicitly in a new `[input_devices]` section. Deliberately NOT disabled: every
  menu/skill/pause `Button` is a standard Control and answers touch only through emulated mouse
  events (TouchScreenButton docs), so mouse-from-touch is a load-bearing default, documented as
  such; the joystick's `_touch_seen` filter stays as defense-in-depth.
- **Retracted: the fps cap was never dead.** This pass first read `run/max_fps.android=60` as a
  bare key the engine would ignore (it reads `application/run/max_fps`) — forgetting that
  `project.godot` keys are section-relative, so the line under `[application]` IS the real
  setting with an Android override. An intermediate edit "fixed" it into the absolute form,
  which under `[application]` resolves to `application/application/...` — i.e. the fix was the
  bug. Caught on re-read before any gate ran. The line stands as written (the existing
  `test_android_cap_preserves_physics_and_survives_tier_changes` pin was correct all along);
  the pass adds only an explicit `run/max_fps=0` base and a comment explaining the
  section-relative rule, plus a contract test refusing absolute-form lines. A second
  near-miss of the same kind: the joystick's mouse branch LOOKED mis-nested in review and was
  exonerated by `cat -A` — the `_touch_seen` clear-and-fall-through is correct.
- **The Back button quit the app from anywhere; now it navigates.** Default
  `quit_on_go_back=true` (`SceneTree._main_window_go_back`) exits on Back — mid-combat
  included. The project now sets it `false` and `UiRoot` owns the button through
  `NOTIFICATION_WM_GO_BACK_REQUEST` (the Back button generates no input event, so `_input`
  never sees it): open modal dismissed, auxiliary screens closed, gameplay paused, pause
  resumed, game-over backed to the menu, root menu through the save-guarded quit (backgrounding
  on Android — the platform-standard Back-at-root). Transient screens ignore it. Desktop never
  emits the notification, so desktop behavior is unchanged.
- **Backgrounding no longer kills the run.** Nothing handled app interruption for gameplay:
  Android/iOS background the app WITHOUT pausing the tree (AudioManager's handler mutes for
  exactly this reason — the sim keeps running behind other apps), so a call taken mid-wave
  meant returning to a corpse. `GameRoot` now auto-pauses on `APPLICATION_PAUSED` /
  `APPLICATION_FOCUS_OUT` / `WM_WINDOW_FOCUS_OUT`, strictly gated on pausable states (an
  ungated call would warn on every menu alt-tab). No auto-resume: the pause screen owns the
  return. Desktop alt-tab takes the same path — standard for single-player.
- **Attack/dodge/swap fire on press-down, not on release.** Release semantics added the whole
  tap duration (60–150 ms) as latency to the time-critical verbs in a game about dodging
  telegraphs. The engine's own gameplay button sets the precedent (`TouchScreenButton.pressed`
  fires "when the button is pressed (down)"); menu Buttons intentionally stay
  release-activated. `_fire()` keeps its guarded-emit + command-before-haptics shape but no
  longer clears the hold — clearing there would re-arm mid-press and let a second finger
  double-fire; release branches and `cancel()` own the clearing. The UI-runner touch test now
  asserts press-fires, no double-fire, foreign-release ignored, and owning-release clears.
- **Two joystick hygiene fixes.** `_input` routed every normal thumb-lift through `cancel()`,
  dumping the 20-line input trace per release (logcat spam through all of combat) and arming
  the 80 ms resume-ignore window, which ate fast re-taps; releases now take the quiet `_end()`
  while `cancel()` + dump stay reserved for pause/focus/hide. `_draw` read
  `DisplayServer.get_display_safe_area()` (physical screen pixels) against the logical `size`
  for an inset UiSafeArea+UiLayout already own upstream — removed; the rest indicator centers
  in its own rect. Also removed: the dead `_process` paused branch in `TouchControls`
  (PROCESS_MODE_INHERIT never runs while paused; UiRoot's `cancel()` owns cleanup).
- **Drive-by: the QA script's launch package tracked the preset.** `device_qa.sh` hardcoded
  `com.laststand.arena` while the preset ships `com.laststandarena.game`, so the smoke-launch
  targeted an uninstalled package; it now greps `package/unique_name` from
  `export_presets.cfg` (`PKG=` still overrides), and `docs/DEVICE_QA.md` — which repeated the
  stale id — points at the preset too. Its checklist gains the new behaviors: press-down
  fire, no layout jump on declined taps, Back routing, interrupt auto-pause, logcat hygiene.

Gates on this round: 794 python tests (16 in the new `test_regress_mobile_input_contract`,
plus 8 from `main`'s PR #42 merged in cleanly — its game_root transition serialization
auto-merged with the auto-pause handler and composes with it: a pause requested mid-transition
is queued, not lost), `validate_guards.py` 201/0 (+6 needles), `validate_resources.py` 159/159,
`check_typed_arch.py` clean, `gdparse`/`gdlint` clean on every file touched, `bash -n` on the
QA script.
`docs/HARDENING.md` counts follow (201 needles, 794 tests; DocCountTests re-derives them),
`docs/ARCHITECTURE.md` documents the input/interruption/emulation contract, and
`tests/ui/ui_test_runner.gd` carries the press-semantics assertions for the headless run.

> **Correction to the first bullet above (added by the branch that ran 4.7.2 in CI).**
> The claim that the three parse-error toasts were only editor first-load artifacts does not
> survive contact with a headless run. `gdscript-diagnostics.yml` boots 4.7.2-stable with
> `--headless --editor` — no interactive first load, no threaded-import race — and still reports:
>
> ```
> SCRIPT ERROR: Parse Error: Class "VirtualJoystick" hides a native class.
>           at: res://scripts/ui/virtual_joystick.gd:1
> ```
>
> Renaming the class to `TouchJoystick` moved the headless suite from `1055 total, 1 failed` to
> `1095 total, 0 failed` with zero `SCRIPT ERROR` lines. So the toast was a real defect with a
> real fix, and `class_name VirtualJoystick` cannot be restored while the project targets 4.7.
> The dependency-order bugs linked above may well be real in other projects; they were not the
> cause here. The sweep's other findings in this entry are unaffected by this correction.


## [Unreleased] — Merging main back in: two sessions, one tree (2026-09-10)

`main` had moved on 28 commits while this pass was in flight — sibling sessions shipping the
performance governor, the threat-aware minimap, the audio playback engine, camera containment and the
first-of-kind announcer — so PR #41 arrived conflicting in 8 files. The rule for resolving them was
never "whose line wins" but "what does the player and the modder end up with": both intents had to
survive, and where the two branches modelled the same thing differently, this branch's data-first
shape had to absorb the other side's feature rather than duplicate it.

- **The first-of-kind announcer kept, and re-homed.** `main` gave `Narrator` an `ENEMY_BLURBS` table
  plus `note_enemy_spawned`/`announce_first_of_kind`, exactly the kind of id-keyed copy table this pass
  deletes. Keeping the table would have contradicted the phase; deleting the feature would have broken
  `run_analytics.gd`'s call and silenced a shipped player-facing voice. So `EnemyConfig` grew a
  `blurb` field, the five shipped blurbs moved into their own `data/enemies/*.tres`, and `Narrator`
  reads through the registry with a `ResourceLoader.exists()` fallback like every other reader in it.
  An archetype with no blurb (basic, fast, heavy) is deliberately never announced. `tool/validate_guards.py`
  pins both halves: the reader exists, and the table does not.
- **Decoration footprints became typed records.** `main`'s solid-prop pass published arena-local
  `{"pos", "half_size"}` Dictionaries and this branch's arena rebuild had just deleted that record
  shape; the seam between `ArenaDecorator` and `Arena` now carries `Array[AABB]` into the same
  `ArenaNavGrid.build()` the authored `ArenaObstaclePlacement` list uses, so one grid is fed from two
  typed sources. `tests/unit/test_decorator_collision.gd` was rewritten to read the same three
  properties (finite, non-empty, clear of spawns) off the boxes — a suite that reads `foot.get("pos")`
  out of an `AABB` degrades into asserting `Vector3.ZERO` over and over, which is a green lie.
- **Two camera fixes ported onto the pooled solver rather than pasted over it.** `main` fixed the
  camera resting inside a wall by allocating a `SphereShape3D` and a query object *per call* and walking
  eight steps; this branch's rebuild exists to make that path allocation-free and cache-gated. Both
  versions now exist once: an embedded verdict is computed in the pass (`safe < 0.04`), held with the
  cache, and the walk-out runs on the pooled query for at most four steps. `main`'s pitch-fanned
  whiskers came over unchanged, minus their per-whisker allocations.
- **This branch's rules were applied to code that arrived on `main`.** A prop body's
  `collision_layer = 1` and a lock-on ray's `collision_mask = 1` became `CollisionLayers` constants
  (their own test pinned the numeric text, so it now pins the named constants and the contract gate
  stopped having an exception); the wave manager took `main`'s live-enemy cap inside this branch's
  authored spawn queue rather than next to it.
- **Docs stop lying about both branches.** `HARDENING.md`'s counts are re-derived by `DocCountTests`
  and did drift (192 scripts, 186 guard needles, 766 python tests); the `arena.gd` line count in
  `ARCHITECTURE.md` was pinned to whatever the current file is, which conflates a frozen measurement
  with a live one, so it now records both: what the rebuild deleted (533 → 354) and what the file
  measures today (419, the delta being features).
- **The headless run then found two bugs of this branch's own, which is why it exists.** `arena.gd`
  asked an `AABB` for `has_area()` — that member belongs to `Rect2`; the engine spells the box one
  `has_volume()` — in the landmark nav rule phase 5 added, again in `tests/unit/test_arena_world.gd`,
  and once more in the decoration seam this merge touched. `wave_modifiers.gd` inferred a `bool` with
  `:=` from a comparison on a `Variant`. Both are *parse* errors: the script never loads, and the
  arena scene is gone. They survived two passes because an earlier parse error
  (`arena_theme_config.gd`'s `NodePath` default) stopped the compiler resolving types downstream — fix
  one and the next file in the chain starts reporting. `gdparse`/`gdlint` are a syntax check with no
  ClassDB and cannot see this class of defect at all.
  The fix is a name, not a repetition: `ArenaObstacles.blocks_nav(box: AABB)` is now the single answer
  to "does this footprint remove cells" (x and z only — a nav grid has no use for height, and a
  non-finite size fails the comparison, matching what `ArenaNavGrid.build` refuses), asked by the
  landmark and the props alike; `is_chance` is declared `: bool`; and `tests/run_tests.gd` now fails a
  suite whose `reload_failed` is set or which returns no cases, because a suite that cannot compile
  used to contribute zero cases and zero failures — which is exactly how the identical mistake in
  `test_arena_world.gd` stayed silent.

- **The same headless run then found the data itself un-loadable**, in the arena-authored files phase
  5 and phase 6 wrote: every `Color` in `data/arena_themes/*.tres` and `data/arena_landmarks/*.tres`
  was written as three components — legal GDScript, and a parse error in a resource file, because the
  text reader calls the constructor itself and wants it flat and complete — so all three themes and all
  three landmarks loaded as *nothing*, and the arenas referencing them failed with them. And thirteen
  lines of authored copy across `data/` and `assets/materials/` held raw em dashes, which the Latin-1
  text reader reports as "Unicode parsing error: Invalid unicode codepoint (2014)" rather than reading
  as written. Both were fixed by writing the data the way Godot writes it (`, 1.0` on every `Color`,
  `\u2014` in place of a raw dash), and both checks are now in `tool/validate_resources.py`, since the
  class of defect is "the .tres reader is stricter than the language" and the local gates had no idea.
  The mirror tests had to learn the same lesson: `string_value()` in the run-mode and mutator suites now
  reverses Godot's escapes, because a python test comparing raw file text to what the engine will hand
  the game is comparing two different strings.

- **The third headless round found five more defects of the same family, and one of them was this
  merge's own doing.** `ArenaDecorator._place_structural(count, half: float, ...)` got a new
  `var half := ...` from the footprint rewrite, and GDScript refuses a local that re-declares a
  parameter of the same function — a parse error, so the decorator, the arena and the integration
  stages all failed to load behind it. `ArenaHazards._require_victims()` returned
  `_victims_this_tick`, an identifier the file never declared (the member is `_victims_last_tick`);
  the harness guard this branch added probed `script.reload_failed`, which is the GDScript 3 name —
  4.x asks `can_instantiate()`. And the run died on `ContentRegistry halting: 4 invalid/missing
  content file(s)` because `GameMode._all_configs()` returned the registry's game-mode table *whenever
  the registry existed*, including while `ContentLoader` was still loading it: `data/hazard_modes/*.tres`
  validate their `mode_id` through `GameMode.is_known()`, and mid-load the registry is present and
  empty, so four shipped overlays were told their modes do not exist and the registry asserted itself
  down for the whole headless run.
  Each got the same treatment: the bug fixed at the source, and the *class* closed locally rather than
  the instance. `tests/python/test_regress_final_sweep.py::ScopeShadowTests` now walks every `.gd` under
  `scripts/` and refuses a `var`/`for` that shadows its own function's parameter (the indentation
  rule is enough, and `gdparse` has no scope analysis to offer). Both content resolvers —
  `GameMode` and `WaveMutators`, the two that ask the registry for a whole table — fall back to the
  content folder when the registry is empty, and cache a disk scan only once it has found something, so
  a mid-load call can neither get a false "no" nor poison the cache with one; the pin covers both
  files, because one rule in one resolver is the same bug with a shorter fuse. The hazard gate's
  counter is now a declared member, and its python test asserts the declaration exists, not just the
  line that reads it. A repo-wide sweep for the remaining shape — a private member assigned but not
  declared in its file — found nine hits, all of them `static var` reads, so that class is closed.

- **A fourth headless round, and the pattern held: five more defects, none of them visible to any local
  gate.** `ArenaHazards._authored_layout()` and `._mode_layout()` returned
  `loaded.hazard_layout if loaded != null else []` — a ternary whose type is the plain `Array` the untyped
  arm contributes, refused by the declared `-> Array[HazardPlacement]`, so the hazard layer never loaded and
  four hazard/nav tests failed on behaviour they were never actually able to exercise. `main`'s new
  `test_safe_player_spawn.gd` steered the spawn solver through `arena._landmark_half`, the duplicate field
  phase 5 deleted, and would have been silently broken (`Invalid assignment of property or key`) had the
  file compiled at all: `Arena` now carries a named seam, `set_landmark_block_half()`, with the production
  value assigned from the landmark at build, so there is still exactly one copy of the centrepiece's shape
  in play. `test_status_manager.gd` called `move_speed_factor()` on a `StatusEffectConfig`, where it is a
  float field — and the `:=` on that call is the same Variant-inference failure as `is_chance`. The arena
  lore rule ("an arena that owns a scene owns its three lines") was in `ArenaConfig.validate()`, where it
  rejected every hand-built probe arena in the suites while saying nothing about the shipped files it was
  written for; it moved to `ContentLoader`, which is the one that knows the difference. And `Boss Rush`'s
  escalation assertion in `test_game_modes.gd` (and this file's own earlier prose) claimed sizes 4/5/7/9/12
  for a formula that produces 4/5/7/8/10 — the `.tres` rows and the python mirror were right, the quoted
  number was not, which is what happens when a number is written from memory instead of from the code.
  `test_regress_final_sweep.py::ScopeShadowTests` and four new guard needles (the seam, the loader check,
  the deleted field, and a ban on `else []` in the hazard layer) pin the shapes.

Gates on the merged tree: 768 python tests, `validate_guards.py` 190/0 (that line first said 186,
quoted from the count before the round's own four needles were added — the same mistake the entry is
about), `validate_resources.py` 159/159 (with the two new checks verified against planted defects),
`check_typed_arch.py` clean, `gdparse`/`gdlint` clean on every file the merge touched.

- **A fifth headless round, and the mask finally came off the behaviour.** Nine items became eight
  fixes, and for the first time the CI log named its own cause: the harness now annotates a suite that
  cannot compile (`Suite compile failure::res://tests/unit/test_status_manager.gd has a parse error`)
  instead of letting it evaporate into `Nonexistent function ... (via call)`. That one line is the
  difference between a 70-second run with a list and a 70-second run with a mystery.
- **A missing `return` is a parse error, and a parse error is a black hole.**
  `tests/integration_stages.gd::_run_run_definition_integration` ended on `results.append({...})` with
  no `return results` — "Not all code paths return a value" — so the whole integration script refused
  to load and *every* stage in it reported a nonexistent function. `EveryPathReturnsTests` now sweeps
  `scripts/` and `tests/` for a function declaring a return type that contains no `return` statement.
- **A resource built, configured, and never attached is invisible to every tool and to the player.**
  `ArenaObstacles.build_nodes` sized a `BoxMesh` and left it on the floor: the obstacle bodies were
  solid, and the walls were not drawn. `main` had just fixed that exact line in its own hardening pass;
  the auto-merge preferred this branch's refactored file and silently dropped it. Restored, swept
  repo-wide (no `*Mesh`/`*Shape3D`/`*Material3D` local in `scripts/` goes unattached or unreturned),
  and pinned twice over — `AttachedResourceTests` in the python suite and the existing Godot body test,
  which is what actually caught it. **Auto-merge is not review**: a clean resolution means the hunks
  did not overlap, not that both intents survived.
- **Three fixtures were the bug, not the code.** `test_hazards.gd`'s "a hazard that targets nobody is
  refused" flipped one of the two `affects_*` flags, so the rule under test correctly stayed quiet;
  its spatial-index check packed all forty bodies into two cells and then blamed the grid for visiting
  everything; and `test_nav_grid.gd`'s layout-parity check compared the *mirror-expanded* authored list
  against the raw two-row fallback, so the sizes differed by construction (the Pit's authored rows are
  verbatim the fallback's geometry: `(6.5,0,6.5)`+pillar mirrored on both axes, `(3.6,0,0)`+block
  mirrored on x). A test that passes for the wrong reason is worse than one that fails.
- **Two assertions found a real behavioural defect.** `HazardInstance.advance()` let a periodic pulse
  that never detonated drift to twice its period and then snap back, which left the clock up to a full
  period ahead of the telegraph it had already shown — the reported `timer=5.95` is 200 ticks at 0.05
  against a 4.05 s period, arithmetic no earlier run could reach. The clock is now capped at one
  period, so an idle hazard simply stays *due*. The once-per-second cooldown sweep also has a monotonic
  `prune` budget, which the fixture violated by pruning at a time before its own last stamp.
- **`StatusEffectConfig.move_speed_factor` is a field, and the round that "fixed" it fixed one of the
  two call sites.** `haste.move_speed_factor()` in the cleanse assertion kept the file unparseable,
  which in turn kept the corrected `expected_move` arithmetic from ever running.

Gates on this round: 770 python tests, `validate_guards.py` 194/0, `validate_resources.py` 159/159,
`check_typed_arch.py` clean, `gdparse`/`gdlint` clean on every file touched.

- **The seventh headless round: the instrumentation answered its own question, and the answer was a
  shipped feature that never worked.** `has=false stacks=-1 full=true attack=true hp=true` — the enemy
  was scaled correctly (32.0 hp, 9.0 attack) and had no status manager at all: `SpawnManager` stamped
  the wave's status inside `_apply_spawn_scaling`, which runs *before* `_activate_enemy`, and
  `EnemyBase` resolves its `StatusManager` component in `_ready()`. So `_stamp_wave_status` found
  `get_status_manager() == null`, returned quietly, and Ember Winds set the player alight for every
  wave of a mutator whose whole promise was lighting the arena's air for the enemies in it. The stamp
  now happens after activation, for burst children too. A no-op that reads as code is the worst failure
  this tree has: no error, no assertion, no crash — only a game that is quietly half as interesting.
- **And the clamp cost one test its honesty.** `test_status_skills.gd` asked `tick()` for whole quanta
  with a 1.1 s frame — precisely the input the new payout bound refuses — so it now feeds two legal
  frames (0.5 s and 0.6 s, remainder carried in the accrual), which exercises the carry the one-liner
  never touched. `docs/HARDENING.md` and one more guard needle (`_stamp_wave_status_on_spawn`, the
  ordering that made the difference) follow the change.

- **The eighth headless round: one failure left, and the answer was in the fixture, not the game.**
  The stage now prints what it is looking at, and `tree=true, kids=HealthComponent, EnemyStateMachine`
  said the rest: `_pack_test_enemy_scene()` packs the harness's enemy out of code with two children, and
  `EnemyBase` resolves its `StatusManager` from the scene — so the fake enemy had no status manager to
  stamp, `_stamp_wave_status` found `get_status_manager() == null` and returned quietly, and the
  assertion failed for a reason that no amount of reading the production code could have revealed. The
  fixture gains the third child (owned before `pack()`, the rule that entry already documents for the
  other two), and the audit test that pins that ownership now pins the status manager with it, so a
  fixture cannot be quietly incomplete again.
- **Two of my own earlier conclusions were wrong and are retracted.** Round seven read the same
  `has=false` and concluded the stamp ran too early in the spawn sequence; `tree=true` shows the enemy
  was in the tree and `_ready()` had long since run, so the stamp's old position was never the problem
  (the move to `_stamp_wave_status_on_spawn` stays, for the reason now written on it — a status needs a
  resolved node, numeric scaling does not — not because it fixed anything). The same entry credited
  `get_status_manager()`'s re-resolve with curing a shipped immunity: it does not, because no shipped
  enemy scene lacks the node. Both comments were rewritten to say what is true, since a comment that
  invents a fixed bug is a trap for the next reader. And `wave_effect=<null>` in the diagnostic was the
  stage reading its own post-cleanup state, which is why the record is now captured at spawn time.

Gates on this round: 770 python tests, `validate_guards.py` 195/0, `validate_resources.py` 159/159,
`check_typed_arch.py` clean, `gdparse`/`gdlint` clean on every file touched.

- **A sixth headless round: three items left, all of them behaviour, and one still open on purpose.**
  With every suite compiling, the headless job reported three failures instead of nine, and the shape
  of the remaining three said the parse-error cascade had finally ended.
- **A DoT hitch clamp that was documented but not implemented.** `test_status_manager.gd`'s
  "one huge frame is clamped to 0.5 s of DoT, not the whole gap" reported `quanta=1 total=16.0`:
  `StatusEffect.tick()` bounded a frame at 64 *ticks* and at the effect's remaining duration, which
  for a 4-second burn is the same thing — so a 5-second frame paid out four seconds of damage in one
  payload. The expiry clock deliberately keeps running on the real delta (a hitch must not stretch a
  status's life); only the payout is capped, by the new `MAX_PAYOUT_DELTA`.
- **`rank 8 means tier 3` — a number in a comment again.** The payout check hard-coded
  `challenge_tiers[0]` for a rank-0 run and `challenge_tiers[3]` for rank 8. The ladder's rows unlock
  at 0/2/4/6/8, so rank 8 selects the fifth; and the harness boots no `GameRoot`, so the run it scores
  is a *standard* one, whose payout must ignore the ladder entirely. The check now asserts that
  property directly and derives the rung through `tier_index_for_rank`, comparing the row's own
  `unlock_rank` against the rank rather than trusting an index — the second time this branch wrote a
  number from memory where the file had the answer.
- **One check is instrumented, not guessed.** "the wave's folded record scales spawns and stamps its
  status" reported a bare `record=false` across five sub-assertions, and reading the spawn, stamping,
  stacking, flooring and config-sharing paths in turn produced seven plausible causes and no evidence.
  The check now names each clause and prints the numbers behind it (`stacks=`, `max=`, `atk=`), which
  is the difference between the next run answering the question and another round of reading.
- `docs/ARCHITECTURE.md`'s description of the payout stage followed the rewrite; the two python mirrors
  that pinned `active_delta = minf(delta, remaining)` and `challenge_tiers[3]` now pin the new shapes —
  a mirror that pins an old line is a liability, not a test.

Gates on this round: 770 python tests, `validate_guards.py` 194/0, `validate_resources.py` 159/159,
`check_typed_arch.py` clean, `gdparse`/`gdlint` clean on every file touched.

## [Unreleased] — A run's modes, its ladder and its voice are authored data (2026-09-10)

Sixth architecture pass, same method: rank `scripts/` by structural weakness, read the winner fully,
grep its blast radius, check it against how the engine and the industry model the problem, rebuild,
then pin the weak shape out with tests that have to fail when the defect is re-introduced. The target
was the run-definition layer — `scripts/meta/game_mode.gd`, `prestige.gd`, `narrator.gd` — three
files whose job was to answer "what is this run like, and what does it sound like" out of code
tables.

- **A mode is a `.tres`.** `GameMode.CATALOG` was a Dictionary of Dictionaries — fourteen authored
  keys per mode, inside the script that ran them — while `GameMode`'s own docblock and
  `docs/EXTENDING.md` both promised that adding a mode was data-only. The seven shipped modes are now
  `res://data/game_modes/<id>.tres` (`GameModeConfig`, 21 exported fields), registered by
  `ContentLoader` alongside the rest of the content (159 validated files, up from 151), and Run Setup
  lists whatever the folder holds. Thirteen `def(id).get("key", default)` accessors are gone; a
  mode id that resolves to nothing is now a `push_error` plus Standard instead of an invisible 1.0×
  run wearing another mode's name.
- **Composition rules are fields, not arms.** Five per-mode queue builders (`_boss_rush_queue`,
  `_survival_queue`, `_defend_queue`, `_collect_queue` and a fifteen-arm `match wave_number` of
  literal archetype lists) became `wave_plans` (inline `GameModeWavePlan` rows),
  `planner_wave_offset`, `planner_wave_floor`, `every_n_waves` and `every_n_append`: Boss Rush's
  4/5/7/9/12 with `heavy` only from wave 3, Campaign's fifteen waves (1–10 and 14–15 scripted,
  11–13 delegated to `WavePlanner` at wave+2), Survival's `+1 heavy` every 4, Defend's every 3,
  Relic Hunt's `+1 ranged` every 4. The campaign's *length* had been copied into a third place
  (`max_waves: 15`); it is one array now.
- **Three dead fields deleted, two authoring walls removed.** `narrator_id`, `boss_interval` and
  `unlock_prestige` were authored on all seven modes and read by nothing; `collect_target` existed on
  two of seven. `upgrade_every` went through `maxi(…, 1)`, so "never offer an upgrade" could not be
  written down — it is `@export_range(0, 20)` now, with 0 meaning never, and every numeric field on
  the five new config types is range-bounded so the editor refuses a value the code would clamp.
- **`Narrator` knows no ids.** `ARENA_LORE`, `MODE_INTRO`, `CAMPAIGN_BEATS` and `ENEMY_BLURBS` (five
  of eight archetypes, read by no caller) are deleted: arena flavour is three `ArenaConfig.lore_*`
  fields authored in the arena's own file, wave flavour is the mode's beat row, and the victory line
  is `GameModeConfig.victory_line`. An authored-empty line emits nothing at all — the milestone
  branches used to put a banner on screen with no text in it. `run_setup_panel` prints
  `arena.lore_intro` instead of guessing "Classic survival" from tags.
- **The prestige ladder is one authored file.** `res://data/prestige/ladder.tres`
  (`PrestigeLadderConfig`) carries the cost curve, `max_rank`, both per-rank bonuses,
  `armory_completion_required`, eleven titles, five `ChallengeTier` rungs (ranks 0/2/4/6/8,
  1.5→3.5 score) and six `PrestigeUnlock` rows (ranks 1, 2, 3, 5, 7, 10). `Prestige` resolves, caches and *reports*:
  `can_prestige()` gained `&"unavailable"` (a missing ladder used to read as "you may prestige"),
  `clamp_rank()` replaced the `min/max` arithmetic that zeroed a save's rank when content failed to
  load, and `title_for` stopped answering `"Unproven"` at rank 9 through a `.get` default. The
  `min(floor(rank / 2), size - 1)` index into an int-keyed Dictionary had let a gap in the ladder pay
  the top rank the *easiest* run at full price; rung order, monotonic cost and bonus, title coverage,
  reachability of the top rung and the cosmetic ids' existence in `Cosmetics` are all `validate()`
  rules now, one of them (`min(idx, size-1)`) only expressible once the cross-row rules moved to the
  config that owns the rows.
- **The challenge protocol is closed across the seam.** Which mutators a prestige-scaled run forces
  had been split between `GameMode.CHALLENGE_MUTATOR_POOL` and numbers in `Prestige`, joined only by
  `mini(count, pool.size())`. Per-mode `prestige_mutator_pool` × per-tier `mutator_count`,
  cross-checked at load — with tier 0 required to *equal* the mode's own `score_mult`/`currency_mult`,
  so the ladder cannot silently rebase a mode.
- **Nothing the player reads moved.** The four modes that used to fall through a `match` default still
  emit `"Victory. The stand holds."`; every label, blurb, intro, beat, objective string and payout in
  the seven mode files and the ladder is mirrored value by value in
  `tests/python/test_regress_run_modes.py`. The `armory_panel` row that read `"ARMORY 60%+"` computes
  it from `Prestige.armory_completion_required()`.
- **Three of eight consumers needed no change at all** (`wave_manager.gd`, `run_scorekeeper.gd`,
  `objective_director.gd`): their call sites were already spelled the way the new layer exposes them,
  which is what "the public API survived" is supposed to mean. The rest moved off record-keys onto
  fields — `Prestige.clamp_rank`, `arena.lore_intro`, `Prestige.armory_completion_required`.
- **Tests.** `tests/unit/test_game_modes.gd` (56 cases headless: resolvers, every `validate()` refusal
  quoted from source, shipped data clean); `tests/python/test_regress_run_modes.py` (43 cases: the
  shipped mirror, the no-dead-field rule, per-field record-literal bans, no mode-id comparison
  anywhere in `scripts/`, loader/registry/consumer pins, and `DocCountTests` re-deriving the
  doc's own counts from the tools); a new live integration stage
  `_run_run_definition_integration` (4 cases) chained from the encounter stage, which is the only
  place that proves a real `Narrator.announce_wave` emits the campaign row's copy, that
  `Prestige.ladder()` still resolves in a tree that booted no registry, and that a challenge kill pays
  exactly one multiplier. `tool/validate_guards.py` 99 → 175 checks; `docs/EXTENDING.md`'s game-mode
  and prestige sections rewritten (they had told modders to append to `GameMode.CATALOG`) and
  renumbered out of a duplicate-§11 collision. **Mutation matrix: 32 reintroduced defects, 32
  caught** — and five of those only after the matrix exposed that a whole-file skip had left
  `game_mode.gd` unbanned, that a `needle in file` check was satisfied by the *other* branch of the
  same guard, that a comment naming a deleted call kept its presence-check green, and that two
  copy-literal regressions nothing was watching at all.
- **Behaviour changes worth knowing at review time.** A save naming a removed mode id, or a
  `RunState.arena_id` nobody authored, is reported now (`push_error`) instead of being laundered into
  Standard's payout / The Pit's lore; milestone waves with no authored lore are silent; `wave 0`
  cannot trigger the "wave 10" line; `ChallengeTierConfig` is `ChallengeTier` (`*_config.gd` names are
  reserved for loadable, validated configs).

## [Unreleased] — The wave's rules became data, and one typed record (2026-09-09)

Fifth architecture pass, same method: rank `scripts/` by structural weakness, read the winner
fully, check it against how the engine and the industry model the problem, rebuild, pin the weak
design out. The target was the wave-mutator subsystem — the smallest file in the ranking
(`scripts/waves/wave_mutators.gd`, 155 lines) and the one whose Dictionary boundaries had the
widest blast radius (`SpawnManager`, `WaveManager`, `DifficultyDirector`, `RunScorekeeper`,
`WeaponManager`, `RunState`, the daily challenge and the run-summary panel).

- **Mutators are `WaveMutatorConfig` resources now.** `definition()` was a `match mutator_id`
  over seven hand-written Dictionaries, and its last line returned a *neutral* Dictionary for any
  id it did not recognise — an unknown mutator was not an error, it was a wave that announced a
  modifier and applied nothing. The seven shipped ones are `res://data/mutators/<id>.tres`,
  registered by `ContentLoader` (151 validated files, up from 143), and their ids are checked at
  load wherever they are referenced: `WaveConfig.arena_modifier_ids`, `GameMode.forced_mutators`,
  `GameMode.CHALLENGE_MUTATOR_POOL`, and each mutator's `status_effect_id`. A mutator whose every
  knob is neutral is refused outright: that is a banner line, not a rule.
- **Five authored knobs started working.** Grepping every key against every consumer found
  `currency_mult` (Bounty Hunt's entire "double currency" pitch) and `player_damage_mult` (Glass
  Cannon's "take +25%") dropped by `set_wave_modifiers`, which copied four named keys and
  documented "unknown keys are ignored"; `score_mult` copied but read by nobody, though six of
  seven mutators advertised richer kills; `burn_tick` — Ember Winds' whole mechanic — read by
  nobody, so it was a banner and a signal; and the director's own `score_mult`, so "dominating
  players get richer waves" was a comment. They now fold into `RunScorekeeper` (score and
  currency, beside the upgrade/mode/prestige multipliers), `WeaponManager` (player damage, beside
  the status factor, refreshed on the wave seam `set_current_wave`), and the arena itself
  (Ember Winds stamps a real `StatusEffectConfig`, `data/status/ember_air.tres` at 1.5/s, through
  `StatusManager.apply_effect` on enemies as they spawn and on the player while a wave arrives).
  `severity` finally escalates the wave banner: `minor` warns, `major` is `danger`.
- **One typed record per wave instead of three Dictionaries.** `WaveModifiers` is what
  `WaveManager._fold_modifiers()` produces once per wave — plan scalars, then the
  `DifficultyDirector`'s bounded nudge, then the mutators, then `clamp_bounds()` — and what
  `SpawnManager`, `RunScorekeeper`, `WeaponManager` and `RunState` read field by field.
  `SpawnManager`'s `_difficulty` and `_wave_mods` are gone (8 string-keyed reads removed),
  `DifficultyDirector.next_wave_multipliers()` returns the record, and the only Dictionaries left
  in the pipeline are `WavePlanner.calculate_difficulty_scalars()`'s (a test-pinned scalar
  function, absorbed by `apply_plan_scalars`) and `debug_dictionary()` at the debug-snapshot
  boundary. Stacking rules are authored per field in `WaveMutatorConfig.FOLD`
  (`multiply`/`add`/`max`) because "how do two modifiers combine" has no generic answer; the
  bounds live with the fold, so a consumer cannot forget its clamp.
- **`RunState.active_modifiers` is written.** It was cleared, duplicated, serialized and shown in
  the run summary — and never assigned, so every summary in the game reported no mutators.
  `set_wave_modifiers()` publishes it from the folded record at each wave launch (ids only:
  multipliers are re-derived per wave and stay out of the save), and the daily card now tooltips
  each mutator's `description` instead of leaving that field in the inspector.
- **Selection stayed deterministic, and got smaller.** `roll_for_wave` keeps its
  `(seed, STREAM_WAVES + wave * 7)` stream, its 4/8-wave shape and its pool order — which is
  authored as `roll_order` now, because `DailyChallenge.mutators_for_stamp()` pops indices out of
  that list and `GameMode` indexes its own challenge pool; `min_wave` replaced
  `if wave < 6: pool.erase(GLASS_CANNON)`. Ties in `roll_order` are a startup error, and the
  unknown-id path warns instead of neutralising.
- **Pinned out:** `tests/python/test_regress_wave_mutators.py` (43 checks: mirrors every shipped
  number, refuses `match mutator_id`/`definition()`/Dictionary multiplier records in `scripts/`,
  requires every field of the record and every field of the config to have a reader, pins the
  fold order, the roll stream, the registry wiring and the doc text),
  `tests/unit/test_wave_mutators.gd` (15 headless cases: fold arithmetic, bounds, targets, the
  neutral refusal, roll gating, the run mirror) and `tool/validate_guards.py` 61 → 99 needles.
  641 python tests green (was 598), and 38 of 38 reintroduced defects caught by a mutation pass over a scratch copy. Two live-stage additions in `tests/integration_stages.gd` assert the
  folded record reaches a spawned enemy's health, damage *and* status list — a path that could
  not exist before, because nothing stamped anything.
- **Docs that lied:** `docs/EXTENDING.md` §11 described "`WaveMutators` (`ALL`,
  `resolve_for_wave`, per-id `apply_to_wave_mods` scalars)" — a method name that never existed and
  an `ALL` const that does not any more; rewritten as "add a mutator without touching code".
  `docs/ARCHITECTURE.md` gained "Wave rules (mutators, the director, and the one folded record)".
  `docs/HARDENING.md` told contributors to "add a `_validated_*` helper", the exact pattern its
  own gate rejects; that section now says what replaced it (load-time `validate()`, typed records,
  "a field must have a reader").

## [Unreleased] — The arena's authored world: theme, landmark, cover (2026-09-09)

Fourth architecture pass, same method: find the weak subsystem, read it fully, check it
against how the engine and the industry do it, rebuild, then pin the weak design out. The
target was the arena's *identity*: `scripts/arena/arena.gd` and its two helpers. Everything
about how an arena looks and what stands in it lived in code that branched on the arena id
string, so a new arena `.tres` could not fail — it just quietly got someone else's arena.

- **`THEMES` and `PANORAMA_SKIES` are gone; the look is a resource.** `arena.gd` held
  `const THEMES := { "ember_crucible": { "sun_color": Color(…), … }, … }` and applied it with
  fourteen `preset.get("…")` reads — four of them wrapped in `float()` — so every key had a
  name-based fallback, and the six numbers every arena shared (ambient energy, the glow triple,
  fog-sky-affect, tone map) were welded into `_apply_sky_and_light`. It is `ArenaThemeConfig`
  (`data/arena_themes/<arena_id>.tres`) now, referenced from `ArenaConfig.theme` by hard
  resource path: every look number is authored, all of them range-enforced, and a NaN channel /
  a fog density that hides the far half of the floor / a `user://` HDRI is refused at load.
  `apply_theme()` no longer takes an id and can no longer `return` silently on a table miss;
  `theme == null` is the one authored way to keep the scene's own look. `@export var config_path`
  was deleted unread — no scene set it and nothing had ever loaded it.
- **The landmark builds nothing instead of defaulting to an obelisk.** Two `match kind`
  statements with `_:` arms chose the silhouette and hard-coded its geometry, light and colours;
  the collision body and the nav-grid footprint were two hand-written numbers per kind that
  could disagree; and `_hd_marble_mat` was dead code. `ArenaLandmarkConfig` authors
  `kind`/`shape`/`footprint_half`/tint/emissive/one point light, and `ArenaLandmark` (new, 204
  lines) builds the silhouette from them; `arena.gd` went 533 → 354. `footprint_half` is now
  *both* the body and the blocker (`footprint_half * scale`), so physics and AI intent cannot
  drift apart, and an unrecognised `kind` is a `push_error` plus nothing built — no mesh, no
  body, no phantom blocker.
- **Obstacle layouts are authored, and stop being a Dictionary record.**
  `ArenaObstacles.layout_for(arena_id, half)` was `match String(arena_id)` emitting
  `{"pos", "half_size", "kind"}`, read back with `.get("pos", Vector3.ZERO)` by the collision
  builder *and* by `ArenaNavGrid.build` — which is exactly how a footprint convention had
  already been misread once (the grid's old comment records it). `ArenaConfig.obstacle_layout`
  is an `Array[ArenaObstaclePlacement]` with a `mirror` (the same vocabulary `HazardPlacement`
  uses, pinned against the two drifting apart), positions are in *that arena's* metres and are
  never rescaled, and the geometry crosses API boundaries as `Array[AABB]`. The records' `kind`
  field disappeared rather than getting a job: nothing had ever read it. An arena that authors no
  layout still gets The Pit's pattern via `fallback_layout(half)`, now the only place that scales
  by the floor size.
- **New cross-check:** an obstacle whose centre lands inside the landmark footprint is a load
  error (`ArenaConfig._obstacle_landmark_overlap`) — it draws nothing, is still solid, and blocks
  the AI away from a wall nobody can see.
- **Docs that lied are fixed.** `docs/EXTENDING.md` §3 promised "additional arenas = a new scene
  + an ArenaConfig" while three files keyed behaviour on the id; §3 is now an eight-step
  authoring guide, `docs/ARCHITECTURE.md` gained "The authored world", and `GODOT_HANDOFF.md`
  item 4 stopped telling the next engineer to grep a table for obstacle boxes. The one remaining
  arena-id branch is `ArenaDecorator.decorate()`'s prop scatter — seeded from the id, so
  re-keying it would move every brazier and banner in a shipped arena, which needs a running
  game to sign off. It is pinned to exactly one `match String(arena_id)` so it cannot spread.
- **Tests.** New `tests/unit/test_arena_world.gd` (15 cases: mirror math against the hazard
  vocabulary, footprint derivation, shared-resource safety, fallback identity, every shipped
  theme/landmark/obstacle number, all validation rules, the refusal path, footprint→grid
  blocking) and `tests/python/test_regress_arena_world_data.py` (32 checks: the id tables pinned
  out, the Dictionary records pinned out, the type contract, every shipped number audited
  against the deleted tables, and the docs). `test_arena_obstacles_node.gd` now asserts the theme
  actually reached the live `WorldEnvironment` and sun — `apply_theme`'s silent return was the
  whole bug — and that the landmark's body *is* the authored footprint. Four stale pins were
  re-pointed at the new design (the `THEMES` milestone check, the per-arena panorama check, and
  the ember 8.5 m / gate-literal hardening checks): all four now assert the guarantee against the
  data the game loads instead of the expression that used to produce it. The re-pin of the hazard
  placement-expansion check also fixed a scoping bug of our own — it scanned every `mirror` in
  the arena file and started counting the new obstacles as hazards (17 for an 11-hazard arena).
- **Verified by mutation, not by inspection:** 43/43 injected regressions were caught — tables
  returning, key-bags returning, `pos` misread as the min corner, expansion writing through a
  shared resource, the fallback skipping `expand`, the silent landmark default, a deleted
  validator rule, a reworded message, a shrunken colour-audit list, a deleted range hint, and
  drift in every shipped colour, footprint and coordinate.
- Gates at this commit: 598 python tests (from 566), `check_typed_arch` clean (174 classes, from
  170), `validate_guards` 61 (from 53), `validate_resources` 143 files (from 137), assets OK,
  `gdparse`/`gdlint` clean on every touched file.

## [Unreleased] — Status effects: the read path became a cached fold (2026-09-09)

Third architecture pass. Same method as the previous two: find the subsystem whose cost is
paid most often, check it against how the engine actually works, rebuild the weak part, and
pin the weak design out. This time the target was `scripts/status/` — the per-entity
component that movement, AI, damage and the HUD query dozens of times per frame. Rationale
in `docs/ARCHITECTURE.md` ("Status effects"); authoring notes in `docs/EXTENDING.md` §10.

- **The five derived numbers are folded once, not per read.** `move_speed_factor()`,
  `outgoing_damage_factor()`, `incoming_damage_factor()`, `is_stunned()`/`is_rooted()` and
  `shield_remaining()` used to re-walk an untyped `Dictionary`, cast each value with
  `as StatusEffect` and call `pow()` per effect per axis — ~80 walks per physics tick at a
  full wave, because `player.gd` and `enemy_base.gd` ask every tick and every hit asks
  twice more. They are field reads on a fold that is recomputed lazily when
  `_aggregates_dirty` is set by exactly the four things that can change it: an application,
  a removal, an absorbed shield layer, and the tick in which `remaining` crosses zero
  (`StatusEffect.reapply()` now returns whether it changed anything a fold depends on, so a
  duration-only refresh — burn re-applied every swing — costs nothing). This is the Dirty
  Flag pattern, the same mechanism Godot uses for a body's global transform and Unreal's
  GameplayEffects uses for attribute aggregators, chosen over re-evaluating per frame.
- **The tick stopped allocating.** `_effects.keys().duplicate()` per entity per frame (two
  Arrays; `keys()` already returns a fresh one, so the `.duplicate()` was pure waste) became
  two reused scratch arrays guarded by a `_ticking` re-entrancy flag — guarded because
  `HealthComponent.damaged` → `cleanse_all()` from a listener is a real path here (Purge
  pickup), and erasing while iterating a Dictionary is undefined per the Godot docs. The
  per-effect `fx.config.validate()` inside the tick is gone: it re-ran a 14-rule authoring
  audit 60 times a second per effect to catch "an old save with bad numbers", and status
  state has never been serialized (SaveManager has no status path).
- **Typed table, and the shield layer moved home.** `Dictionary[StringName, StatusEffect]`
  replaces `Dictionary` + casts (runtime-only on purpose: 4.4 cannot serialize a typed
  Dictionary of Resources in a `.tres`, godot#100889, nor accept one from
  `JSON.parse_string`, godot#97137). The parallel `_shield_layers` Dictionary keyed by
  effect id — written on every application, erased on every removal, re-summed from
  `.values()` on every absorbed hit — is now `StatusEffect.shield_layer`, so `absorb_direct()`
  is one allocation-free walk and `_sync_shield_pool()` disappeared. `_power_for` returns a
  `Vector2` pair instead of a `Dictionary` record with three string lookups per application.
- **An idle component is not ticked.** `set_physics_process(false)` while the table is empty
  (the repo's own convention: `enemy_base`, `pickup`, `player_feedback`, `projectile`),
  because with 40 enemies alive "no effects" is the most common state and used to cost a
  `_physics_process` call plus an `is_empty()` test anyway.
- **Real defect fixed, not just moved:** the `SOFT_LOCK_CAP_SECONDS` "hard stop" for
  stun/root durations was written as a `maxf` floor, so an authored `duration = 30` with
  `stuns = true` froze the player for 30 s under a comment claiming it was capped at 3.
  Initial duration, `set_power_modifiers` and all three stack-mode branches now route through
  the ceiling. Shipped data is unaffected (`stun.tres` is 1.5 s); no shipped effect is
  permanent, and none uses `roots`.
- **`StatusEffectConfig` now extends `ValidatedConfig`**, so its audit runs at load through
  `ContentLoader` and `ContentRegistry` turns a bad `.tres` into a startup error. This is the
  first conversion off the documented "needs a real run to prove the shipped files pass"
  list — the proof was built without a binary instead: `tests/python/test_regress_status_hot_path.py` (35 checks)
  mirrors all 14 rules in python, reads its defaults and rule text out of the GDScript class
  so the mirror cannot drift, and audits every `data/status/*.tres`. The remaining four
  (`SkillConfig`, `WeaponConfig`, `AudioConfig`, `BossPhaseConfig`) stay listed, still
  pinned as a shrink-only set. Related inconsistency fixed while there:
  `duration`'s `@export_range` minimum of 0.05 made "0 = permanent until cleansed" — which
  `validate()` and `is_permanent()` both define — unauthorisable in the inspector (guard
  needle re-pinned, same fix as `HazardConfig.period`).
- **Behaviour preserved deliberately**, and pinned so the cache cannot be quietly wrong: the
  multiplicative axes still include an effect that expired this tick but has not been removed
  yet (what the per-read scans did; it self-corrects in the same tick), the stun/root locks
  still exclude it, `ADD` shields still grant only newly acquired capacity, `absorb_direct()`
  still consumes layers in stable insertion order and still clamps a hit to 10k, DoT/HoT
  still route through `HealthComponent` with the authored `dot_type` and caster attribution,
  and all three signals still fire from the same points.
- **Tests.** New `tests/unit/test_status_manager.gd` (live, in-tree fixtures over a real
  `HealthComponent`, tick driven by hand at 1/8 s so DoT arithmetic is binary-exact): 90 reads
  cost one fold, a fold is not done eagerly, the cache refolds exactly once after an
  application, expiry releases the entity *in the tick it expires*, the scratch arrays come
  back empty, `cleanse_all()` from a damage signal mid-tick neither crashes nor leaves a
  stale fold, remove-during-removal is idempotent, shield pools cannot outlive their effect,
  a 5 s hitch is one DoT quanta, HoT totals are tick-rate independent, and a NaN/Inf authored
  factor cannot reach movement (60 assertions across 15 cases). New `tests/python/test_regress_status_hot_path.py` (35
  checks: shipped-data audit, mirror-coverage link, hot-path bans, invalidation completeness,
  type contract, behaviour parity, docs consistency). 566 python tests OK; 53/53 guard
  needles; typed-arch and resource gates clean.
- **Caveats.** No Godot binary in this environment: the GDScript suite is static-verified
  (gdparse/gdlint/check_typed_arch) and executes in CI, so its first run should be read
  carefully. Two pins had to move because they asserted the weak design, not the behaviour:
  `test_regress_foundational_guards.test_status_has_instance_valid` (per-tick
  `is_instance_valid(fx)` walk → typed, exclusively-owned table) and
  `test_regress_top5_hardening.test_status_manager_looks_up_bus_by_path` (kept as-is by
  preserving the accessor name `_event_bus()`; the lookup is now resolved once in `_ready`
  instead of on every application and every expiry). `weapon_manager.gd`'s pins on
  `as StatusManager` / `apply_effects(` are untouched: the public API did not change.

## [Unreleased] — Arena hazards rebuilt: authored, typed, spatially indexed (2026-09-09)

Second architecture pass, chosen by measurement rather than taste: the arena hazard
subsystem was the one place where *content was code* and where the hot path did per-tick
work the rest of the project had already designed out. Rationale now in
`docs/ARCHITECTURE.md` ("Arena hazards"); the authoring workflow is `docs/EXTENDING.md` §11.

- **Layouts and tuning became data.** `ArenaHazards._layout_defaults()` matched on
  `String(arena_id)` and hand-placed eleven/twelve hazards per arena, so adding a fourth
  arena meant editing the hazard system — and `ArenaObstacles` documented itself as
  "hand-tuned against" that function. Now: `HazardConfig extends ValidatedConfig`
  (`res://data/hazards/*.tres`, six authored hazards) + `HazardPlacement` on
  `ArenaConfig.hazard_layout` (with a `mirror` that expands one line into a symmetric set)
  + `HazardModeLayout` (`res://data/hazard_modes/*.tres`) replacing the four
  `apply_mode_pressure` match arms. All three are validated at load through
  `ContentLoader`, and the arena `.tres` files carry the exact hazard sets the deleted code
  produced (11 / 9 / 10, pinned in `tests/unit/test_hazards.gd`).
- **Six code paths collapsed into two mechanics.** `pulse` (periodic or proximity-armed
  detonation) and `field` (applies while you stand in it, throttled per victim), with
  travel as a property rather than a `_tick_mover` branch. `match h["kind"]` over an
  untyped Dictionary is gone: the mechanic is a validated id, an unknown one is a load
  error, and the runtime fall-through `push_error`s instead of silently doing nothing.
- **Typed per-hazard state.** `HazardInstance` (`RefCounted`) replaces the
  `{kind, pos, timer, node}` + lazily-created `{angle, tick}` records, so `h["timer"]`
  typos become compile-checked field access, and `_radius_of()` / `_color_of()` — which
  re-declared the same tuning a third and fourth time (the ichor radius was a bare `2.8`
  in two places, the plate blast a `+ 1.5` in the tick) — are gone. Mutable state lives on
  the instance, never on a shared config resource.
- **The visual stopped being metadata.** `HazardMarker` is built from the same radius the
  gameplay uses and exposes `set_pulse()` / `set_center()`; the marker reference is read
  through one guarded accessor (`HazardInstance.visual()`), replacing
  `set_meta("disc")` / `get_meta("disc")` round trips and the per-victim
  `set_meta("spike_cd_…")` cooldown keys (metadata is serialized with the scene, and
  godot#79222 measured a real frame-rate cost for `set_meta`/`get_meta` at this volume).
- **One shared snapshot + a uniform grid, on the game clock.** Victims used to be gathered
  into a fresh Array, `.filter()`-ed through a lambda into a second Array, then scanned by
  every hazard: ~460 distance tests plus two allocations and 42 lambda calls per 60 Hz
  tick at 40 enemies, with `_tick_spikes` additionally doing an O(n) `_hazards.find(h)`
  *per victim*. Now `_require_victims()` builds one lazy snapshot per tick
  (`RadiusSpatialIndex`: `PackedInt32Array` heads + next-links, rebuilt in place, sized
  from the largest query radius) and each hazard queries the few entities near it at its
  own `scan_interval` — a periodic vent queries nothing between bursts. Timers accumulate
  `delta` on `_game_time` instead of `Time.get_ticks_msec()`: at the hitstop manager's
  0.05x a 1 s spike immunity used to be spent in ~50 ms of game time, and the vent
  telegraph pulsed on wall clock while the world stood still. Heal now integrates over the
  time a field actually covered, so scan cadence changes cost, not total.
- **New typed seams that other systems can use.** `Damageable.get_status_manager()`,
  `get_health_component()` and `get_hit_radius()` replace
  `get_node_or_null("StatusManager") as StatusManager` on hazard paths, and `AreaDamage`
  pads bodies through the same `get_hit_radius()` so a hazard's spatial pre-filter can
  never disagree with the damage it hands off. `AreaDamage.VALID_FALLOFFS` lets content
  validate its own `falloff` name.
- **Dead knob removed:** `configure(..., ambient_burn)` was never passed `true` (the
  "Ember Winds" mutator delivers its fire ticks via `burn_tick`, not via hazards). It is
  now an explicit `ignite_pulses()`, tested, and available to the mutator path.
- **Validation reachability gap found and half-closed.** `ContentLoader` runs `validate()`
  only on resources that are a `ValidatedConfig`; `ArenaConfig` had one but did not extend
  it, so arena validation ran in the CI harness and never at load. Converted (authored
  hazard layouts make that load-bearing). Five other config types (`SkillConfig`,
  `StatusEffectConfig`, `WeaponConfig`, `AudioConfig`, `BossPhaseConfig`) still extend
  `Resource` — converting each is one line, but `ContentRegistry` *halts startup* on a
  validation error in debug builds, so each needs a real run proving the shipped `.tres`
  files pass. Pinned as a shrink-only list in the new suite.
- **Tests.** New `tests/unit/test_hazards.gd` (pure: validation rules, mirror expansion,
  layout parity with the old hand-tuned coordinates, cooldown/burst arithmetic, grid vs
  brute force, capacity overflow counting) and `tests/unit/test_hazards_live.gd`
  (in-tree fixtures, tick-by-tick: both teams hit once per period, throttled fields,
  player-armed plate, 100 Hz vs 60 Hz heal totals equal, freed markers, group/dead-body
  filtering, NaN epicentre). New `tests/python/test_regress_hazard_subsystem.py` (28
  checks; verified to fail on ten mutations, including a re-added wall clock, re-added
  metadata, a re-added arena `match`, a mechanic losing its arm, an AoE call handed the
  whole arena, and a reassigned bucket store). `tests/unit/test_nav_grid.gd` now reads
  hazard centres from the arena `.tres` instead of a hand-copied mirror of the deleted
  function. `tool/validate_guards.py` hazard needle moved from "a `Dictionary` signature
  exists" to the two guards that matter; 53/53 pass.
- **Caveats.** No Godot binary in this environment, so the GDScript suites are
  static-verified (gdparse/gdlint/check_typed_arch/validate_resources) and the behaviour
  tests themselves run in CI; the timing numbers in the live suite are written to tolerate
  float accumulation but a first CI run should be read carefully. Gameplay-visible
  changes are intentional and few: movers now orbit the position they were authored at
  (they used to ignore it and circle the arena centre), a mover with no room to circle
  stays put instead of clipping the wall, spike beds and vents now respect the shared
  body-padding rule at the rim (a big enemy is caught a hair earlier, like every other
  AoE in the game), and an ichor pool re-stamps its slow at 0.25 s instead of every tick
  (so the slow may linger up to a quarter second after you leave). Roll back the whole
  subsystem by restoring `scripts/arena/arena_hazards.gd` at this commit's parent; the
  arena `.tres` `hazard_layout` lines and `data/hazards*` directories are additive.

## [Unreleased] — Physics timing contract, collision contract, swept projectiles (2026-09-09)

Architecture pass on the parts that touch physics — collision, camera, player,
projectiles. No new physics engine: Godot's server already owns capsule motion, and
the gaps were contracts and timing, not solvers. Full rationale in
`docs/ARCHITECTURE.md` ("Collision contract", "Timing contract").

- **`CollisionLayers` (`scripts/core/collision_layers.gd`) is now the only source of
  3D bits.** 24 hand-written `collision_layer` / `collision_mask` numbers across
  arena bodies, `EnemyPack` separation, the camera solver, the projectile pool and
  the pickup pool became named constants, and the reserved-but-unassigned
  `PlayerAttack` / `EnemyAttack` / `Pickup` layers are now documented as reserved
  rather than left implied. New
  `tests/python/test_regress_collision_contract.py` (15 checks) pins the bit layout to
  `[layer_names]`, rejects any numeric assignment in `scripts/**`, pins
  `player.tscn` (2/1) and `enemy_base.tscn` (4/5) to the constants, forbids
  archetypes re-declaring collision, and asserts the four deliberate decisions
  (no hero/enemy body-block, geometry-only camera, peers-only separation,
  polled-not-detected pickups). `tests/unit/test_collision_layers.gd` is the
  in-engine mirror (registered in `UNIT_SUITES`).
- **Camera spring-arm stopped allocating on the frame-critical path.**
  `CameraCollisionSolver.solve()` ran once per *render* frame and built a fresh
  `SphereShape3D` + `PhysicsShapeQueryParameters3D` + one
  `PhysicsRayQueryParameters3D` per whisker per frame — up to 6 RID-backed objects
  handed to the physics server, scaling with panel refresh rate. Query objects are now
  built once and mutated (the `EnemyPack._sep_query` pattern), and the whole spatial
  pass is gated on a 1/60 s clock *and* a 0.4 m arm-displacement test, so a 120 Hz
  panel halves the queries while `solve()` still applies the cached pullback to the
  current arm direction (no added tracking latency). `recovery_timer` semantics, the
  whisker fan, ground clearance and the fast-in/slow-out asymmetry are unchanged;
  `use_sphere_cast` is now actually honoured (it was an authored profile field no code
  read). `invalidate_cache()` forces a pass after a re-target, a rig reset and the
  10 m teleport guard. `queries_last_pass` / `passes_total` reach the debug snapshot.
- **Physics interpolation enabled; the camera opts out and reads the interpolated
  target.** `physics/common/physics_interpolation=true` so the 60 Hz sim can never
  alias against a 120 Hz panel or the `PerformanceMonitor` step-down to `Engine.max_fps`
  30. `CameraRig` and its `Camera3D` set `PHYSICS_INTERPOLATION_MODE_OFF` (the rig is
  written every render frame — double-smoothing it would add a tick of lag) and follow
  `get_global_transform_interpolated()` instead of the stale tick value;
  `DamageNumberLayer` opts out for the same reason. Every teleport now resets
  interpolation after the write: `Projectile.launch/pool_reset`, `Pickup.drop/pool_reset`,
  `SpawnManager` spawn placement and split burst, `PickupManager.magnet_burst`,
  `Player.reset_for_new_run` (the run-start placement — reset lives on the actor, so a
  future debug/menu spawner cannot forget it), and the non-finite position repairs in
  `CharacterController` / `PlayerLocomotion`.
  `tests/python/test_regress_physics_timing_and_ccd.py` (22 checks) pins all of it,
  including a scan that fails on any new `_process` transform writer without an opt-out.
- **Projectiles are swept, no longer point-sampled.** A `Projectile` assigns
  `global_position` itself, so the server never integrates it and there is no CCD:
  at `sunbow`'s 24 m/s that is 0.40 m of travel per tick against a 0.25 m detection
  sphere, enough to skip a barrier or a dodging target. Each step now asks
  `cast_motion` how far it may safely go, identifies the blocker with a short
  `hit_from_inside` ray (cast_motion reports a fraction, not a collider), and loops up
  to 4 segments so a piercing shot resolves every victim along the path instead of at
  its endpoint. Swept and overlap contacts funnel through one `_resolve_hit()`, so the
  two paths cannot disagree; `sweep_radius` is taken from the authored
  `SphereShape3D`; `collide_with_bodies` only (volleys cannot shoot each other down);
  the launcher body is ignored for the flight; and with no space, no tree or
  `swept_collision = false` the shot falls back to the previous plain integration.

Verification (no Godot binary in this sandbox — see the caveat below): `gdparse` clean
on all 222 scripts/tests, `gdlint` clean on every touched file,
`check_typed_arch.py` clean (164 classes), `validate_guards.py` 47/47,
`python3 -m unittest discover -s tests/python` **502 tests OK**, and both new suites
confirmed to fail on deliberately reverted code (mutated copies: opt-out removed →
2 failures, extra `SphereShape3D.new()` → 1 failure). `--headless` runtime tests could
not be executed here, so the GDScript suite (`tests/unit/test_collision_layers.gd`) is
verified by parser + lint only and runs in CI.

## [Unreleased] — Audio playback engine rebuilt from the base up (2026-09-10)

Third-round audit picked the audio engine: it shipped a fully data-driven
`AudioConfig` schema the playback engine never read (per-cue voice caps,
cooldown spam guard, per-play volume/pitch rolls, bus routing, the `music_layer`
tag — all dead), started every SFX voice at full volume in sample zero, hard-
stopped stolen voices (the step-function pop), left one hot cue able to
monopolize all 16 voices, declared a "UI" bus that was never created, kept a
dead hard-switching music path inside AudioManager, and ran a "4-layer
intensity mixer" that was a volume nudge on a single bed. Rebuilt grounded in
FMOD/Wwise voice-management practice and adaptive-music research (full
write-up + sources in `docs/AUDIO_ENGINE.md`):

- **The contract is live.** New pure `SfxPolicy` governs every play:
  per-cue cooldown (silent suppression), per-cue voice cap with
  middleware-"oldest" steal, all from config; `AudioConfig.for_cue()` ships
  hand-tuned defaults (spam guards for footsteps/shots/hits, cap-1 for
  one-shot feedback, UI-bus routing) and `register_cue` accepts per-cue
  overrides. Per-play volume/pitch rolls are now actually applied.
- **Click-safe voices.** Every start ramps in (12 ms); a stolen voice fades
  out over 30 ms with a 1-t² shape before its player is reused — steals ride
  a pending-claim queue so no live voice is ever hard-cut.
- **Real vertical layering.** MusicManager now mixes optional intensity
  stems (`music_<bed>_l2/_l3`) above the bed with asymmetric fades (up 0.6 s
  / down 2.0 s), a 0.4 s dwell that stops heat flicker from machine-gunning
  the stems, and phase-synced joins. No stems registered → v1 single-bed
  behavior; stream swaps always fade-out → swap → fade-in.
- **Housekeeping.** The phantom "UI" bus exists and routes; the dead parallel
  music path (`play_music`/`stop_music`/`_music_player`) is gone; the fake
  bed volume-nudge layer is replaced by real stem levels. Soak/stress seams
  (`_sfx_pool`, `_cues`, `get_cue_stream`) and the v1 public API are
  preserved.
- New unit suite `tests/unit/test_audio_policy.gd` + Python shape guards.
- **4.4.1 compatibility.** `AudioConfig.for_cue()` annotates its dict lookup
  `: Variant` — the CI runtime suite treats "inferred from Variant" as an
  error, and the sandbox's `gdparse` doesn't type-check against the engine.

## [Unreleased] — Minimap radar rebuilt from the base up (2026-09-09)

The next-weakest subsystem audit picked the radar: v1 re-queried groups at
15 Hz and snap-drew every dot from raw node positions (visible ~0.8 m stepping
per refresh for a fast enemy), carried a dead `_north_up` member, had no
spawn/death transitions, no facing cone, no threat hierarchy, and redrew
unconditionally at the discovery cadence even when idle. Rebuilt as a
threat-aware radar grounded in published radar-HUD practice (full write-up +
sources in `docs/MINIMAP_RADAR.md`):

- **Smoothed tracks, decoupled cadences.** Each entity's display position
  eases toward the truth with frame-rate-independent exponential smoothing
  (`1 - exp(-rate*dt)`, the same family the camera uses). Group queries stay
  at 15 Hz; drawing runs per frame but `queue_redraw()` is gated on actual
  change, so an idle radar issues zero canvas invalidations.
- **Pure testable core.** Projection (v1-pinned semantics, now degenerate-
  safe), `track_position`, `ping_progress`, `blink_alpha`, `wedge_points` and
  the `advance_tracks` state machine are static + deterministic — new unit
  suite `tests/unit/test_minimap_radar.gd` plus Python shape guards.
- **Threat intelligence.** New enemies spawn a 1.2 s "spotted" ping; deaths
  fade out; the closest enemy gets a white emphasis ring; a live boss turns
  the rim into a red danger pulse with a boss halo; expiring pickups blink.
- **Orientation context.** North-up radar with a 70° facing cone (10 m range)
  so "which way is ahead" reads at a glance; player wedge stays instant.
- **Preserved contracts.** `project_to_map` semantics, `arena_half`,
  140×140 minimum, `Arena.ARENA_GROUP` lookup with legacy path fallback in
  `_find_arena()`, shared group constants; help-panel legend updated to the
  new vocabulary.
- **4.4.1 compatibility.** World→map projection goes through a `world_xz()`
  helper (`Vector2(p.x, p.z)`) because `Vector3.xz` is not a 4.4 member.

## [Unreleased] — Performance governor rebuilt from the base up (2026-09-09)

The audit found the weakest subsystem: the adaptive-quality monitor. It
averaged **FPS** (a nonlinear transform) against **absolute** 45/57 fps
thresholds, O(n) every frame, started every run at a hardcoded HIGH tier,
never persisted what auto-scaling found, let every unrelated settings save
re-assert the saved tier (clobbering the auto-scaled one), and shipped an
unreachable "ultra" tier — the settings schema silently dropped it, so the
`ui_root` ultra branch was dead code. Rebuilt as a frame-time governor,
grounded in published adaptive-quality-scaling practice (full write-up +
sources in `docs/PERFORMANCE_GOVERNOR.md`):

- **Frame time, relative budgets.** Decisions run on frame time against the
  current tier's *own* budget (`1000 / target_fps`). A healthy 30 fps capped
  tier reads as healthy, not failing — absolute rules misread capped tiers and
  cascade to the floor with no way back up (the engine's own cap forbids the
  frame times the upgrade rule would demand).
- **p95 + hitches, not just the mean.** Nearest-rank p95 over a 240-sample
  ring (O(1) push; percentiles computed at the 0.5 s decision cadence only),
  with hitches = frames beyond 2× budget. Two downgrade gates: *sustained*
  (avg ≥ 1.15×, p95 ≥ 1.35×, two consecutive bad ticks) and *spiky* (≥ 2
  hitches, p95 ≥ 1.5×).
- **Hysteresis.** Downgrade fast, upgrade cautiously: an upgrade needs 15 s of
  stability since the last tier change plus a clean window; a 5 s cooldown
  separates steps (the pre-existing contract); a 3 s warmup absorbs run-start
  load spikes; the sample window clears on every tier change so no decision
  runs on stale samples.
- **Rate-capped tiers hide headroom.** At the cap, frames pin to the limiter
  even on fast hardware, so the upgrade gate there tests flat pacing (p95
  ≤ 1.1× budget, zero hitches) instead of average headroom the cap forbids.
- **The save round-trips.** `SettingsData` now accepts **ultra** (four
  presets), the settings panel offers all four tiers, `main.gd` opens each run
  at the saved quality, and an auto-scaled tier is persisted through an
  injected `Callable` seam (`main.gd` wires it to `SaveManager`) so a slow
  device reboots at the tier it already proved it can hold. `ui_root` applies
  a saved quality **only when it changed**, so saving a volume can no longer
  clobber the auto-scaled tier; auto tier changes also refresh the
  damage-number budget via `quality_tier_changed`.
- **Real actuators + session-cap survival.** MSAA now actually follows the
  tier (LOW off, MEDIUM 2×, HIGH/ULTRA 4× — 4× is the mobile-safe ceiling)
  via `Viewport.msaa_3d`, restored from the project setting on teardown like
  the fps cap already was. The player's Settings FPS cap survives tier
  changes: the governor may lower `Engine.max_fps`, never raise it above the
  choice.
- **Tested.** New deterministic unit suite
  `tests/unit/test_performance_monitor.gd` (pinned clock, synthetic frame
  times: warmup, floor/ceiling, hysteresis, cooldown, session cap, p95 math,
  ring cap, artifact dropping, spiky gate, hitch-blocked upgrade + recovery)
  registered in `run_tests.gd`; static guards in
  `tests/python/test_regress_performance_governor.py`. Existing pins kept:
  `Engine.max_fps` teardown restore, single `_exit_tree`, no-op-free
  `_apply_tier_to_engine`, damage-budget numbers, 5 s cooldown semantics.
- **4.4.1 compatibility.** The sample ring is built by a `make_ring()`
  factory (4.4 has no `PackedFloat32Array(int)` constructor) and lazily sized
  on first push; `get_tier_name()` takes an optional tier index; debug
  telemetry uses the typed `OS.get_static_memory_usage()` (4.4 has no
  total-RAM getter, and string dispatch is gate-banned); `test_save.gd` now
  pins that `ultra` is a valid preset and that a truly invalid quality is
  still ignored.

## [Unreleased] — Solid decoration + touch-button dispatch hardening (2026-09-09)

Player-reported: *"character crossing through objects"* and *"crash on clicking the
attack button or any other button"*.

### Nothing walks through objects — decoration was the remaining hole

`ArenaObstacles` and the central landmark were already solid and nav-registered, but
the KayKit props the `ArenaDecorator` scatters — barrels, crates, boxes, rubble, the
brazier/torch rings and the frost ice shards — were **visual-only `Node3D` + mesh
holders**, so the hero and every enemy walked straight through them. The decorator's
own structural pillars had collision but were **missing from the nav grid**, so AI
intent routed through a pillar and the body leaned on it until the stuck-nudge freed
it. Both now honour the invariant the README/`docs/ENEMY_AI_RESEARCH.md` §3.1 promise:

- Every floor-standing prop gets a `StaticBody3D` named `PropCollision` on
  `collision_layer 1` / `mask 0` — the world layer the player (mask 1) and every enemy
  (mask 5) already collide with — sized from the mounted model's **own imported AABB**
  (`_combined_local_aabb` walks the child transforms, so a GLB's internal node offsets
  are included and no hardcoded box clips or floats), clamped to
  `MIN_PROP_HALF`/`MAX_PROP_HALF_XZ`/`MAX_PROP_HALF_Y` so a corrupt import can never
  produce a room-sized invisible wall.
- Each footprint (expanded to the axis-aligned bounds of the yaw-rotated box) is
  published through `Arena.register_decoration_blockers()` and merged into
  `ArenaNavGrid.build()`, so AI routes around exactly what physics blocks. Structural
  pillars are registered too.
- Props now also keep `SPAWN_MARKER_CLEAR_RADIUS` from every **enemy spawn marker**
  (previously only the player start and other props), so a new collider can never sit
  on a spawn and shove a spawning enemy into a wall.
- Wall-hung banners stay visual-only: flat cloth against the arena shell, not floor
  obstacles.
- New headless node suite `tests/unit/test_decorator_collision.gd` (registered in
  `run_tests.gd`'s `NODE_SUITES`) instantiates the real arena + decorator and asserts
  collider presence/layer/shape, one footprint per solid body, every footprint
  blocked in the rebuilt nav grid, the player start still walkable, and no solid prop
  on the hero start or a spawn marker.

### Touch buttons: the command can no longer be swallowed

`TouchActionButton._fire()` ran the settings lookup and `Input.vibrate_handheld()`
**before** `pressed.emit()`. Any failure in that presentation-only step aborted
`_fire()` and the gameplay intent never left the button — and the ATTACK button is the
only one with `vibrate_on_press`, which is exactly why it was the one that stopped
answering. The command is now emitted first, and haptics moved into a guarded
`_vibrate()` (null settings check, `OS.has_feature("mobile")` gate) that cannot reach
the input path.

- `TouchControls` routes all three buttons through one named dispatcher
  (`_on_button_pressed`, `pressed.connect(... .bind(method))`) instead of three
  anonymous lambdas, so a declined/failed command has a single place to surface.
- `UiCommands.action()` type-checks the skill-slot argument before `int()`, so a
  non-numeric arg degrades to slot 0 instead of raising mid-dispatch.

### Android haptics — documented, not silently dead

`docs/ANDROID_PERMISSIONS.md` claimed Godot adds `VIBRATE` automatically. Verified
against the 4.4.1 source, it does not: `platform/android/export/export_plugin.cpp`
reads `permissions/vibrate` from the export preset (line 945), and this preset
declares no `permissions/*` at all, so `Input.vibrate_handheld()` can never fire on
Android (`Godot.kt` gates it behind `requestPermission("VIBRATE")`). The doc is
corrected; enabling haptics on device is a deliberate product decision (it would add
`permissions/vibrate=true` and change the "no permissions" posture guarded by
`tests/python/test_android_permissions.py`), so it is left to the operator.

## [Unreleased] — Real Godot 4.4.1 verification + log hygiene (2026-09-09)

The handoff's open items are closed against a **real Godot 4.4.1-stable
runtime** (built from the official source tag in-sandbox; see
`GODOT_HANDOFF_RESOLUTION.md` for provenance and the complete unedited
`--import` / `run_tests.gd` logs under `docs/godot-runs/`):

- **All 7 documented arena-nav/obstacle test failures confirmed fixed on
  `main`** by the real runtime — no navigation code was modified (operator
  requirement honored).
- **AUTOLOAD blocker fixed per real 4.4.1 behavior.** Godot compiles the
  `--script` main loop *before* registering autoload globals (`Main::start`
  order); the runner's compile-time closure no longer reaches
  autoload-referencing scripts. `tests/run_tests.gd` is now dependency-free
  (built-in types + suite paths + thin wrappers) and loads the moved
  integration stages at runtime from `tests/integration_stages.gd`. No fake
  singletons; the real autoloads are used. New Python guards pin this
  load-order contract.
- **Runtime-surfaced script bugs fixed:**
  - `test_enemy_scene_inheritance.gd` used nonexistent
    `MeshInstance3D.get_surface_material_override_*` — the runtime error
    aborted the check function and silently skipped ~96 checks across all 8
    archetypes; now `get_surface_override_material_*` (suite grew 544 → 640).
  - `enemy_base.tscn` / the nav check referenced nonexistent
    `NavigationAgent3D.path_height_tolerance`; renamed to
    `path_height_offset` (the pinned 0.6 value is now actually in effect).
  - `arena.gd` set `PanoramaSkyMaterial.energy` (not a 4.4.1 property) on
    every themed arena load; removed with a comment.
  - `arena_{marble,metal,wood}.tres` carried the dead Godot-3 `specular`
    parameter (engine warning per load); removed.
  - The `_boss_ability_sequence` encounter fixture lacked its
    `EnemyStateMachine`, tripping the required-component fail-fast 3× per
    run; fixture now carries the full component set.
- Python regression suite: 415 → 417 tests, all green. Full local CI replica
  green: import (0 script errors), unit/integration (640/0 failed),
  hero runtime (148/0), UI validation (2189/0 ×2 profiles), asset imports
  (209 resources, 0 failures).

## [Unreleased] — Joystick movement no longer kills the run (2026-09-09)

Fixed the reproducible device crash where the app died a few steps after driving the
hero with the on-screen joystick. Cause: the movement chain had no finiteness boundary,
so one non-finite analog/camera value was integrated into `CharacterBody3D` and lerped
into the camera rig, where it latched (a NaN lerp never decays, and the locomotion input
only refreshes when it reads as exactly zero) — physics/rendering then aborted frames
later, far from the bad frame.

- One choke point for motion: `CharacterController._apply_velocity()` sanitises velocity
  in and out and repairs a non-finite body position per axis instead of propagating it;
  `tick()` refuses non-finite input and any non-positive/non-finite delta; yaw writes are
  whole-and-validated; `set_move_speed()` clamps instead of letting `inf` through.
- Camera rig: a single `_apply_follow_position()` writer rejects a non-finite solver
  result *and* a non-finite smoothing weight; `_update_look_at()` rejects non-finite and
  coincident eye/target frames and validates the built transform before it reaches the
  `Camera3D` (new `CameraMath.is_finite_v3/is_finite_transform` gate).
- Input chain: `VirtualJoystick` no longer divides by a degenerate radius, drops
  non-finite press/drag samples and never hands out a bad `get_value()`;
  `TouchControls` publishes a neutral stick instead of latching garbage;
  `PlayerLocomotion` validates both input hand-offs and repairs a poisoned transform in
  `clamp_to_bounds()`. The stick also accepts mouse drags, so this path is now
  reproducible in the editor without a touch device.
- Camera transform writers closed end to end: the shake pass (the frame's last writer)
  and the FOV controller now reject non-finite samples instead of committing them.
- Collateral defects in the same path: `PlayerAnimation._length()` could dereference a
  null/non-finite animation resource and feed `speed_scale`; `ArenaHazards` per-frame
  ticks dereferenced arena-owned visuals without validity checks (now a shared
  `_hazard_emission()` helper — the vent still damages when its glow is gone).
- Refusals log once per process (name the boundary that caught it) so a silent guard
  never hides the source. No balance, input-map or scene changes.
- Tests: new `tests/unit/test_locomotion_nan.gd` (headless, tree-free by design) +
  `tests/python/test_regress_locomotion_nan.py`; 13 new needles in the real-guard
  contract (`tool/validate_guards.py`: 45/45). Python suite 436 passing. See
  `docs/MOVEMENT_STABILITY.md` for the mechanism, the limits of this pass and how to
  confirm on a device (Godot is unavailable locally, so native CI + a phone run remain
  the verification step).

## [Unreleased] — Hero character fidelity (2026-09-09)

- Replace the live KayKit hero mesh with the project-authored **Arena Warden**:
  human proportions, layered armor, mail, gloves, split blue tabard, 1K PBR maps;
  34,860 triangles / 23 deform bones / one opaque body surface.
- Bake all **76 CC0 donor clips** to the new rig, preserving every combat/cast
  selection and hand socket. Condition gait lift, remove planar root travel,
  ground support and preserve pose reset channels. No gameplay/balance changes.
- Add an authored PBR gladius sharing the hero atlas; preserve authored material
  factors, remove the hero float tween and correct left/right dodge selection.
- Gate imports by the full clip/socket contract; keep the complete KayKit rig and
  primitive as fallbacks. Idle autoplay now uses private animation resources.
- Add reproducible authoring/provenance, strict offline validation, 19 focused
  Python tests, native pose/fallback/material tests and a real Player animation
  lifecycle CI gate with isolated saves.
- Add an interactive before/after clip viewer using actual GLBs/HDRIs; restore
  the existing three.js viewer's missing core dependency.
- Validation scope: both new models pass Khronos with no errors/warnings, focused
  tests and changed-script lint pass, output rebuilds are byte-identical. The full
  Python suite passes 415/415 after incorporating the subsequent fixes from
  `main`. Native Godot CI and device review remain required (the engine is
  unavailable locally).
- This is authored PBR armored art, not a photoreal scanned human or a replacement
  of the entire enemy roster. See `docs/HERO_FIDELITY.md` for remaining limits.

## [Unreleased] — Prestige gets teeth: cosmetics, tiers, objectives (2026-09-09)

Prestige, cosmetics, and challenge tiers were tables of IDs that never touched a
run. This pass makes all three change play.

### Challenge tiers scale the run

`Prestige.CHALLENGE_TIERS` now carries `currency_mult` and `waves` per tier plus
typed accessors (`challenge_tier_label/score_mult/currency_mult/mutator_count/
waves`). `GameMode` reads the player's prestige tier for the Challenge mode via a
new prestige-aware API (`scales_with_prestige`, `challenge_mutators`,
`score_multiplier_for`, `currency_multiplier_for`, `max_waves_for`,
`is_victory_wave_for`). The Challenge run's mutator SET is drawn by tier count
from `CHALLENGE_MUTATOR_POOL` (tier 0 reproduces the historical
`glass_cannon + ember_winds` pair), and its score/currency payout and wave cap
grow with rank — Hard → Nightmare → Mythic → Last Stand are now genuinely harder,
better-paying, longer runs. `WaveManager`, `RunScorekeeper`, `GameRoot`, and the
run-setup preview all consult the tier; the scorekeeper skips the flat per-rank
prestige bonus for Challenge so the tier payout isn't double-counted.

### Cosmetics attach to the world

New `Cosmetics` catalogue turns unlocked cosmetic IDs into applyable definitions
(trail / aura / banner / title, highest rank worn). New `PlayerCosmetics` node
mounts a coloured GPUParticles3D **trail** (ember/frost) and a rotating emissive
**aura** ring + motes on the live hero; `ArenaDecorator.apply_prestige_banners`
hangs unlocked **banners** on the arena walls in their colours; the run summary
shows the prestige title + worn cosmetics. Main reads the persisted unlock list
from `SaveManager` on every run build.

### Objectives become real modes

`OBJECTIVE_DEFEND_POINT` and `OBJECTIVE_COLLECT` (previously constants with zero
implementations) are now the playable modes **Hold the Line** and **Relic Hunt**,
driven by a new per-run `ObjectiveDirector`:
* Hold the Line — a beacon at the arena centre drains while enemies stand in its
  radius and self-repairs when clear; win on the mode timer, lose the instant it
  falls.
* Relic Hunt — slain foes drop `relic_shard` pickups on a deterministic cadence;
  bank the quota to win.
Both have endless spawn queues, HUD progress (`EventBus.objective_progress`), and
resolve through `EventBus.objective_resolved` → GameRoot victory/game-over. Adds
`RunState.objective_progress/objective_failed`, HUD objective line, Narrator
intros, and the `relic_shard` pickup (catalogued; `drop_weight 0` so it never
leaks into normal drop tables).

## [Unreleased] — Smaller product-debt cleanup (2026-09-09)

Follow-up on the remaining QA_RELEASE_AUDIT debt items that were not part of any
feature pass: fail-loud content loading, deletion of the legacy melee path, an
unbiased wave-director count nudge, and a strict (allowlist-free) UI gate.

### Content loading now halts on broken content (debug/test)

`ContentRegistry._ready()` already reported validation problems but then kept
running, so a corrupt `.tres` under `res://data/` could silently ship a game
missing enemies/weapons/upgrades. It now halts in debug/test builds (push_error
+ assert) and still reports every problem in release builds before continuing
with the degraded-but-usable tables. Cleaned up alongside: the write-only
`_validation_dirty` flag and the unreachable duplicate-id loop in `validate_all()`
(ContentLoader rejects duplicate ids at load time) were deleted; both startup and
`validate_all()` now share one error-reporting path.

### Legacy `AttackController`/`ComboChain` removed (M3 cleanup)

`Player._try_attack()` has used the `WeaponManager → WeaponInstance →
MeleeResolver/RangedResolver` path as its single authority since the typed
architecture overhaul; the `AttackController` fallback only ever ran when no
`WeaponInstance` was equipped, which production scenes never hit. Both files are
deleted, the `player.tscn` node and its `ext_resource` are gone, and `player.gd`
no longer resolves/ticks/resets the legacy controller; the vestigial
`Player.attack_hit` signal + handler (never emitted by the weapon path) and
`build_effects.gd`'s legacy wiring to it were removed too. Comments in
`combat_query.gd`, `character_controller.gd`, `player_animation.gd`,
`melee_resolver.gd`, `weapon_manager.gd` and the UI player double were updated;
docs (`ARCHITECTURE`, `EXTENDING`, plus RESOLVED markers on the audit summaries)
now describe `WeaponManager` as the single attack authority. The GDScript
integration suites that drove the legacy class directly were removed/updated
(`run_tests.gd` combo stage, `test_player.gd` legacy-recovery scenario), and the
Python regression guards that read the deleted files were retargeted to the
canonical combat code or inverted into “must stay deleted” guards.

### Wave-director count nudge no longer skews spawn composition

`WaveManager._apply_director_count_nudge` appended `queue[i % queue.size()]`
while the queue grew (sampling from the head) and used `pop_back()` to trim
(dropping the tail). Because spawn queues order weak-to-strong, that over-copied
the weakest front entries and silently deleted late elites/bosses on a down
nudge. The logic is now a pure, headless-testable
`WaveManager.apply_count_nudge(queue, bonus)` that spreads additions/removals
evenly across the ORIGINAL queue. New unit coverage in `tests/unit/test_waves.gd`
(boss preserved on −1, late entries kept on −2, deterministic, never empties a
non-empty plan) plus a structural guard in
`tests/python/test_regress_wave_systems.py`.

### UI validation gate is strict again (allowlist deleted)

The `KNOWN_FAILURES` filter in `scripts/ui/run_ui_validation.sh` masked two
pre-existing runtime bugs surfaced by the UI suite: `RunScorekeeper` calling the
nonexistent `CombatLog.log()` (fixed on `main` — the API is `record`, which the
scorekeeper has used since the runtime-verification pass) and the UI player
double exposing a Dictionary where a typed `ProgressionComponent` is expected
(the double now builds a real `Player` with real typed components). Both
underlying bugs are fixed in this tree, so the allowlist and its rationale
comment were deleted: any `SCRIPT ERROR` / `Parse Error` / `UI FAIL` now fails
the gate again. The suite re-runs in CI (fresh + existing save profiles) to
confirm no masked errors remain.

## [Unreleased] — Recheck, modularize, perfect (2026-09-09)

Follow-up pass over the 2026-09-08 AI/collision work: full re-read of every
touched file, extraction of the last inlined brain logic into the module
pattern, and small correctness/perf fixes.

### New: pack-coordination module (`scripts/enemies/enemy_pack.gd`)

`EnemyPack` (RefCounted, same pattern as EnemyLocomotion/EnemyNavigator/
EnemyStriker) now owns everything "the pack around me": hearing an ally's hit
(stimulus into EnemyPerception), grief-retreat after nearby ally kills,
player projectile/skill noise, and the separation steering query — including
the EventBus wiring (injected `connect_signals`/`disconnect_signals`, so the
module stays tree-free and headless-testable). `EnemyBase` shrank
accordingly and delegates: `is_fear_retreating()`, per-frame `update`/
`apply_separation`, `get_run_time()` for the grief window. Behavior is
unchanged; the query parameters object is now allocated ONCE per enemy
instead of per query (12–40 concurrent enemies was churning GC every
0.12 s).

### Fixes & polish

* **Attention-boost leak** — `enemy_idle_state.gd` reset
  `attention_boost = 1.0` only in the wander branch, so a look-pause boost
  (×1.6) leaked into REACTING/INVESTIGATING for the whole investigate
  window. The baseline is now reset at the top of `physics_update`, before
  any branch; only an ACTIVE look-pause widens sight.
* **Obstacle node building extracted** — `ArenaObstacles.build_nodes()`
  (static, deterministic, no autoload access) creates the StaticBody3D/
  BoxShape3D/BoxMesh set; `arena.gd`'s `_spawn_obstacles` now only resolves
  the parent node and delegates.
* **Flow-field refresh gated** — `arena.gd` skips the 10 Hz flow-field
  refresh entirely while no enemies are on the field (the field rebuilds on
  the first tick of the next wave).
* **Nav margin = capsule radius** — `ArenaNavGrid.AGENT_MARGIN` 0.45 → 0.5
  (the enemy capsule radius) so the path centerline never steers a body's
  edge into a wall. Verified: blocked cells are identical at 0.5 m cell size,
  so existing nav-grid assertions are unaffected.

### Audio content: recorded boss / calm / victory beds

* Previously only the menu and combat loops shipped as recorded audio; the
  boss, calm and victory beds shared the combat loop or fell back to
  procedural pads. All five music states now ship distinct CC0 loops:
  `arena_calm.ogg` (RandomMind — King's Feast), `arena_victory.ogg`
  (RandomMind — Rejoicing) and `arena_boss.ogg` (Juhani Junkala / SubspaceAudio —
  Evil3: Apocalypse), added to `assets/catalog.json` + `assets/manifest.json`
  with checksum-locked provenance and a saved creator notice
  (`ASSET_LICENSES/jrpg-evil.txt`). `AudioAssetIntegrator` now maps each music
  state to its own bed instead of sharing the combat track; the combat loop
  (`arena_gameplay.ogg`) is unchanged.

### Tests

* `tests/unit/test_arena_obstacles_node.gd` (new, NODE_SUITES) —
  instantiates the REAL arena scene headless and asserts end to end: one
  StaticBody3D per layout entry on collision layer 1 with box shape + mesh
  matching the layout, landmark collision body present, wall/floor geometry
  and boundary collision intact, nav grid blocking every obstacle + landmark
  footprint while the gate gap and player start stay walkable, LOS through
  the landmark blocked, flow field steering. The arena is freed before the
  later integration stages run.
* `tests/unit/test_nav_grid.gd` — margin comment updated to 0.5.

## [Unreleased] — Human-like enemy AI + nothing walks through objects (2026-09-08)

Research-driven pass over the enemy brain and arena collision. Full source
analysis (web game-dev literature + free open-source games on GitHub) lives in
`docs/ENEMY_AI_RESEARCH.md`.

### New: shared navigation grid (`scripts/arena/arena_nav_grid.gd`)

One deterministic 48×48 grid per arena (the Manymies flow-field pattern): a
shared flow field toward the player — rebuilt only when the player crosses a
cell — plus per-goal A\* with string-pulling, sampled line-of-sight, no corner
cutting, and deterministic tie-breaks. Pure RefCounted, headless-testable.

### New: interior obstacles the player AND enemies collide with
(`scripts/arena/arena_obstacles.gd`, `scripts/arena/arena.gd`)

Each arena now has a deterministic pillar/block set (hand-cleared against
hazards and spawn markers). Every obstacle is a StaticBody3D on collision
layer 1 — the same layer the player (mask 1) and enemies (mask 5) use — and
the same set feeds the nav grid, so **the AI's intent routes around exactly
what physics blocks**. The central landmark (forge/crystal/obelisk) also gets
a collision body: it was previously the one object both sides could walk
through. Enemy packs also get soft separation steering so they fan out
instead of overlapping each other.

### New: perception + personality (the "human" pass)

* `scripts/enemies/enemy_perception.gd` — sight (range + FOV cone + grid
  line of sight), hearing (ally hits, kills, player attacks/skills, being hit),
  a visible reaction beat, last-seen memory → investigate → forget, and the
  legacy always-aware mode when ranges are zeroed.
* `scripts/enemies/enemy_personality.gd` — deterministic per-enemy cast
  (aggression, caution, aim skill, strafe bias, reaction scale, dash
  willingness, cooldown spread) from `(run_seed, spawn_serial)`.
* Idle now wanders + "looks around" instead of freezing; chase re-rolls a
  maneuver (straight/flank/strafe) on a personal 0.9–1.8 s clock; melee
  cooldowns are jittered per swing (0.6×–1.4×); ranged enemies fire only
  with line of sight, aim with distance-scaled error, and their first shot
  is deliberately loose; wounded cautious enemies back off briefly after
  nearby allies die; dashers sometimes fake a charge by not dashing.
* All knobs are data-driven: 9 new validated `EnemyConfig` fields, tuned
  per archetype in `data/enemies/*.tres` (`detect_range > 0` still wins).
* `scripts/enemies/enemy_navigator.gd` — grid (LOS → flow field → A\*) first,
  legacy navmesh fallback, then direct.

### Tests

* `tests/unit/test_nav_grid.gd` — LOS, flow-field detour/idempotence, A\*
  detour/reach/determinism, obstacle-layout safety (bounds, spawn/hazard
  clearance, passable gate, scaling).
* `tests/unit/test_enemy_brain.gd` — personality determinism + ranges; full
  perception state machine (sight, hearing, LOS, FOV, memory, legacy mode).
* `tests/run_tests.gd` — new "reaction beat" integration check; the
  step-counted encounter assertions keep their frame budgets via
  `reaction_time = 0` in the probe config.

### Notes

* Enemy vs enemy is steering-separated (swarm-standard); enemy vs object and
  player vs object remain hard physics.
* Hazards intentionally stay walkable for the AI (kiting enemies through
  vents remains a player strategy).

## [Unreleased] — Typed architecture overhaul (2026-09-09)

Ends the duck-typing architecture: every component interaction is now a typed,
direct method call. **~10,000 lines rewritten across Player, EnemyBase,
GameRoot, all systems and every UI panel.**

### Removed
- **All 168 `_validated_*`/`_guarded_*` "validation theater" helpers** (141
  were provably dead — defined, never called). The guards that were real are
  inlined at their use sites; `docs/HARDENING.md` is marked SUPERSEDED.
- **All duck typing in `scripts/`**: 308 `.call("...")` sites and 297
  `has_method()` probes are gone (one sanctioned `has_method` assertion
  remains in `test_harness.gd`, where probing IS the job). Dead branches
  exposed by removed probes were deleted (GameRoot armory/arena-selection
  probes that never existed, projectile `set_team_tint`, chase-state dead
  clause, content-loader untyped registration).
- **`run is Dictionary` probing everywhere** — `GameRoot.get_run()` is typed
  (`RunState`); consumers read fields directly.
- 5 pure-theater python test files; ~130 theater assertions stripped from the
  rest (now pinned to real guards instead).

### Added
- `tool/check_typed_arch.py` — architecture gate: bans `.call("...")` string
  dispatch and `has_method(` (allowlisted exception), verifies `as T` casts
  and `Class.member()` calls resolve against declared `class_name`s +
  extends chains (133 classes, 8 autoloads).
- `scripts/core/validated_config.gd` — `ValidatedConfig` protocol base;
  all content configs extend it and ContentLoader runs their `validate()`.
- `class_name RingFade`; `HitstopManager`/`PerformanceMonitor`/`CameraRig`/
  `CharacterController` typed casts in feedback/UI code.
- Real `@export_range` editor enforcement on every authored content config
  (replacing the `pass`-stub `_export_range_guard` documentation theater).
- `docs/ARCHITECTURE.md` — the typed component model, autoload policy,
  seams, and the enforcement gates.
- Typed component accessors on Player (`get_health_component()`,
  `get_weapon_manager()`, `get_skill_controller()`, …).

### Changed
- `UiCommands.action` is a closed typed dispatch (unknown command → warn +
  false); TouchControls/SkillBar route through it.
- `weapon_manager`/`attack_controller`/`skill_controller`/`dodge_controller`/
  `stamina_component` resolve ProgressionComponent/StatusManager as typed
  refs; status effects source from `EnemyBase.get_archetype_id()`.
- SpawnManager's boss path is fully typed (`as BossController`, connect
  `summon_requested` **before** `begin_fight`); arena/placer APIs take
  `Arena` types; fake_arena test double now `extends Arena`.
- `audio_manager` volume/pitch clamps inlined at the voice-claim site;
  `event_bus` dead `_safe_emit`/`_guarded_*` wrappers removed.
- `tool/validate_guards.py` rewritten: pins the real inlined guards +
  @export_range contracts + theater-stays-dead (was: asserted 139/139
  helpers exist).

### Verified
- `gdparse` over all scripts + tests; `gdlint` clean on changed files.
- `tool/check_typed_arch.py`: clean. `tool/validate_guards.py`: exit 0.
- `python3 -m unittest discover tests/python`: 353 tests, all passing.

## [Unreleased] — Gameplay loop overhaul (2026-09-08)

Structural content/design pass that breaks the single-mode grind loop. Code stays
data-driven; modes, transforms, narrative and prestige are additive systems.

### Game modes (`scripts/meta/game_mode.gd`)

Five playable modes selectable from Run Setup:

| Mode | Objective | Notes |
|---|---|---|
| **Standard** | Endless waves | Original loop, unchanged defaults |
| **Boss Rush** | Slay 5 Warlords | No filler packs; elite-surge mutator; upgrade every wave |
| **Survival** | Endure 5:00 | Dense packs; time-based victory; score ticks with life |
| **Challenge** | Clear 12 waves | Fixed Gladius + glass/ember mutators; 1.5× score |
| **Campaign** | Clear 15 scripted waves | Authored encounter beats + narrator lore; final dual Warlord |

Victory ends the run cleanly (`RunState.victory`), banks a larger wallet cut, and
shows a distinct summary banner. Retry preserves the mode.

### Transformative upgrades (8 new cards + `BuildEffects`)

Stat sticks remain, but new **transform** rarity cards change how you play:

- **Storm Edge** — melee hits chain lightning
- **Cinder Step / Glacial Step** — dodge leaves fire trail or frost nova
- **Grave Pact** — kills summon temporary ally auras
- **Thorn Mantle** — taking a hit detonates a thorn nova
- **Reaper's Mark** — execute foes below 18% HP
- **Blood Rite** — every 5th kill heals a burst
- **Static Halo** — shocking aura pulses around you

`UpgradeConfig.effect_tags` + `ProgressionComponent` effect tracking +
`scripts/progression/build_effects.gd` runtime owner. Wired by Main on world build.

### Arena differentiation

Hazards now include **pressure plates** (player-triggered enemy blasts) and
**orbiting movers**, with denser per-arena layouts. Mode pressure adds extra
hazards for Boss Rush / Challenge / Survival / Campaign. Arena tags updated.

### Narrative layer (`scripts/meta/narrator.gd`)

Arena lore intros, mode intros, campaign beat sheet (15 scripted lines), enemy
blurbs. Delivered through the existing announcement banner — no new UI chrome.

### Prestige endgame (`scripts/meta/prestige.gd` + Armory UI)

After ~60% armory completion, spend banked coins to prestige: permanent score/
currency multipliers, titles (Unproven → Last Stand), unlockable cosmetics,
challenge-tier ladder. Save schema v5 carries `prestige_rank` + victory/boss
lifetime counters.

### Tests

`tests/unit/test_game_modes.gd` covers mode catalogue, victory conditions, spawn
queues, narrator, prestige gates, effect tracking, RunState summary fields, and
save migration.

---

## [Unreleased] — HD realism pass (2026-09-08)

Presentation overhaul across the arena, sky, lighting, renderer settings and actor
materials. **No gameplay, rig, animation, balance, save or input changes** — the
same scenes, physics, spawns, navigation and HUD contract are preserved.

### Assets (locked, provenance-kept)

- **17 new checksum-locked downloads (+10.58 MiB, 239 files / 45.63 MiB total):
  three Poly Haven CC0 HDRI panoramas** (spruit sunrise, venice sunset, moonless
  golf — via the pinned, MIT-licensed three.js mirror) and **photo PBR sets from
  Godot's Material Testers** (rock, aged brick, marble, wood, aluminium) at the
  already-pinned `godot-demo-projects` revision. The downloader/validator now
  support `.hdr` and `.jpg` with the same hash locks.
- Five new arena materials under `assets/materials/` (rock floor, brick walls,
  marble, wood, metal); `ASSET_LICENSES/` gains the three.js MIT and
  Godot MIT notices.

### Arena map — replaced

- `scenes/arena/arena.tscn` is rebuilt: photo-PBR rock floor, aged-brick walls
  with stone trims + marble cornices, corner towers with marble caps, an
  iron-banded wooden gate, marble dais, boulders and 4 flickering torch sconces
  (`scripts/arena/torch_flicker.gd`, deterministic, 4 omni lights, no shadows).
- Collision, spawn points, pickup points, navigation floor and arena script
  contract are unchanged; `Arena` themes still tint floor/walls by arena.

### Sky, lighting and renderer

- `arena.gd`: per-arena `PanoramaSkyMaterial` (IBL) with procedural fallback,
  exposure/contrast adjustment, tuned fog, glow on emissives; landmarks use the
  photo-rock/marble materials.
- `project.godot`: 2× MSAA, 8× anisotropic filtering, 2048px high-quality PCF
  directional shadows. Mobile renderer retained (SSAO/SSR off on purpose).

### Actor + prop material pass

- `scripts/visuals/hd_materials.gd` (`HdMaterials`) applies anisotropic filtering
  and role-tuned roughness/metallic/specular to every mounted player/enemy model
  (`CharacterVisuals`, `EnemyAnimator`) and every arena prop/decorator. Shallow
  material duplicates; textures, rigs and animations untouched.
- Rig inventory kept deliberately (combat clip coverage — see
  `docs/ASSET_AUDIT.md` "Why not a photoreal rig swap").
## [Unreleased] — Audit follow-ups: roster smoke, minimap robustness, dead facade (2026-09-08)

Follow-up pass over the remaining small-but-real findings in
`docs/QA_RELEASE_AUDIT.md`, plus hardening of the enemy-inheritance work:

- **TestHarness startup smoke now covers all 8 enemy archetypes** (`_enemy_archetypes_ok`,
  `_spawn_resources_ok`, `_kill_and_wave_scoring_configured` iterate a shared
  `ENEMY_ARCHETYPE_IDS` const). They validated only basic/fast/heavy — the exact
  "works for some enemies" blind spot the scene refactor closed on the scene side.
- **`tests/unit/test_enemy_scene_inheritance.gd` upgraded to full-roster goldens**: every
  archetype (not just the five refactored) now pins collision shape, body mesh, material
  colour, nav distances, marker offsets and animator config against shipped values;
  `path_height_tolerance` and the no-BossController-leak check included.
- **Minimap arena lookup is layout-independent** (audit "fragile hardcoded path"):
  `Arena` joins the `arena` group in `_ready`; `minimap._find_arena()` resolves through
  `get_first_node_in_group` first and keeps the legacy `WorldRoot/Arena` path only as a
  fallback. No behaviour change in main.tscn; the lookup now also survives renames and
  hosts other than the current scene.
- **GameRoot dead facade deleted** (audit "two sources of truth for best score/wave"):
  zero-caller `get_best_score()`/`get_best_wave()` accessors removed; SaveManager remains
  the single public read path (as pinned by the startup-stability guards) and GameRoot's
  `_best_*` mirrors stay internal (run_ended fan-out + debug snapshot only).
- **`tool/validate_resources.py` gained a file-local `SubResource` guard**: scenes that
  `instance=` another scene must not reference the parent's sub-resource ids (the classic
  hand-edit mistake on child scenes like the enemy archetypes); the editor's `[editable]`
  cross-file pointer remains sanctioned. Behaviour-tested in
  `test_regress_tooling_and_ci.py`; verified to flag and to clear real scenes.
- **`audio_config.gd` comment fixed** (audit known-issue #4): AudioConfig instances live in
  `res://data/audio/`; the referenced `res://data/audio_config/` directory does not exist.

## [Unreleased] — Enemy scene inheritance overhaul (2026-09-08)

Closes the audit's "highest-value structural cleanup left": **5 of 8 enemy archetype
scenes were hand-copied full trees** of `enemy_base.tscn`, so any edit to the base
(collision layers, shared child wiring) silently missed dasher/exploder/ranged/
splitter/warlord — the exact mechanism behind audit bug P6-style "works for some
enemies" divergence.

- `dasher/exploder/ranged/splitter/warlord_enemy.tscn` are now true **child scenes** that
  `instance=ExtResource("…/enemy_base.tscn")` and override only their archetype-specific
  bits (collision shape/mesh/material, marker offsets, warlord nav distances) plus their
  unique nodes (`EnemyAnimator` on all five, `BossController` + `BossPhaseConfig` plan on
  warlord). 69–117-line copies → 38–85-line diffs; resolved trees verified byte-parity with
  the pre-refactor scenes (values pinned in `test_archetype_overrides_pinned`).
- Root nodes renamed `EnemyBase` → `<Archetype>Enemy`, matching basic/fast/heavy.
- New guards keep it fixed: `tests/python/test_regress_enemy_scene_inheritance.py`
  (static: inheritance contract, no re-declared shared nodes, per-archetype override
  goldens) and `tests/unit/test_enemy_scene_inheritance.gd` (engine-side: instantiates all
  8 scenes and asserts shared nodes are present, typed and script-wired identically).
- `enemy_base.tscn` is now the single source of truth for all 8 archetypes: one edit lands
  on the whole roster.

## [Unreleased] — UI/UX polish pass (2026-09-08)

Presentation-only pass over the existing screens. **No new gameplay systems, no
new screens, no changes to run/combat/meta logic** — every fix is layout,
hierarchy, spacing, colour, feedback or Android fitness.

### New: one shared layout solver (`scripts/ui/ui_layout.gd`)

`UiLayout` is a pure, static solver that returns every gameplay-overlay rect
(top strip, vitals, minimap, boss frame, banner, toast, virtual stick, attack /
dodge / swap cluster, skill bar) from just the safe-area size and the
accessibility text scale. `ui_root._layout()` now feeds that single solution to
`GameHud.apply_layout()`, `TouchControls.apply_layout()` and the remaining
overlays, replacing the scattered magic offsets (`Vector2(290, 160)`,
`width * 0.5 - 160`, `width < 850`, `height - 210`, …) that produced the
overlaps.

Guaranteed and asserted at runtime by `_test_layout_solver` in
`tests/ui/ui_test_runner.gd`, over 12 resolutions (16:9, 18:9, 19.5:9, 20:9,
4:3, 1600x720 ultrawide, 720x1280 / 1080x2340 portrait, 640x360 floor) × text
scales 1.0 / 1.4 / 2.0:

- every rect lies inside the safe area;
- no two overlay elements overlap;
- attack / dodge / swap are never below the 88px touch floor;
- when a short screen genuinely has no room, the message band collapses to zero
  height and the element is hidden, instead of stacking onto the controls.

### Fixed

- **Overlapping overlays**: banner over the minimap and vitals, boss frame over
  the vitals column in portrait, toast under the skill bar, and (at 200% text)
  the skill bar landing on the action buttons.
- **Wrong anchors**: the HUD toast and the banner's coach line used fixed
  `PRESET_BOTTOM_WIDE` / `PRESET_TOP_WIDE` offsets that drifted off-screen on
  non-16:9 panels; both now follow the solved rect.
- **Joystick drew in the wrong space**: the active base/knob were drawn using
  screen coordinates inside a `_draw()` that is control-local, so the stick
  rendered offset from the thumb. Resting hint is now centred in its capture
  area, active base/knob draw correctly.
- **Text clipping**: HUD labels wrapped mid-word inside a fixed-width strip;
  they now use `OVERRUN_TRIM_ELLIPSIS`, the scrims clip, and compact wording
  refreshes on rotation (`_relabel`). Skill names abbreviate on narrow slots.
- **Confirmation dialog** was hardcoded to 500x220 and clipped its message at
  large text; `_popup_confirm()` sizes it from the viewport and text scale,
  wraps the label and gives both buttons full touch targets.
- **Upgrade grid** flipped 3→1 columns at a hard 1000px cutoff; it now fits
  2 columns where they fit and grows card height at large text.
- **Main menu** secondary row (Armory / Settings / How to play) clipped its
  labels on narrow portrait; it stacks vertically below 560px.

### Touch & feedback

- Touch-target floor unified at 88px (`UiTheme.TOUCH_MIN` / `UiLayout.MIN_TOUCH`)
  and enforced in `UiFactory.button/check` — sliders, option buttons, rebind
  buttons, armory Buy/Close and the HUD Pause button were all below it.
- Action buttons gained a real press state (brighter disc, thicker gold ring,
  outer halo) so a tap is confirmed even when the thumb covers the label.
- Skill slots now read locked / cooling / ready visually (opacity + caption
  colour), not by text alone.
- Theme `pressed` state is deliberately louder than `hover`, since touch has no
  hover; added `font_pressed_color` / `font_focus_color`.

### Visual coherence

- `UiTheme` gained a shared spacing scale (`SPACE_S/M/L`, `RADIUS`) used by the
  factory, cards, grids, menus and panels, replacing ad-hoc 8/10/12/16/24 gaps.
- Rajdhani is now bound for `Label`, `RichTextLabel` and `PopupMenu` too, so no
  control silently falls back to the engine default font.
- HUD top strip and vitals sit on translucent scrims, so score/health stay
  legible over the Ember and Frost arena themes without hiding gameplay.
- Boss frame, banner, toast and touch labels carry text outlines.
- Clearer hierarchy: dominant primary CTAs (Start Run, Resume Run), muted
  supporting copy, destructive pause actions grouped in a secondary row, and a
  subtitle on the Settings/Armory shells.

### CI

- The headless UI suite (`scripts/ui/run_ui_validation.sh`) was referenced by the
  docs but **invoked by no workflow**, so it had never actually run in CI. It is
  now wired into the `godot-tests` job. Wiring it up immediately caught a real
  bug in this branch: `TouchActionButton` seeded `custom_minimum_size` from its
  initial radius, so the Control refused to shrink to a smaller solved rect and
  overflowed the viewport at 960x540. Fixed.
- Current state: **2187 UI checks, 0 failed.**

### Pre-existing bugs surfaced (NOT fixed here — out of scope for a UI pass)

Running the UI suite for the first time also exposed two latent runtime errors
that exist unchanged on `main` (verified against base commit `3751371`). They
are filtered by an explicit, documented `KNOWN_FAILURES` allowlist in the
validation script so the new gate reports UI regressions instead of failing on
day one. Each should be fixed and de-listed:

1. `scripts/core/run_scorekeeper.gd` calls `_combat_log.log(...)`, but
   `CombatLog` defines `record(...)` and has no `log()`. Every run start and
   wave bonus raises `SCRIPT ERROR` and the entry is never recorded.
2. The UI player double returns a `Dictionary` where a `ProgressionComponent` is
   expected, so `get_stat` lookups error on a base object of type `Dictionary`.

### Notes

- Orientation stays `sensor_landscape` per `docs/ART_STYLE.md`; the stretch
  settings are now commented to explain the tall-panel behaviour. Portrait
  geometry is still solved and tested because the safe area can be portrait-ish
  mid-rotation and on foldables.
- Verified: `tool/validate_resources.py`, `tool/validate_assets.py`,
  522 Python regression tests (new suite:
  `tests/python/test_regress_ui_layout_polish.py`) and `gdparse` on all UI
  scripts. The Godot headless UI suite could not be executed in this sandbox
  (no network access to a Godot binary); it runs in CI via
  `scripts/ui/run_ui_validation.sh`.

## [0.6.0-dev] — In Development

- **Version bump**: `0.5.0→0.6.0` (version code `2→3`).
- Initiated development cycle for `v0.6.0`.
- **Character integrity**: `PlayerStart` moved off the central landmark so the hero
  is visible at run start; `player.tscn` gains a fallback `Body` capsule
  (load_steps `26→28`) mirroring the enemy pattern; `character_visuals.gd` fixes
  double-counted fit scale in grounding, hides Knight equipment before measuring,
  skips hidden/mesh-less nodes in bounds, warns (with `ResourceLoader.exists`
  pre-check) on mount failure, plants the ground shadow on the mount, and exposes
  start/stop breathing; `PlayerAnimation`/`PlayerEquipment` re-bind late mounts,
  stop before animation-library surgery, and rest the death pose; `PlayerFeedback`
  re-collects late-mounted weapon meshes.
- **Enemy facing**: all 8 `EnemyAnimator` nodes set `yaw_offset_degrees = 180.0` —
  every model authors forward as +Z (verified from bind-pose joints) while
  `face_direction` aims VisualRoot −Z at the player, so enemies faced backwards.
- **Spawn safety**: `ArenaDecorator._open_spot` keeps props/pillars 2.5 m clear of
  `PlayerStart` so runs can't begin inside decoration collision.
- **Lint**: repo-wide `gdlint` clean (renamed `_p_check`/`_pl` locals).
- **Startup stability follow-up**: deterministic dependency-first autoload order
  (`project.godot`: EventBus → SaveManager → AudioManager → ContentRegistry →
  GameRoot → SceneRouter → RunAnalytics → TestHarness) so singleton `_ready` code
  can rely on its dependencies existing — load-bearing now that
  `ContentRegistry.refresh_all` drives `AudioAssetIntegrator` registration, which
  needs `AudioManager`; documented inline in `project.godot`.
- **Authoritative end-of-run bests**: `game_root.gd:_finalize_run` re-reads
  `SaveManager.get_best_score`/`get_best_wave` (guarded by `has_method`) and takes
  `maxi` with the in-memory values, so reported bests can never regress below what
  is persisted even if a stats signal was dropped mid-run.
- **Richer mount diagnostics**: `character_visuals.gd` adds `model_path(role)` and
  `_report_mount_issue` (push_warning always + EventBus diagnostic mirror), and now
  reports the four previously silent abort sites (missing mount point, non-Node3D
  model root, no usable geometry, no visible mesh bounds); `visual_mount.gd` names
  the resolved model path and whether the primitive Body fallback is present
  ("primitive Body fallback kept" / "NO FALLBACK VISUAL PRESENT").
- **Bootstrap validation**: `main.gd` reports errors for a missing `WorldRoot`,
  a null arena config guard, an arena that fails to instantiate (naming
  `resource_path`), player scene load/instantiate failure, a null player aborting
  system creation, SpawnManager/WaveManager instantiation failure, and wave start
  without spawn/wave systems; adds `_validate_player_visual` which verifies
  VisualRoot/CharacterModel/Body at spawn time.

## [Unreleased] — Runtime verification fixes (2026-09-08)

Found by the headless E2E harness (`tests/verify_flow.gd`, 193 checks over two
full menu→run→game-over loops, all passing with zero script errors). Each fix is
a one-line correction of existing intent; no gameplay or architecture changes.
- **SFX variant volume restored**: `AudioStreamRandomizer.random_volume_db` does
  not exist (Godot 4.4 uses `random_volume_offset_db`); every pooled cue errored
  at registration and lost its ±3 dB humanization.
- **Run-start log error removed**: `RunScorekeeper` called the nonexistent
  `CombatLog.log`; the API is `record`, so the "Run started" entry now lands.
- **Player model mounts again**: `CharacterVisuals._bounds` took `Node3D`, so any
  imported rig (AnimationPlayer child) failed the mount and the hero stayed a
  primitive with no animation. The parameter is now `Node`, matching the body.
- **Boss phases work**: `HealthComponent.reset` emitted a transient 0/max state
  (current HP restored after the emit), so every boss spawned in Enrage with a
  phantom phase event + sting and phases never advanced afterwards.
- **Post-run music bed restored**: `run_ended` always lands after the game-over
  state hook, so requesting SILENT there stomped the explicit game_over→VICTORY
  bed with dead silence; it now restates VICTORY (same-state is a no-op).

## [Unreleased] — Audio & feedback polish (2026-09-08)

No new gameplay; feel-only fixes to existing audio, buses, and feedback.
- **Missing audio connected**: every `UiFactory` button now ticks (`ui_confirm` /
  `ui_back` by caption; those cues previously had zero call sites), plus upgrade
  cards, armory buy/close, option rows, toggles, the leave-run dialog, keyboard
  pause/resume, and the run-end `game_over` sting in `GameRoot._finalize_run`.
- **Double plays removed**: level-up no longer stacks `upgrade_select` over
  `level_up`; weapon switch plays `player_switch` exactly once (`equip` kept as a
  fallback via the `play_sfx` return value instead of a layered double).
- **Consistent mix**: enemy/pickup/upgrade cues moved from 0 dB to the catalogue's
  suggested gains (`-8`, spawns `-10`, explosions `-6`); enemy cues gained slight
  pitch variance; `AudioManager.play_sfx` now clamps volume/pitch (the
  `_validated_volume` helper was previously unused).
- **Music lifecycle**: menu bed seeds on fresh launch (previously silent until the
  first return to menu); heat resets on run start; crossfades capture the outgoing
  level so rapid state changes don't pop; recorded tracks register before tracking
  starts so launch audio is never the procedural placeholder.
- **Background/foreground**: `AudioManager` mutes the master bus on
  application-pause/focus-loss and restores on resume, combined with (never
  overwriting) the player's mute setting.
- **Volume controls**: settings sliders preview live on the mixer without touching
  saved data; leaving without saving restores the saved mix (`cancel_preview`).
- **Enemy hit feedback rebuilt**: `EnemyFeedback` no longer touches the
  nonexistent `Node3D.modulate` (runtime errors on every hit, no flash) — color
  flashes use a per-enemy overlay material, scale pops are relative so archetype /
  elite scales survive hits, overlapping flashes replace instead of piling up,
  hit/crit juice honors reduced motion, and the death sink fills the 0.8 s free
  window instead of vanishing early.
- **Softer transitions**: announcement banner entrance pop (reduced-motion aware),
  boss bar fade in/out with spawn-token guard, fallback idle clips forced to loop.
- **Hygiene**: integrator re-registration resets its counters; no new players,
  buses, or content — pool and memory footprint unchanged (16 SFX + 2 music + 1
  legacy music voice).

## [0.5.0] — Polished presentation & release fix (2026-09-08)

- **Arena identities**: per-arena themes (ember 0.12/0.85 fog 0.028 sun1.85, frost 0.18/0.82 fog0.024, default) plus central `Landmark` (forge lava 4.5+light2.2, crystal prisms 1.8, obelisk+cap) via `arena.gd:THEMES`+`_spawn_landmark`; `arena_decorator` distinct clutter (ember 18+5 braziers, frost columns+ice shards, default stone circle).
- **Character polish**: `character_visuals.gd` ground shadow + breathing bob, `player_animation` skill/victory clips (10 skill map, Cheer on level/boss), `enemy_animator` stun/cast + telegraph sync, `boss_controller` phase visuals (tint/scale/light) + audio.
- **Combat feel**: pooled bursts 10×22/0.68s + emissive rings, crit gold 0.82+1.05, elite aura, hitstop 0.04/0.16, camera combat shake wiring (skill/wave/boss).
- **Audio**: `procedural_sfx` 10→28 cues, `skill_controller`/`experience`/`wave_manager`/`boss_controller` play `skill_cast`/`ready`/`level_up`/`wave_started`/`completed`/`boss_*`; `catalog.json` 7 new cues.
- **UI / mobile**: `upgrade_panel` rarity borders, `touch_controls` 64/52 thumb-friendly, `camera_rig` impulse, safe-area.
- **CI fix**: `android.yml` `publish-release` now triggers on `release: published` (was skipped) plus tags/dispatch, tag fallback uses `event.release.tag_name`; version bump `0.4.0→0.5.0` code 2 to unblock `v0.5.0`.

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

## [Unreleased] — Environment / presentation pass (Agent 4, 2026-09-08)

### Visual
- **Live character + enemy models**: `scripts/visuals/character_visuals.gd` mounts the
  approved Knight + 8 archetype models onto `VisualRoot/CharacterModel` (height-fit,
  foot-grounded, +Z→−Z yaw, optional idle loop) with a primitive fallback; player wired
  via a scene mount node, enemies via a narrow `EnemyBase` hook. No gameplay change.
- **Arena identity**: `ArenaDecorator` now places approved KayKit dungeon props
  (pillars/columns, banners, torches, crates, barrels, rubble) with per-arena
  compositions + primitive fallback; `arena.gd` applies per-arena sky/fog/sun/ambient
  and floor/wall tint themes for Default, Ember Crucible and Frost Hollow.
- **Pooled VFX** (`scripts/visuals/effect_director.gd`): mobile-capped GPU bursts +
  ground rings for enemy spawn/death, wave start/completion, pickups, boss spawn/slain
  and status effects (via existing `EventBus` signals; no gameplay edits).

### Audio
- **Approved audio registered**: `AudioAssetIntegrator` reads `assets/catalog.json`
  at startup and registers the recorded SFX pools + looping menu/combat music onto the
  existing `music_*` state cues over the procedural fallback.

### Validation
- Unit suite `test_character_visuals` + `validate_asset_imports` presentation checks
  (role model import/idle coverage, VFX sprite textures). Full Android CI green.

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

### CI

- The headless UI suite (`scripts/ui/run_ui_validation.sh`) was referenced by the
  docs but **invoked by no workflow**, so it had never actually run in CI. It is
  now wired into the `godot-tests` job. Wiring it up immediately caught a real
  bug in this branch: `TouchActionButton` seeded `custom_minimum_size` from its
  initial radius, so the Control refused to shrink to a smaller solved rect and
  overflowed the viewport at 960x540. Fixed.
- Current state: **2187 UI checks, 0 failed.**

### Pre-existing bugs surfaced (NOT fixed here — out of scope for a UI pass)

Running the UI suite for the first time also exposed two latent runtime errors
that exist unchanged on `main` (verified against base commit `3751371`). They
are filtered by an explicit, documented `KNOWN_FAILURES` allowlist in the
validation script so the new gate reports UI regressions instead of failing on
day one. Each should be fixed and de-listed:

1. `scripts/core/run_scorekeeper.gd` calls `_combat_log.log(...)`, but
   `CombatLog` defines `record(...)` and has no `log()`. Every run start and
   wave bonus raises `SCRIPT ERROR` and the entry is never recorded.
2. The UI player double returns a `Dictionary` where a `ProgressionComponent` is
   expected, so `get_stat` lookups error on a base object of type `Dictionary`.

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

### Post-merge fix (UI/UX polish branch)

- `scripts/audio/audio_asset_integrator.gd`: `random_volume_db` is not a Godot 4
  property on `AudioStreamRandomizer`; the assignment raised a runtime
  `SCRIPT ERROR` on every SFX pool build. Renamed to the real property
  `random_volume_offset_db` (same intent: +/-3 dB per-playback variation).
  Caught by the headless UI validation gate added on this branch.
