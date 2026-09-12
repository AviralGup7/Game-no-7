# BUILD.md — Reproducing the Android build

## Pinned toolchain

| Tool | Version (pinned) | Notes |
|---|---|---|
| Godot | **4.4.1-stable** | Linux/macOS/Windows editor + export templates matching |
| Android SDK | API 34+ | cmdline-tools, platform-tools, build-tools |
| JDK | 17 (or bundled by Godot Android editor) | required by Android export |
| Python | 3.10+ | validation tooling (`tool/validate_resources.py`) |

`.godot-version` is the local source of truth; the CI pin is checked against it.
Keep the editor and **export templates** identical. The local build fails before
expensive work on a patch-version mismatch. `GODOT_BIN` can name the editor binary.
The Bash build/test wrappers support Linux/WSL and macOS with Python installed;
on Windows use WSL or the editor's native export UI.

## Shipping campaign entry

`project.godot` and `SceneRouter` boot `scenes/campaign/station_zero.tscn`.
The default menu offers Continue/New Campaign, not arena/daily/seed selection.
Both Android export presets explicitly include `data/campaign/*.json`;
`check_android_apk.py` opens the exported campaign JSON and checks its actual
content/topology in addition to the APK metadata. The configured non-OBB export
must contain `assets/data/campaign/station_zero.json`; alternate encrypted/packed
layouts require an explicit checker change, not a waived missing-content gate.

`python3 tool/validate_campaign.py` is offline. `bash scripts/run_campaign_validation.sh`
imports and runs the real shipping scene using an isolated profile, a timeout and
strict logs. It is called by the local build and CI native job. An absent engine
returns **NOT TESTED / exit 2**, never a passing result. See [campaign notes](campaign/README.md).

## Android target versus host-only rendering

The APK uses `project.godot`'s **Mobile renderer**, Android's 60 FPS ceiling and
2x startup MSAA. The 4.4.1 Android template pins compile SDK/build-tools 34 and
Java 17; the export remains ARM64 with min SDK 24 / target SDK 34. This is a
sideload milestone, not a claim of current Google Play or 16 KB-page compliance.

`scripts/run_godot.sh` routes Godot by invocation type, so each step keeps a
log channel the strict `tool/check_godot_log.py` gate can trust:

- **`--import` always runs headless.** Resource import touches neither a
  display nor a GL context, and under Xvfb the editor's own Vulkan (`VK_KHR_surface`)
  and ALSA probes print environment ERROR lines that must never reach the gate.
  The headless editor's GLB/GLTF preview-thumbnail generation emits an
  enumerated dummy-renderer null-texture pair, demoted via
  `check_godot_log.py --allow-engine-noise` (context-bound; importers, parse
  errors and every other line still fail the step).
- **Scene-running steps** (`--script`, `.tscn`, plain `--path`) stay **native**:
  real Compatibility GL via Mesa/Xvfb so rendering regressions are exercised,
  pinned to `--rendering-driver opengl3` and Dummy audio so a host without a
  Vulkan ICD or sound device logs identically everywhere. Under a real GL
  driver the engine prints a small, enumerated set of teardown/shutdown
  reports (scene-cull null-material RID queries, GL texture exit accounting,
  ObjectDB/resource exit reports) that carry no `res://` location and are not
  game defects; the native-step gates opt into demoting exactly those
  headline+`at:` pairs via `check_godot_log.py --allow-engine-noise`.
- **Export** detects export commands, uses `--headless` with **no renderer
  override**, and rejects explicit export-time renderer overrides. This
  prevents the host test backend from leaking into the Android manifest/project.
  The final APK verifier checks its renderer metadata.

On display-less Linux the native steps need Xvfb/Mesa (CI installs them):

```bash
sudo apt-get install xvfb libgl1-mesa-dri
```

**They are not Android app dependencies.** `GODOT_BIN` (or legacy `GODOT`) chooses
the engine. `GODOT_HEADLESS=1` forces headless as an explicit logic-only host
diagnostic mode, not release validation. See
[ANDROID_HARDENING.md](ANDROID_HARDENING.md) for the Android follow-up and
[PROJECT_AUDIT.md](PROJECT_AUDIT.md) for the earlier source-built host-test limits.

## First clone / import

```bash
bash scripts/run_godot.sh --path . --import
```

