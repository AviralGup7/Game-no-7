# Release notes template — next Station Zero milestone

Copy this file into the GitHub Release body (or a dated
`docs/release-notes-vX.Y.Z.md`) when tagging. Replace every `TBD` and the
version. Do not claim device/FPS numbers that were not measured on that build.

## Last Stand: Station Zero vTBD (YYYY-MM-DD)

**What it is:** a debug-signed ARM64 sideload APK of the shipping campaign
`scenes/campaign/station_zero.tscn`. Not a Google Play / 16 KB-page release.

**What it is not:** proof that touch, Vulkan, thermals or long traversal were
run on a phone. Those stay on [DEVICE_QA.md](DEVICE_QA.md).

### Campaign (from `python3 tool/validate_campaign.py`)

Fill these from a fresh validator run on the tagged tree — do not copy from
memory:

| Stat | Value |
|---|---|
| Bounds | 864 × 672 m |
| Districts | 12 |
| Missions | 13 |
| Floor regions / 8 m modules | 47 / 3 768 |
| Landmarks (solid props) | 72 |
| Interactions | 30 |
| Encounters / authored enemies | 32 / 96 |
| Walkable nav cells / perimeter edges | 13 440 / 1 676 |
| Activation / visibility caps | 18 living enemies / 3 district batches |

Route: docks → transit → hydroponics → foundry → cargo → reactor → medbay →
habitat → salvage → archive → comms → command → docks (extraction).

### Packaging

- Application id: `com.laststandarena.game`
- Launcher name: `Station Zero` (project name remains `Last Stand: Station Zero`)
- `version/name` / `version/code`: must match `export_presets.cfg` and
  `project.godot` (currently `0.7.0` / `4` — bump both before the tag)
- ABI: arm64-v8a; min SDK 24 / target SDK 34; permission: `VIBRATE` only
- APK size report (CI, no local APK required to draft this section):

  ```bash
  python3 tool/apk_size_report.py build/LastStandArena-debug.apk | tee build/apk-size-report.json
  ```

  Paste `apk_bytes` and the four ZIP groups (`native_libraries`, `godot_pack`,
  `assets`, `android_other`). ZIP size is not installed size or RAM.

### Known limitations (ship with every milestone)

- Headless GDScript / UI / campaign-native suites are CI evidence, not a device
  playtest. An environment without Godot must print **NOT TESTED**, never pass.
- Filesystem power-loss durability, Mobile/Vulkan frame time, thermal soak and
  multi-touch ownership on a real phone are **NOT RUNTIME VERIFIED** until
  [DEVICE_QA.md](DEVICE_QA.md) is filled in for *this* APK SHA-256.
- PCK encryption is off until a release keystore and script-encryption key are
  configured. Debug-signed artifacts are for sideload/testing.
- Arena / daily / challenge modes remain in the tree for regression; they are
  not the default app flow.
- Third-party notices ship in the APK (`ASSET_LICENSES/`, `THIRD_PARTY_ASSETS.md`).
  Warehouse mesh is CC-BY-4.0 (credit Nicholas-3D). Everything else in the
  download lock is CC0 / MIT / OFL as listed.

### Changes in this tag

- TBD (copy the matching `CHANGELOG.md` Unreleased block; delete it from
  Unreleased after the tag).

### Verification on the tag

Offline (no Godot): the 11 gates in [AGENTS.md](AGENTS.md).  
Native (CI): `godot-tests` + `build-android`.  
Device: attach the filled checklist, or write **not run**.
