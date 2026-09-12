# Android permissions policy — Last Stand: Station Zero

**Release policy:** the app requests **one** Android permission: `android.permission.VIBRATE`.
It is a normal (not dangerous) permission, so there is no runtime prompt. No other
permissions are enabled in the export preset; debug-export behavior is below.

## Why this permission set

Verified across the codebase (autoloads, gameplay, UI, save, meta, audio, VFX):

- **Fully offline, single-player.** No networking. `RunAnalytics` is explicitly
  offline-only, and there are no `HTTPRequest` / socket / web clients in the game.
- **Save data is app-private.** All persistence (`SaveManager`, settings, meta
  progression, lifetime stats) writes to Godot's `user://`, which is the app's own
  internal storage. This requires no `READ`/`WRITE_EXTERNAL_STORAGE` permission.
- **No device hardware is accessed except the vibrator.** The game does not use the
  microphone, camera, GPS/location, sensors (gyro/accelerometer), Bluetooth, contacts,
  or notifications.
- **Haptics are opt-in and declared.** The game calls `Input.vibrate_handheld()`
  (attack button feedback in `touch_action_button.gd`, hit feedback in
  `player_feedback.gd`), gated behind the user's `vibration_enabled` setting.
  Godot does *not* add `VIBRATE` automatically: `platform/android/export/export_plugin.cpp`
  emits `android.permission.VIBRATE` only when the export preset sets
  `permissions/vibrate`. This project's `export_presets.cfg` therefore declares
  `permissions/vibrate=true` so a handheld with vibration enabled actually vibrates.
  `touch_action_button.gd` keeps the call off non-handheld platforms and strictly
  *after* the gameplay command is emitted, so haptics can never take the button
  down with them.
- **Rendering/output only.** Camera is virtual; audio is output-only.

Declaring unneeded permissions (especially `INTERNET`, storage, camera, or mic) is
actively harmful for a privacy review: it is unnecessary attack surface and shows up
in the store/installer as a permission the app never uses.

## Debug vs release nuance (Godot)

Godot's **debug** export auto-adds `android.permission.INTERNET` because the APK
contains the remote-debugger/profiler that connects to the editor over the network.
That is build/tooling only and is not a runtime feature of the game. The **release**
build used for distribution does not depend on it. Do not add `INTERNET` to the
preset to "make debug easier" — the engine already injects it for debug APKs.

## Verifying (permission set in a build)

```bash
# After producing an APK (build/LastStandArena.apk), inspect its manifest:
#   - debug builds will list android.permission.INTERNET (Godot debugger) — expected.
#   - release builds should list android.permission.VIBRATE and no dangerous
#     permissions (no network / sensor / storage / camera / mic entries).
"${ANDROID_HOME}/build-tools/$(ls "${ANDROID_HOME}/build-tools" | tail -1)/aapt" dump permissions build/LastStandArena.apk
# Or, with Android Studio / SDK:
apkanalyzer manifest permissions build/LastStandArena.apk
```

The build and CI now run `tool/check_android_apk.py` against the **built APK**.
This checks the manifest's permissions (not just preset text), signing, ABI,
SDK levels, package/version and configured renderer. Packaging checks do not
substitute for physical haptic or lifecycle QA.

## Project rules (keep it this way)

- The Android export preset (`export_presets.cfg`) declares **only**
  `permissions/vibrate=true` and no custom `AndroidManifest.xml`.
- Any future feature must justify the permission it needs before it is added, and the
  rule above ("no permission without a real, user-visible need") applies.