Generates `.godot/` caches, the global class registry and import/UID sidecars. This
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
bash scripts/run_godot.sh --path . --script res://tests/validate_asset_imports.gd
bash tool/test_hero_runtime.sh  # isolated profile; Player combat animation/equipment lifecycle
```

The export presets include `ASSET_LICENSES/*.txt` / `*.md` and both provenance
manifests, retaining the mandatory Rajdhani OFL copyright/licence with the fonts.
A `docs/ANDROID_PERMISSIONS.md` policy is also bundled so the permission posture is
auditable from inside the APK.

## Android permissions

The game is fully offline and requests **only** `android.permission.VIBRATE` (a
normal permission so opt-in haptics work; verified: no networking, sensors,
microphone/camera, or external storage; saves use internal `user://`). Keep it
that way — see `docs/ANDROID_PERMISSIONS.md` for the rationale, the Godot
debug-vs-release `INTERNET` nuance, and how to inspect a built APK's manifest
with `aapt dump permissions`.

## Environment variables (export / signing)

Never commit a keystore or its passwords. Supply through CI secrets / env instead:

- `ANDROID_HOME` — Android SDK root.
- `GODOT_ANDROID_KEYSTORE_RELEASE_PATH` — release keystore path.
- `GODOT_ANDROID_KEYSTORE_RELEASE_USER` — key alias.
- `GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD` — shared keystore/key password.

The build wrapper also maps the legacy `KEYSTORE_PATH`, `KEY_ALIAS`,
`KEYSTORE_PASSWORD` / `KEY_PASSWORD` aliases to Godot's native variables. Godot's
Android exporter requires the key and keystore passwords to match; conflicting
aliases are rejected. These values are never written into a tracked preset.

Without a keystore a **debug-signed APK** can still be produced for local validation.

## Validation & tests

```bash
# Static lint of GDScript (dev tool, requires gdtoolkit)
gdlint scripts tests

# Structural validation of .tscn/.tres hand-authored files
python3 tool/validate_resources.py
python3 tool/validate_campaign.py

# Engine-API contract gate (offline, stdlib-only): every typed member access,
# bare global call and .tscn/.tres property is checked against the pinned
# engine's ClassDB (tool/godot_api_manifest.json). Regenerate the manifest with
# `python3 tool/build_api_manifest.py` when GODOT_VERSION changes.
python3 tool/check_engine_api.py

# Scene-path contract gate (offline, stdlib-only): every get_node / NodePath
# literal is resolved against the actual scene trees; a renamed or removed
# node fails the build instead of the runtime.
python3 tool/check_scene_paths.py

# String-format contract gate (offline, stdlib-only): every "..." % use is
# verified against the pinned engine's String::sprintf rules; an arity or
# placeholder mismatch fails the build instead of erroring at runtime.
python3 tool/check_string_formats.py

# Signal contract gate (offline, stdlib-only): every signal name and emit
# arity is resolved against the declaring classes; a phantom signal or a
# wrong arity fails the build instead of erroring at runtime.
python3 tool/check_signals.py

```

Run native units/integrations in an isolated profile (Bash; after importing):

```bash
(
  mkdir -p .cache/test-reports
  source scripts/godot_test_env.sh
  godot_test_profile "$(mktemp -d "$PWD/.cache/test-reports/profile.XXXXXX")"
  godot_test_timeout 180 bash scripts/run_godot.sh --path . --script res://tests/run_tests.gd \
    > .cache/test-reports/unit.log 2>&1
  code=$?
  python3 tool/check_godot_log.py .cache/test-reports/unit.log --exit-code "$code" \
    --allow-test-errors --require '^GDScript tests: [1-9][0-9]* total, 0 failed$'
)
bash tool/test_hero_runtime.sh
bash scripts/ui/run_ui_validation.sh      # legacy combat/UI regressions
bash scripts/run_campaign_validation.sh  # shipping campaign flow
```

The wrappers isolate **both HOME and XDG paths**, including Godot's macOS save
location, and retain disposable profiles/logs for inspection. UI checks run with a
fresh profile and then the same existing profile. Do not run save-mutating UI or
flow harnesses against your own progression.

Godot can return zero even after script/resource errors. `tool/check_godot_log.py`
requires a clean error channel and a non-empty success summary, not just an exit
code. Unit-only intentional diagnostics use `ExpectedErrors.begin([...])` / `end()`
with exact lines and counts; missing, additional, nested or unterminated messages
still fail. Import/export/player/UI logs do **not** enable this exception protocol.

The runner compiles before project autoload identifiers are registered, so it
runtime-loads suite/stage scripts rather than preloading game classes. Tree-independent
units run in `_initialize()`; live-node suites wait for `_process()`, when global
transforms are meaningful. The real project autoloads are available to those
runtime-loaded stages. Preserve this load-order boundary when adding integrations.
The player and UI harnesses cover additional multi-frame lifecycle behavior.

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
(`$XDG_DATA_HOME/godot/export_templates/<version-string>/`, defaulting to
`~/.local/share/godot/...` on Linux, or `~/Library/Application Support/Godot/...` on
macOS). The version uses a dot before `stable`, e.g. `4.4.1.stable`.
`GODOT_TEMPLATE_DIR` overrides the **complete per-version directory**. The installer
validates every archive member in private staging (including traversal/symlink
rejection), checks the version, and **fails loudly** unless the
Android build templates (`android_debug.apk`, `android_release.apk`,
`android_source.zip`) are actually present.

Because the Android export uses Gradle (`gradle_build/use_gradle_build=true`), Godot
additionally needs the Android **build** source template *inside the project*
(normally the Project menu → "Install Android Build Template"). In headless CI this is
done by `scripts/install_android_build_template.sh`, which mirrors Godot's own
installer: unzip `android_source.zip` into `res://android/build`, add an empty
`.gdignore`, write the template identifier into `res://android/.build_version`, and
`chmod +x gradlew` (Python's `zipfile` does not preserve Unix exec bits). Run this
before `godot --export-*`. Matching existing templates are reused without deleting
project customizations. An incomplete or different-version `android/build` is
refused: preserve your customizations and explicitly move it aside before retrying.
A JDK (Temurin 17) is also required for the Gradle build.

What the build script does:

1. Verify the engine exists and matches `.godot-version` exactly.
2. Verify required files and that the selected preset is Android.
3. Run locked-asset, resource, architecture, guard, API/path/format/signal and Python checks.
4. Import and validate the full Godot log (not just process status).
5. Run native asset and unit/integration tests in a disposable profile.
6. Run the player runtime and fresh/existing-profile UI lifecycle checks.
7. Install/reuse matching export and Android build templates safely.
8. Remove the selected stale APK, then export debug or release.
9. Run `tool/check_android_apk.py`: verify the APK's identity/version, launcher,
   SDK levels, native ELF/ABI, Mobile-renderer metadata, permission policy and
   signature; reject test/developer assets. Write `build/apk-validation.json`.
10. Write `build/BUILD_REPORT.txt` with the result; failures record the failed stage.

**Release signing:** `BUILD_TYPE=release` uses `--export-release` with the native
secret environment variables above or private editor credentials. Debug builds
need no custom keystore and are what CI publishes as artifacts/milestones. A
failed native CI job can still produce a **diagnostic APK artifact**, but release
publication requires offline validation, native tests **and** Android export to
all succeed.

### Manual export command

```bash
bash scripts/run_godot.sh --path . --export-debug "Android" build/LastStandArena-debug.apk
# release (keystore configured in the editor):
bash scripts/run_godot.sh --path . --export-release "Android" build/LastStandArena.apk
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
- **Parse/compile errors** → first confirm the pinned engine and finish a clean
  import. Inspect the full log with `tool/check_godot_log.py`; do not dismiss an
  error just because Godot exited zero or a test summary printed. Persistent
  errors need the exact message, engine version and `res://` location. The newer
  diagnostics workflow is informational and does not replace the pinned gate.

## Publish a GitHub milestone release

Dispatch `Android build` on the intended branch with an explicit version tag:

```bash
gh workflow run android.yml --ref <branch> -f release_tag=v0.7.0
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

## Android package and on-device validation

```bash
python3 tool/check_android_apk.py build/LastStandArena-debug.apk \
  --build-type debug --report build/apk-validation.json
ANDROID_SERIAL=<device-serial> bash scripts/device_qa.sh
bash scripts/device_qa.sh --checklist  # instructions only; not a test pass
```

The checker requires `aapt2`/`aapt`, `apksigner` and Java. Set `ANDROID_SDK_ROOT` /
`ANDROID_HOME` or `ANDROID_BUILD_TOOLS_DIR` if needed. CI installs platform-tools,
`platforms;android-34` and `build-tools;34.0.0` explicitly for the pinned template.
The device helper refuses missing/ambiguous devices, validates the actual APK
before installation, scopes adb/logcat to the selected device/process, and never
uninstalls or clears progression. See [DEVICE_QA.md](DEVICE_QA.md).
