# Startup Stability — Core-Stability Pass (2026-09-08, updated after PR #17)

Scope: **crash shortly after start on Android** and **main character does not
load/appear**. No gameplay, mechanics, levels, characters or monetization changed.
Architecture and data flow preserved; fixes are additive guards/determinism only.

> **Status note (reconciliation).** While this pass was in review, PR #17
> (branch `arena/01a08130-game-no-7`) landed an independent fix for the
> player-visibility root cause on `main`: it added the primitive `Body` capsule
> fallback to `player.tscn` (load_steps 28), reworked `character_visuals.gd`
> (ResourceLoader pre-check, equipment hidden before measuring, double-scale
> bounds fix, mount-parented ground shadow, breathing meta guard), and moved
> `AudioAssetIntegrator` registration out of `main.gd` into
> `ContentRegistry.refresh_all`. This branch has been **rebased onto that main**
> and now stacks only the fixes PR #17 did not cover: deterministic autoload
> order, authoritative end-of-run bests, richer mount diagnostics, and world
> bootstrap validation. Where the two passes touched the same lines (player.tscn
> fallback Body, mount-failure warnings), the merged version on main is kept and
> this branch's additions are layered on top without changing PR #17's behavior
> or console output.

## Verification limits in this pass

- GDScript static analysis of all `.gd` files: **0 errors** (only pre-existing
  `INFERENCE_ON_VARIANT` hints, also present before the change).
- Repo validators: `tool/validate_resources.py`, `tool/validate_guards.py`,
  `tool/validate_assets.py`, `download_assets.py --verify` — all green.
- Python regression suite: green (pre-existing suites + PR #17's tests + 9 new
  startup-stability guards from this branch).
- Content/GLB audit: every model referenced by `CharacterVisuals` / enemy
  `animation_map`s exists with the expected animation names (Knight, skeletons,
  creatures, demons) — verified against an independent GLB parser.
- Engine behavior verified against Godot **4.4.1-stable source**: (a) all autoload
  nodes exist *before* any `_ready()` runs (tree insertion is deferred), so
  `Singleton.foo()` never resolves to null; (b) `_ready()` still runs strictly in
  declaration order, so reading another singleton's *data* at `_ready()` is only
  deterministic when the dependency is declared above the consumer.
- No desktop/editor regression path changes: on success paths behavior is identical.
- CI on the rebased branch: **must be re-verified** — the earlier green run
  (34235676103: validate+python 511/511, Godot 4.4.1 headless import+tests,
  Android APK build) covered this change set *before* the rebase onto PR #17;
  the reconciled tree gets a fresh CI run via the pull request.

## Root causes found

### RC1 — The player had no visual fallback at all (invisible player)

`CharacterVisuals` replaces primitive actor visuals with the mounted Knight model
at runtime (`VisualMount._ready`). Every *enemy* carries a primitive capsule
`Body` under `VisualRoot/CharacterModel` which keeps it visible if the mount
fails; `CharacterVisuals._hide_primitive()` hides it only after a successful
mount. `scenes/player/player.tscn` had **no such Body** — the player's only
visual was the runtime model load. Any device-side failure (import cache,
VRAM pressure, Basis Universal transcode failure) left the player completely
invisible, and the failure log was info-level only.

