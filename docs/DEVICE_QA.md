# Device QA — Last Stand: Arena

CI produces an unsigned **debug** APK (`build/LastStandArena-debug.apk`). That is
not a substitute for a physical device. Run this once per milestone.

## Install

```bash
bash scripts/build_android.sh          # debug APK
bash scripts/device_qa.sh              # adb install -r if a device is connected
```

Package id: read from `package/unique_name` in `export_presets.cfg` (currently
`com.laststandarena.game`; override with `PKG=` for preset experiments).

## Play checklist (one sitting)

1. **Boot** — main menu, no freeze, landscape, keep-screen-on.
2. **Touch** — left joystick, attack, dodge, skill bar, weapon switch. Attack/dodge fire on press-down (no tap-duration lag); a declined tap (dodge on cooldown) toasts but must NOT move the stick/buttons.
3. **Full loop** — start run → fight a wave → pause → resume → pause → **Main Menu** → start a **new** run (must not stay frozen).
4. **Restart** from game over; minimap and world names stay valid.
5. **Back button** — gameplay → pause; pause → resume; settings/help → back to previous; game-over → menu; menu → guarded quit. Never quits mid-run.
6. **Interrupt** — Home/recents mid-wave, take a call, then return: the run must be paused on return (never damage taken while backgrounded); audio stays muted until resumed.
7. **Thermals / pacing** — 3+ minutes: watch for 30 fps cap sticking after a dip (PerformanceMonitor should restore on teardown).
8. **Haptics** — Settings vibration on/off; no extra permission prompt.
9. **Audio** — menu bed, combat bed, SFX; mute/unmute in settings.
10. **Logcat hygiene** — lifting the thumb off the stick must not dump input-trace blocks; only pause/focus interruptions log.

Record device model, Android version, and any frame-time spikes in the PR.

## Why this is in-repo

The sandbox cannot USB-install. The script is the reproducible stand-in: it
sideloads when `adb` sees a device and otherwise prints this checklist.
