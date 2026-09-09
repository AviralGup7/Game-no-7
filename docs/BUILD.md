# BUILD.md — Reproducing the Android build

## Pinned toolchain

| Tool | Version (pinned) | Notes |
|---|---|---|
| Godot | **4.4.1-stable** | Linux/macOS/Windows editor + export templates matching |
| Android SDK | API 34+ | cmdline-tools, platform-tools, build-tools |
| JDK | 17 (or bundled by Godot Android editor) | required by Android export |
| Python | 3.10+ | validation tooling (`tool/validate_resources.py`) |

Keep the editor version and its **export templates** identical. Mixing editor and
template versions breaks exports. The CI workflow (`android.yml`) installs the same
pinned Godot version on a fresh runner.

## First clone / import

```bash
godot --headless --path . --import
```

Generates `.godot/` caches (global class registry, `.uid` files, import steps). This
is required before tests/export run and is also done automatically in CI.

The reviewed core art/audio files are checked into `assets/`; a fresh clone does
not need to download third-party packs. Verify them offline before importing:

```bash
python3 scripts/download_assets.py --verify
python3 tool/validate_assets.py
python3 -m unittest discover -s tests/python -v
```

Restore a missing approved file with `python3 scripts/download_assets.py`; use
`--repair` to explicitly replace a damaged file. Downloads require access to the
pinned GitHub public content URLs but **verification, import and the game do not**.
No GitHub token is required by the asset downloader. A rate-limit/network error is
a failed download, not permission to bypass the hash lock; retry later or use the
already-versioned files. See `docs/ASSET_CATALOG.md` and the provenance manifests.

After import, test actual Godot resource types, skeletons and animation names (including the authored Warden):

```bash
godot --headless --path . --script res://tests/validate_asset_imports.gd
bash tool/test_hero_runtime.sh  # isolated profile; Player combat animation/equipment lifecycle
```

The export presets include `ASSET_LICENSES/*.txt` / `*.md` and both provenance
manifests, retaining the mandatory Rajdhani OFL copyright/licence with the fonts.
A `docs/ANDROID_PERMISSIONS.md` policy is also bundled so the no-permission posture is
auditable from inside the APK.

## Android permissions

The game is fully offline and requests **no Android runtime permissions** (verified:
no networking, sensors, microphone/camera, external storage, or vibration use; saves
use internal `user://`). Keep it that way — see `docs/ANDROID_PERMISSIONS.md` for the
rationale, the Godot debug-vs-release `INTERNET` nuance, and how to inspect a built
APK's manifest with `aapt dump permissions`.

## Environment variables (export / signing)

Never commit a keystore or its passwords. Supply through CI secrets / env instead:

- `ANDROID_HOME` — Android SDK root.
- `KEYSTORE_PATH` — path to a `.keystore` (signing).
- `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD` — signing credentials.

Without a keystore a **debug-signed APK** can still be produced for local validation.

## Validation & tests

```bash
# Static lint of GDScript (dev tool, requires gdtoolkit)
gdlint scripts tests

# Structural validation of .tscn/.tres hand-authored files
python3 tool/validate_resources.py

# Content/data registry validation runs at startup and via TestHarness.
# Headless unit tests:
godot --headless --path . --script res://tests/run_tests.gd
```

Exit code `0` means all checks pass.

> **Scope note (live-loop integrations):** the headless runner above is invoked with
> `--script`, which starts a bare `SceneTree` — it does **not** instantiate the
> project's autoload singletons (`GameRoot`, `EventBus`, `ContentRegistry`,
> `AudioManager`, …). For that reason the suites in `run_tests.gd` only exercise pure
> unit logic plus node-based integrations that do not depend on autoloads (e.g. the
> combat integration uses real `HealthComponent`/`DamagePayload` but injects its own
> clock). Driving the **real** end-to-end loop through GameRoot/EventBus/ContentRegistry
> (menu → run → wave-complete → upgrade selection/apply → game-over → restart, or
> SpawnManager accounting) requires a context where autoloads are live, e.g. a headless
> run of the main scene (`godot --headless --path .`) or a scene that owns those nodes.
> Attempting such a real-singleton test inside `run_tests.gd` fails at compile/parse time
> (autoload identifiers like `EventBus` are unresolved and loading the real `player.tscn`
> transitively compiles scripts that reference them), so it is intentionally **not**
> placed there.

## Android export

An Android export preset named **"Android"** must exist in `export_presets.cfg`
(scaffolded at `export_presets.cfg` — see `export_presets.cfg.example`). Build script:

```bash
bash scripts/build_android.sh                # debug-signed APK (no keystore needed)
BUILD_TYPE=release bash scripts/build_android.sh   # release APK (keystore configured)
```

