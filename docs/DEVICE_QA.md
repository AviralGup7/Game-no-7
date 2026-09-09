# Device QA — Last Stand: Arena

CI produces an unsigned **debug** APK (`build/LastStandArena-debug.apk`). That is
not a substitute for a physical device. Run this once per milestone.

## Install

```bash
bash scripts/build_android.sh          # debug APK
bash scripts/device_qa.sh              # adb install -r if a device is connected
```

Package id: `com.laststand.arena` (override with `PKG=` if the export preset changes).

## Play checklist (one sitting)

1. **Boot** — main menu, no freeze, landscape, keep-screen-on.
2. **Touch** — left joystick, attack, dodge, skill bar, weapon switch.
3. **Full loop** — start run → fight a wave → pause → resume → pause → **Main Menu** → start a **new** run (must not stay frozen).
4. **Restart** from game over; minimap and world names stay valid.
5. **Thermals / pacing** — 3+ minutes: watch for 30 fps cap sticking after a dip (PerformanceMonitor should restore on teardown).
6. **Haptics** — Settings vibration on/off; no extra permission prompt.
7. **Audio** — menu bed, combat bed, SFX; mute/unmute in settings.

Record device model, Android version, and any frame-time spikes in the PR.

## Why this is in-repo

The sandbox cannot USB-install. The script is the reproducible stand-in: it
sideloads when `adb` sees a device and otherwise prints this checklist.
