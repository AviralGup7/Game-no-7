# Android-first follow-up — 2026-09-12

**Target:** Last Stand: Station Zero, Android / ARM64, landscape, touch-first.
Keyboard/controller bindings and desktop rendering are development conveniences,
not requirements to play the Android app.

## Changes applied

### Multi-touch and interrupted gestures

- Skills and the HUD PAUSE button now have `TouchButtonInput` adapters. They
  accept their own `InputEventScreenTouch` fingers on press-down while movement
  and FIRE remain held. Synthetic mouse copies are consumed before BaseButton
  can activate a second time. Disabled/hidden buttons and canceled touches do not
  activate; release outside the button still clears ownership.
- Android skill hints say **TAP / READY**, not keyboard bindings.
- Joystick cancellation handles Android's canceled event even when `pressed` is
  still true. Emulated mouse events cannot reacquire the joystick afterward.
- Camera look begins only with a fresh unhandled touch-down in empty look space.
  A drag leaving a gameplay control cannot start camera rotation. Cancellation,
  pause, backgrounding, overlays and safe-area changes clear captured fingers and
  queued camera deltas.

### Cutouts, lifecycle and device defaults

- Safe-area calculation clips platform rectangles to the window and rejects
  non-finite geometry. Insets are checked at a low rate and after foregrounding,
  not only on viewport resize: a 180-degree landscape flip can swap notch sides
  without changing width/height. Unchanged polling does not rewrite offsets or
  cancel input. Actual layout changes cancel held gestures before repositioning.
- Audio tracks **activity pause** and **focus** separately. A focus-in while the
  app remains paused, or a resume beneath an unfocused system overlay, cannot
  prematurely unmute it. Foreground restoration preserves user mute. Gameplay
  remains paused until the player explicitly resumes.
- Player-feedback haptics run only on mobile and respect vibration settings.
- Android keeps its Mobile renderer and 60 FPS ceiling. Startup MSAA has an
  Android-specific 2x override (enum 1); the existing quality governor still owns
  in-run quality changes. No phone FPS or thermal claim follows from this default.

### Real Android packaging and device QA

- Host Compatibility/Xvfb rendering is now explicitly **host-only**. Export
  commands run headless without a renderer override; explicit export-time
  overrides are rejected. The APK's manifest rendering-method metadata is checked
  against the Android project setting, preventing a desktop-test override from
  silently changing the shipped backend.
- `tool/check_android_apk.py` verifies the actual APK: ZIP integrity, nonempty
  game assets, native ELF machine/class and enabled ABIs, package/version,
  launcher, min/target SDK, renderer metadata, permission policy and apksigner
  verification. Release checks reject a debuggable APK/debug signing certificate.
  A failed validation replaces stale successful validation state.
- Developer reports, test data and caches are explicitly excluded from APK assets.
- CI installs the SDK platform/build-tools required by Godot 4.4.1 and verifies
  the APK before upload. SDK-license and APK/launch failures are not swallowed.
- `scripts/device_qa.sh` now verifies the APK before installing, selects one
  authorized device explicitly, uses data-preserving `install -r`, checks process
  liveness and app-scoped logcat, and writes a machine-readable result. Missing
  adb/SDK/device is **not tested**, not a pass. `--checklist` is documentation only.
  See [DEVICE_QA.md](DEVICE_QA.md) for the physical-device checklist.

## Validation in this follow-up

| Check | Result |
|---|---|
| Python suite | 1,099 tests passed, including 25 new Android/tooling tests |
| GDScript lint | Passed |
| API, scene-path, signal, format, architecture, resource and guard gates | Passed |
| Bash syntax / diff whitespace / workflow YAML structure | Passed; GitHub Actions itself not executed here |
| New native Android input/lifecycle regressions | Added and registered; not executed in this follow-up |
| Updated real-node UI interruption/multi-touch checks | Added; not executed in this follow-up |
| Actual APK export, SDK signature/manifest tools and physical device | Not available in this sandbox; not claimed as tested |

The packaging/adb Python tests use explicit local fakes. They verify checks,
error handling and command selection, not a real APK or a physical Android
session. The prior source-built Godot engine was in an excluded temporary cache
and is not present in this workspace snapshot. A fresh pinned-binary download
failed at the release CDN. No new source build or Android execution was claimed.
The [September 11 audit](PROJECT_AUDIT.md) remains historical evidence for that
revision; its native test counts are not reused as proof of these later changes.

## Toolchain and distribution boundary

The pinned Godot **4.4.1-stable** template uses compile SDK 34, target SDK 34,
build-tools 34.0.0 and Java 17. The app's minimum SDK stays 24 and ARM64 is the
shipping ABI. These were not blindly bumped beyond the engine/template contract.
This is a sideload/debug milestone, **not current Google Play or 16 KB-page
certification**. Store-target/toolchain updates and native page-size/device
validation remain separate work and may require a matched engine/template upgrade.
Matching engine/export templates must be used for the build.

Relevant pinned-engine source checked while making these changes:
- [BaseButton input](https://github.com/godotengine/godot/blob/4.4.1-stable/scene/gui/base_button.cpp): mouse/ui_accept handling does not replace independent raw-touch ownership.
- [Control input order](https://github.com/godotengine/godot/blob/4.4.1-stable/scene/gui/control.cpp): `gui_input` signal is emitted before native handling and can consume an event.
- [Android template versions](https://github.com/godotengine/godot/blob/4.4.1-stable/platform/android/java/app/config.gradle).
- [Android renderer metadata](https://github.com/godotengine/godot/blob/4.4.1-stable/platform/android/java/app/AndroidManifest.xml).
