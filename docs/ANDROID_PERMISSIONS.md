# Android permissions policy — Last Stand: Arena

**Status:** the app requests **no Android runtime permissions**. This is intentional
and correct: the game needs none, so none are declared or prompted.

## Why no permissions are needed

Verified across the codebase (autoloads, gameplay, UI, save, meta, audio, VFX):

- **Fully offline, single-player.** No networking. `RunAnalytics` is explicitly
  offline-only, and there are no `HTTPRequest` / socket / web clients in the game.
- **Save data is app-private.** All persistence (`SaveManager`, settings, meta
  progression, lifetime stats) writes to Godot's `user://`, which is the app's own
  internal storage. This requires no `READ`/`WRITE_EXTERNAL_STORAGE` permission.
- **No device hardware is accessed.** The game does not use the microphone, camera,
  GPS/location, sensors (gyro/accelerometer), Bluetooth, contacts, or notifications.
- **Haptics are opt-in and currently inert on Android.** The game does call
  `Input.vibrate_handheld()` (attack button feedback in `touch_action_button.gd`, hit
  feedback in `player_feedback.gd`), gated behind the user's `vibration_enabled`
  setting. **Correction to an earlier revision of this doc:** Godot does *not* add
  `VIBRATE` automatically. Verified against the pinned 4.4.1 engine source,
  `platform/android/export/export_plugin.cpp` emits `android.permission.VIBRATE` only
  when the export preset sets `permissions/vibrate` (line 945), and this project's
  `export_presets.cfg` declares no `permissions/*` at all. `Godot.kt` additionally
  gates the call behind `requestPermission("VIBRATE")`, which cannot succeed for a
  permission absent from the manifest. Net effect: no crash and no prompt, but the
  device never vibrates.
  Enabling haptics on device is a deliberate product decision — it means adding
  `permissions/vibrate=true` to the preset and accepting one more (normal,
  non-dangerous) permission in the installer listing, which the guards in
  `tests/python/test_android_permissions.py` currently forbid. `touch_action_button.gd`
  keeps the call off non-handheld platforms and strictly *after* the gameplay command
  is emitted, so haptics can never take the button down with them.
- **Rendering/output only.** Camera is virtual; audio is output-only.

Declaring unneeded permissions (especially `INTERNET`, storage, or vibration) is
actively harmful for a privacy review: it is unnecessary attack surface and shows up
in the store/installer as a permission the app never uses.

## Debug vs release nuance (Godot)

Godot's **debug** export auto-adds `android.permission.INTERNET` because the APK
contains the remote-debugger/profiler that connects to the editor over the network.
That is build/tooling only and is not a runtime feature of the game. The **release**
build used for distribution does not depend on it. Do not "fix" the no-permission
state by forcing permissions into the manifest — the game has no feature that needs
one.

## Verifying (no permissions in a build)

```bash
# After producing an APK (build/LastStandArena.apk), inspect its manifest:
#   - debug builds will list android.permission.INTERNET (Godot debugger) — expected.
#   - the application should declare NO dangerous permissions and no network sensor
#     storage/camera/mic entries beyond the Godot debug default above.
"${ANDROID_HOME}/build-tools/$(ls "${ANDROID_HOME}/build-tools" | tail -1)/aapt" dump permissions build/LastStandArena.apk
# Or, with Android Studio / SDK:
apkanalyzer manifest permissions build/LastStandArena.apk
```

## Project rules (keep it this way)

- The Android export preset (`export_presets.cfg`) declares **no** `permissions/*`
  options and no custom `AndroidManifest.xml`.
- Any future feature must justify the permission it needs before it is added, and the
  rule above ("no permission without a real, user-visible need") applies.
