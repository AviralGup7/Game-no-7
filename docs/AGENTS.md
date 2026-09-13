# AGENTS.md — working in this repository

This is the operating manual for AI agents (and humans) changing Last Stand:
Station Zero. Gameplay code lives under `scripts/`; **this file does not grant
permission to edit it.** Content is added as data — see [EXTENDING.md](EXTENDING.md).

Pinned engine: **Godot 4.4.1-stable** (`.godot-version`). Target: Android ARM64,
Mobile renderer, landscape, touch-first. Shipping entry:
`scenes/campaign/station_zero.tscn` (not the legacy arena menu).

## Architecture rules (do not violate)

- **Typed, not duck-typed.** No `.call("…")` / `has_method(` in `scripts/`
  (`tool/check_typed_arch.py`). Resolve once `as T`, call directly.
- **No Dictionary state channels** for new gameplay. Cross boundaries with typed
  records (`DamagePayload`, `WaveModifiers`, …). The shipping campaign still
  has some validated Dictionary graphs — that is debt, not a template
  ([CODE_QUALITY_AUDIT_2026-09-12.md](CODE_QUALITY_AUDIT_2026-09-12.md)).
- **Numbers in `.tres`, not code.** `ValidatedConfig.validate()` at load.
  `ContentRegistry` halt-on-error in debug.
- **Collision bits** from `CollisionLayers` only. Combat hits are math, not
  physics layers.
- **Finite physics.** `is_finite()` + clamp before writing transforms/velocity.
- **Pools are bounded.** `clampi(size, 1, MAX)`.
- **Determinism.** Gameplay RNG goes through `RngService` streams; no global
  `randi()` on the sim path.
- **No Godot binary required for the offline gates.** An absent engine is
  `NOT TESTED / exit 2`, never a green skip. Do not invent runtime/FPS/device
  claims. Keep **NOT RUNTIME VERIFIED** honest.

Full model: [ARCHITECTURE.md](ARCHITECTURE.md). Hardening contract:
[HARDENING.md](HARDENING.md).

## The 11 offline gates (must stay green)

Run from the repo root. No Godot, no network, no extra pip packages.

| # | Command | Baseline (2026-09-13, this workspace) |
|---|---|---|
| 1 | `python3 tool/validate_resources.py` | Validated **183/183** files: OK |
| 2 | `python3 tool/validate_assets.py` | **128** models, **135** PNGs, **46** audio, **2** fonts |
| 3 | `python3 tool/validate_campaign.py` | 12 districts, 13 missions, 96 authored enemies, 47 floors, 72 landmarks, 30 interactions, 32 encounters, 3 768 modules, 36 288 nav cells, **13 440** walkable, **1 676** perimeter edges |
| 4 | `python3 tool/validate_geometry.py` | 0 issues across 13 categories |
| 5 | `python3 tool/validate_guards.py` | Passed **201**, Failed 0 |
| 6 | `python3 tool/check_typed_arch.py` | **214** project classes, **9 autoloads** |
| 7 | `python3 tool/check_engine_api.py` | **304** GDScripts vs pinned 4.4.1 ClassDB; advisory `[unsafe]` count is reported, not silenced |
| 8 | `python3 tool/check_scene_paths.py` | **39** scenes, **236** resolved paths |
| 9 | `python3 tool/check_string_formats.py` | **966** `%` uses checked |
| 10 | `python3 tool/check_signals.py` | names/arities resolve; advisory dynamic-receiver warnings reported |
| 11 | `python3 -m unittest discover -s tests/python -p 'test_*.py'` | includes the **license-mapping** walk (`tests/python/test_license_mapping.py`) |

Companions (also offline, also CI): `validate_level_flow.py`,
`validate_shooter_readiness.py`, `validate_visual_performance.py`.

`tests/python/test_regress_run_modes.py::DocCountTests` re-derives HARDENING.md's
GDScript / validated-file / guard-needle counts from the tools. If you add a
`.tscn`/`.tres`, update those HARDENING lines.

### Autoloads (9)

`EventBus`, `DebugErrorHandler`, `SaveManager`, `AudioManager`,
`ContentRegistry`, `GameRoot`, `SceneRouter`, `RunAnalytics`, `TestHarness`
— order in `project.godot` is load-bearing.

## CI (read-only in this pass)

`.github/workflows/android.yml` — do not edit it unless a dedicated CI task
says so. Jobs:

1. `validate-resources` — the 11 gates above (no Godot).
2. `godot-tests` — import + `tests/run_tests.gd` + asset-import + UI/campaign
   wrappers. Missing Godot → **NOT TESTED**, not pass.
3. `build-android` — export debug APK, `tool/check_android_apk.py`, size report.
4. `publish-release` — tag / `scripts/release.sh vX.Y.Z`.

Reproduce locally: [BUILD.md](BUILD.md). Device checklist: [DEVICE_QA.md](DEVICE_QA.md).

## Licensing

Every media file under `assets/` and `data/` (glb/gltf/bin/png/jpg/hdr/ttf/ogg/wav/…)
must be either:

- in `assets/manifest.json` (download lock → `sources[pack].license_file`), or
- under an explicit first-party prefix with a notice in `ASSET_LICENSES/`, or
- the Nicholas-3D warehouse tree (`data/models/warehouse/`, CC-BY-4.0).

See [THIRD_PARTY_ASSETS.md](../THIRD_PARTY_ASSETS.md). The mapping test fails
the build on an unmapped file.

## Release tooling

- `export_presets.cfg` must match `export_presets.cfg.example`.
- `version/name` / `version/code` must match `project.godot` (`0.7.0` / `4`).
- Android application id: `com.laststandarena.game`. Launcher label `Station Zero`
  is the short form of `config/name` `Last Stand: Station Zero` — do not “fix”
  them to be identical strings.
- No APK in a typical checkout. CI command:

  ```bash
  python3 tool/apk_size_report.py build/LastStandArena-debug.apk | tee build/apk-size-report.json
  ```

- Next GitHub Release notes: [RELEASE_NOTES_TEMPLATE.md](RELEASE_NOTES_TEMPLATE.md).
- Tag path: `bash scripts/release.sh vX.Y.Z` (clean tree, CHANGELOG mentions the
  tag, preset `version/name` matches).

## Historical audits

Dated audits under `docs/` keep the numbers they **executed**. Do not rewrite
those counts to match today's tools. A one-line “historical snapshot” banner is
the allowed correction. Live index: [README.md](README.md).
