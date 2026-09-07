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
5. `godot --headless --path . --import`
6. Run the headless unit tests (`tests/run_tests.gd`).
7. `python3 tool/validate_resources.py`
8. `godot --headless --path . --export-release "Android" build/LastStandArena.apk`
9. Verify the APK exists and is non-zero.
10. Print the APK path and write a concise build report to `build/BUILD_REPORT.txt`.

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