**Fix (PR #17, on main):** the primitive fallback `Body` capsule in
`player.tscn` (load_steps 26→28, `Mat_player`), the `character_visuals.gd`
mounting hardening, and info→warning log levels.

**Fix (this branch, stacked):** mount failures now log warnings including the
resolved model path and whether a fallback visual exists (`visual_mount.gd`:
"primitive Body fallback kept" / "NO FALLBACK VISUAL PRESENT"), and
`character_visuals.gd` gains `model_path(role)` plus `_report_mount_issue`
(push_warning always + EventBus diagnostic mirror, tree-resolved so headless
users stay safe). The four previously **silent** abort sites now report:
missing `VisualRoot/CharacterModel` mount point, non-Node3D model root,
no usable geometry, and no visible mesh bounds. PR #17's two existing warning
messages are preserved verbatim (now routed through the shared helper).

### RC2 — Non-deterministic autoload initialization order

`GameRoot._ready()` read `SaveManager.get_best_score()/get_best_wave()`. Autoload
`_ready()` runs in declaration order and GameRoot was declared **first**, before
SaveManager had loaded the save file from disk — so GameRoot's cached bests were
the defaults for the entire session, feeding `run_ended`/game-over presentation.
`AudioManager._ready()` similarly applied default settings (only accidentally
corrected later by the load-time `settings_changed` emission).

**Fix:** dependency-first autoload order in `project.godot`
(EventBus → DebugErrorHandler → SaveManager → AudioManager → ContentRegistry →
GameRoot → SceneRouter → RunAnalytics → TestHarness), documented in-file, plus
`GameRoot._finalize_run()` now adopts the authoritative bests from the save store
after recording, so the emitted best can never be a stale startup cache.

This ordering became **load-bearing** with PR #17: audio cue registration moved
into `ContentRegistry.refresh_all()`, which instantiates `AudioAssetIntegrator`
and calls into `AudioManager` — so `AudioManager` must be ready before
`ContentRegistry._ready()` runs. The enforced order guarantees exactly that.

### RC3 — Bootstrap failed silently (no validation)

`Main.build_world()` returned silently when `WorldRoot` was missing; player
spawn had no explicit validation; `SpawnManager`/`WaveManager` instantiation
failures would have aborted `_create_systems` mid-way and `_start_run_waves`
degraded silently.

**Fix:** clear validation + structured `report_error`/`report_diagnostic`
diagnostics in `main.gd`: world-root missing, arena config guarded against a
null registry, arena instantiation failure (naming the scene's
`resource_path`), player scene load/instantiate failure (fails closed with a
clear error), a null player aborting system creation,
`_validate_player_visual()` (fails loudly if the player would be invisible;
warns when only the model mount would render), spawn/wave subsystem failures
(report + fail closed, rest of the world stays consistent), and an explicit
error when a wave start is requested with missing systems.

## Files changed (this branch, on top of PR #17)

- `project.godot` — autoload order + in-file rationale (RC2).
- `scripts/visuals/visual_mount.gd` — path-naming mount-failure diagnostics with
  fallback-presence (RC1).
- `scripts/visuals/character_visuals.gd` — `model_path()` helper +
  `_report_mount_issue` and reporting at the four previously silent abort
  sites; PR #17's messages/behavior kept (RC1).
- `scripts/main/main.gd` — world/player bootstrap validation + structured error
  reporting; fail-closed subsystem guards (RC3).
- `scripts/core/game_root.gd` — authoritative best-score/wave adoption at run
  finalize (RC2).
- `tests/python/test_regress_scene_player_tscn.py` — adds the "Body has a
  CapsuleMesh sub-resource" assertion to PR #17's load_steps/Body pins (RC1).
- `tests/python/test_regress_startup_stability.py` — new: autoload-order,
  player-fallback, bootstrap-validation and finalize-audit guards (9 tests).
- `docs/STARTUP_STABILITY.md`, `CHANGELOG.md` — this report.

## Tests performed

- `python3 -m unittest discover -s tests/python` → all green (pre-existing
  suites + PR #17's tests + 9 new guards).
- `python3 tool/validate_resources.py` → OK (incl. scene `load_steps`).
- `python3 tool/validate_guards.py` → all guard checks pass.
- `python3 scripts/download_assets.py --verify` → all assets verified.
- `python3 tool/validate_assets.py` → OK.
- GDScript analyzer (Godot 4.x semantic diagnostics) across `scripts/` + `tests/` →
  0 errors; no new diagnostics vs. baseline.
- Independent GLB audit → all role/archetype models + animation names present.
- CI on the pre-rebase tip (run 34235676103) was all green; the reconciled tree
  **requires a fresh CI run** (created with the pull request) before merge.
- Physical Android device / emulator: **not available in this environment** — the
  remaining manual verification step is to sideload the CI APK (`LastStandArena-android`
  artifact from the branch run) and confirm boot → menu → run start → player visible,
  watching logcat for the new mount/spawn diagnostics
  (`CharacterVisuals: …`, `VisualMount: …`, Player visual validation lines).

## Remaining risks / notes

- The menu music state is only requested on state *changes*; because the game
  starts already in `MAIN_MENU`, the music director stays silent until the first
  transition. Cosmetic, pre-existing, out of stability scope — noted for the audio
  owner.
- Renderer remains `mobile` (Vulkan) with Godot's default
  `rendering_device/fallback_to_opengl3=true`, which already covers devices with
  broken Vulkan init. Switching default renderers would be a product/visual
  decision and was intentionally not made.
- First boot performs bounded synchronous content registration (data `.tres` +
  audio + model references). No unbounded or repeated work was found; further
  deferral would alter content-registration architecture and was not risked.
- Runtime behavior of the new warnings cannot be observed without a device run;
  they are additive and identical on success paths.