CI installs the matching export templates for the pinned Godot version via
`chickensoft-games/setup-godot` (`include-templates: true`) and verifies them with
`scripts/install_export_templates.sh`. That script is deliberately strict: it downloads
the `Godot_v<version>_export_templates.tpz` release asset (if not already present),
extracts it with Python's `zipfile`, copies the files into Godot's data dir
(`~/.local/share/godot/export_templates/<version-string>/`, where the version string
uses a dot before `stable`, e.g. `4.4.1.stable`), and **fails loudly** unless the
Android build templates (`android_debug.apk`, `android_release.apk`,
`android_source.zip`) are actually present.

Because the Android export uses Gradle (`gradle_build/use_gradle_build=true`), Godot
additionally needs the Android **build** source template *inside the project*
(normally the Project menu → "Install Android Build Template"). In headless CI this is
done by `scripts/install_android_build_template.sh`, which mirrors Godot's own
installer: unzip `android_source.zip` into `res://android/build`, add an empty
`.gdignore`, write the template identifier into `res://android/.build_version`, and
`chmod +x gradlew` (Python's `zipfile` does not preserve Unix exec bits). Run this
before `godot --export-*`. A JDK (Temurin 17) is also required for the Gradle build.

What the build script does:

1. Verify `godot` exists.
2. Verify `export_presets.cfg` contains the Android preset.
3. Verify required project files (`project.godot`, main scene, scripts).
4. Verify the documented Godot version or report a mismatch.
5. Verify locked asset hashes, formats/dependencies and the Python asset tests (offline).
6. `godot --headless --path . --import`
7. Run native asset import checks (`tests/validate_asset_imports.gd`).
8. Run the headless unit tests (`tests/run_tests.gd`).
9. `python3 tool/validate_resources.py`
10. Install the Android build template into the project.
11. Export the selected debug/release APK using the Android preset.
12. Verify the APK exists and is non-zero.
13. Print the APK path and write a concise build report to `build/BUILD_REPORT.txt`.

**Release signing note:** `BUILD_TYPE=release` uses `--export-release`, which requires
the Android export preset's keystore to be configured (editor setting, never
committed). Debug builds need no keystore and are what CI publishes as artifacts/milestones.

### Manual export command

```bash
godot --headless --path . --export-debug "Android" build/LastStandArena-debug.apk
# release (keystore configured in the editor):
godot --headless --path . --export-release "Android" build/LastStandArena.apk
```

## Debug vs release

- **Debug** — verbose logging on, TestHarness/smoke available, debuggable.
- **Release** — verbose diagnostics stripped, debug-only systems gated by
  `OS.is_debug_build()` where practical, APK signed with the supplied keystore.

## Troubleshooting

- **"Android build template not installed in the project" at export time** → the export
  templates for the pinned Godot version are present in Godot's data dir, but the Android
  **build** template is not installed into the project. Run
  `bash scripts/install_android_build_template.sh` (creates `res://android/build`,
  `.gdignore`, `.build_version`) before exporting.
- **`android/build/gradlew: Permission denied`** → the build template was extracted
  without Unix exec bits. Re-run `bash scripts/install_android_build_template.sh`, which
  now `chmod +x`es `gradlew` and shell launchers after extraction.
- **"Android export not available"** → install Android export templates for the exact
  editor version via Editor → Manage Export Templates.
- **"preset not found"** → confirm `export_presets.cfg` lists a preset named `Android`.
- **Import errors on fresh clone** → run `--import` once (needed for class registry).
- **Play rejects debug-signed APK** → provide a release keystore + CI secrets.

## Publish a GitHub milestone release

Dispatch `Android build` on the intended branch with an explicit version tag:

```bash
gh workflow run android.yml --ref <branch> -f release_tag=v0.4.0
```

Tag-push runs also use the tag that triggered them. Publication waits for all checks
and the Android build to succeed, then downloads that job's exact APK rather than
building a second, independently validated binary. The release targets the workflow
commit and includes `LastStandArena-debug.apk` plus `SHA256SUMS.txt`. These are
**debug-signed sideload/testing milestones**, not Google Play production releases.
Use a new version tag for each release.

### Embedded model textures

`project.godot` sets the scene importer default `gltf/embedded_image_handling` to
**2 (Embed as Basis Universal)**. A fresh import keeps glTF/GLB embedded textures
inside Godot's imported scene cache instead of extracting duplicate PNGs next to
the source model. The source asset inventory therefore remains checksum-locked.
On an existing developer checkout, change the model's Import setting to Embed as
Basis Universal and reimport if its old `.import` sidecar still selects Extract
Textures. Only remove obsolete generated PNGs after confirming they are not in
`assets/manifest.json`; never delete the approved editable texture atlases.

### Authored hero assets

The checked-in Warden GLBs and three shared PNG maps import normally in Godot
4.4.1; Python/SciPy/Pillow are **optional authoring tools**, not build/runtime
dependencies. `tool/validate_assets.py` verifies the separate derived-output and
recipe lock. Rebuild/review instructions and validation limitations are in
`docs/HERO_FIDELITY.md`. Export presets include the derived provenance report and
its licence notice; authoring code and browser tooling stay excluded.
