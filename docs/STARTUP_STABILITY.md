# Startup Stability — Core-Stability Pass (2026-09-08)

Scope: **crash shortly after start on Android** and **main character does not
load/appear**. No gameplay, mechanics, levels, characters or monetization changed.
Architecture and data flow preserved; fixes are additive guards/determinism only.

## Verification limits in this pass

- GDScript static analysis of all 177 `.gd` files: **0 errors** (only pre-existing
  `INFERENCE_ON_VARIANT` hints, also present before the change).
- Repo validators: `tool/validate_resources.py` (110 files OK), `tool/validate_guards.py`
  (139/139, 69 OK), `tool/validate_assets.py` (OK), `download_assets.py --verify` (222/222).
- Python regression suite: **511/511 green** (502 pre-existing + 9 new guards).
- Content/GLB audit: every model referenced by `CharacterVisuals` / enemy
  `animation_map`s exists with the expected animation names (Knight, skeletons,
  creatures, demons) — verified against an independent GLB parser.
- Engine behavior verified against Godot **4.4.1-stable source**: (a) all autoload
  nodes exist *before* any `_ready()` runs (tree insertion is deferred), so
  `Singleton.foo()` never resolves to null; (b) `_ready()` still runs strictly in
  declaration order, so reading another singleton's *data* at `_ready()` is only
  deterministic when the dependency is declared above the consumer.
- No desktop/editor regression path changes: on success paths behavior is identical.

## Root causes found

### RC1 — The player had no visual fallback at all (invisible player)

`CharacterVisuals` replaces primitive actor visuals with the mounted Knight model
at runtime (`VisualMount._ready` → `load("…/Knight.glb")`). Every *enemy* carries a
primitive capsule `Body` under `VisualRoot/CharacterModel` which keeps it visible
if the mount fails; `CharacterVisuals._hide_primitive()` hides it only after a
successful mount. `scenes/player/player.tscn` had **no such Body** — the player's
only visual was the runtime model load. Any device-side failure (import cache,
VRAM pressure, Basis Universal transcode failure) left the player completely
invisible, and the failure log was info-level only.

**Fix:** added the same primitive fallback `Body` capsule to `player.tscn`;
mount failures now log warnings including the model path and whether a fallback
visual exists (`visual_mount.gd`), with per-reason reporting inside
`character_visuals.gd` (load failure / wrong type / no Node3D root / no geometry),
each explicitly noting the kept fallback.

### RC2 — Non-deterministic autoload initialization order

`GameRoot._ready()` read `SaveManager.get_best_score()/get_best_wave()`. Autoload
`_ready()` runs in declaration order and GameRoot was declared **first**, before
SaveManager had loaded the save file from disk — so GameRoot's cached bests were
the defaults for the entire session, feeding `run_ended`/game-over presentation.
`AudioManager._ready()` similarly applied default settings (only accidentally
corrected later by the load-time `settings_changed` emission).

**Fix:** dependency-first autoload order in `project.godot`
(EventBus → SaveManager → AudioManager → ContentRegistry → GameRoot →
SceneRouter → RunAnalytics → TestHarness), documented in-file, plus
`GameRoot._finalize_run()` now adopts the authoritative bests from the save store
after recording, so the emitted best can never be a stale startup cache.

### RC3 — Bootstrap failed silently (no validation)

`Main.build_world()` returned silently when `WorldRoot` was missing; player
spawn had no explicit validation; `SpawnManager`/`WaveManager` instantiation
failures would have aborted `_create_systems` mid-way and `_start_run_waves`
degraded silently.

**Fix:** clear validation + structured `report_error`/`report_warning`
diagnostics in `main.gd`: world-root missing, arena/player instantiation
failure, `_validate_player_visual()` (fails loudly if the player would be
invisible; warns when the fallback is in use), spawn/wave subsystem failures
(report + fail closed, rest of the world stays consistent), and an explicit
error when a wave start is requested with missing systems.

## Files changed

- `project.godot` — autoload order + in-file rationale (RC2).
- `scenes/player/player.tscn` — primitive `Body` fallback visual; `load_steps` 26→28 (RC1).
- `scripts/visuals/visual_mount.gd` — loud, reasoned mount-failure diagnostics (RC1).
- `scripts/visuals/character_visuals.gd` — `model_path()` helper + per-reason
  failure reporting, tree-resolved EventBus so headless users stay safe (RC1).
- `scripts/main/main.gd` — world/player bootstrap validation + structured error
  reporting; fail-closed subsystem guards (RC3).
- `scripts/core/game_root.gd` — authoritative best-score/wave adoption at run
  finalize (RC2).
- `tests/python/test_regress_scene_player_tscn.py` — pin updated 26→28 + Body
  regression guard (explained in-file).
- `tests/python/test_regress_startup_stability.py` — new: autoload-order,
  player-fallback, bootstrap-validation and finalize-audit guards (9 tests).
- `docs/STARTUP_STABILITY.md`, `CHANGELOG.md` — this report.

## Tests performed

- `python3 -m unittest discover -s tests/python` → 511 passed, 0 failed.
- `python3 tool/validate_resources.py` → 110 files OK (incl. scene `load_steps`).
- `python3 tool/validate_guards.py` → 139/139 files, 69 guard checks pass.
- `python3 scripts/download_assets.py --verify` → 222/222 assets (35.05 MiB).
- `python3 tool/validate_assets.py` → OK.
- GDScript analyzer (Godot 4.x semantic diagnostics) across `scripts/` + `tests/` →
  0 errors; no new diagnostics vs. baseline.
- Independent GLB audit → all role/archetype models + animation names present.
- CI pipeline on this branch (run 34235676103): **all green** —
  - *Validate resources & Python tests*: pass (511/511 + all repo validators).
  - *Godot headless tests* (real Godot 4.4.1-stable): project import, GDScript
    unit+integration suites, and native asset-import validation pass with the
    reordered autoloads, the modified `player.tscn`, and the new diagnostics.
  - *Build Android APK*: the Gradle Android export completes and the APK
    artifact passes existence/size verification.
- Physical Android device / emulator: **not available in this environment** — the
  remaining manual verification step is to sideload the CI APK (`LastStandArena-android`
  artifact from the branch run) and confirm boot → menu → run start → player visible,
  watching logcat for the new mount/spawn diagnostics
  (`CharacterVisuals: …`, `VisualMount: …`, `Player spawned with mounted character model`).

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
