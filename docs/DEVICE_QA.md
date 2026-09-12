# Android device QA — Last Stand: Station Zero

The product is an **Android, landscape, touch-first game**. Desktop/Godot host
checks are development tools, not Android certification. CI builds a
**debug-signed ARM64 APK**, not an unsigned APK or a Play-ready release.

## Build, verify and install

Development-host prerequisites: Godot **4.4.1-stable** and matching templates,
Java 17, Android SDK platform 34 / build-tools 34.0.0, and platform-tools (`adb`).
The APK is ARM64, minimum SDK 24; target SDK 34 matches this engine's template.
Current Play target/API requirements and 16 KB-page support must be checked
against a verified toolchain and APK. Upgrade matched engine/templates as needed;
do not assume a sideload smoke test proves store or page-size compliance.

```bash
bash scripts/build_android.sh
# build/LastStandArena-debug.apk + build/apk-validation.json

# One ready device is selected automatically. For several devices, be explicit:
ANDROID_SERIAL=<device-serial> bash scripts/device_qa.sh
# Or:
bash scripts/device_qa.sh --serial <device-serial> --apk build/LastStandArena-debug.apk

# Documentation only, deliberately NOT a validation pass:
bash scripts/device_qa.sh --checklist
```

Return to the game's menu before installing an update. The tool verifies the
actual APK's package/version, launcher, SDK levels, ARM64 ELF libraries, configured
Mobile renderer, permissions and signature **before** installing. It uses
`adb install -r`, force-stops only that verified package, launches it, checks that
its process stays alive, and inspects process-scoped logcat for startup errors.
It never uninstalls the app, clears app data, or clears the device's global logs.

A missing SDK/adb/device or ambiguous device selection is **not a pass**. The
script exits nonzero; missing/unauthorized devices return 2. `PKG` may not silently
launch an unrelated already-installed app: it must match the verified APK.

Reports are written to `build/device-qa/`:
- `result.json`: install/launch smoke outcome; manual checks remain pending.
- `apk-validation.json`: verified packaging metadata and APK SHA-256.
- `logcat.log`: app-process startup messages (when a process was started).

This automated smoke is not a substitute for the checklist below.

## Campaign acceptance checklist

- Fresh launch shows **NEW CAMPAIGN**, not an arena/daily/seed chooser. Existing
  saves show Continue; starting over requires confirmation and keeps settings,
  banked credits and permanent Armory ranks.
- Walk all six districts and all three long service causeways in one world.
  Shared deck edges are open, outer rails block void, and large props have matching
  collision. Check both routes around the ring; there must be no chapter load.
- Complete all seven objectives, including three separate cargo manifests and
  the return to the docks. Guarded consoles refuse interaction until their authored
  guards are defeated. The commander has finite slam/charge/shockwave phases.
- Hold MOVE/FIRE and use another finger on **INTERACT** or **MAP**. Interactions
  trigger once. Map pauses simulation and shows an accessible route, checkpoints
  and supplies. Back from Map returns to Pause; Back again resumes.
- Leave/revisit a district. Distant actors stop simulating, cleared enemies do not
  respawn and no reward is granted just for unloading an actor. Check the debug
  snapshot remains at or below 18 active enemies / three district batches.
- Activate a safe green rest pad or complete an objective; die and retry. Verify
  the named checkpoint, collected manifests, defeated IDs, upgrades, XP and loadout.
  Supply lockers and mission rewards cannot be collected twice after Continue.
- Kill a guard/open a cache, immediately Home → force-stop → relaunch. Verify the
  same save contains both its claimed ID and credited reward. Repeat with low
  storage: show a save error, retain the previous valid profile and allow retry.
- Complete extraction, then choose **EXPLORE STATION**. No ending/reward loop;
  remaining optional supplies/patrols stay available. New Campaign resets only
  campaign state after confirmation.

## Touch, lifecycle and presentation checklist

1. **Boot:** correct title, landscape orientation, touch controls visible without a
   keyboard/mouse. No frozen loading screen or runtime error overlay.
2. **Three-finger input:** hold the left stick, hold/drag FIRE, then tap a READY
   skill with another finger. The skill activates once; movement/FIRE keep their
   owners. Tap PAUSE while both thumbs remain down; it must respond immediately.
3. **Reload/dodge/swap:** each works independently of the other held fingers.
   Empty magazines auto-reload. Moving or tapping a skill must not itself fire a
   gun through an emulated mouse event. Locked/cooling skills stay inactive.
4. **Canceled gestures:** use Android gesture navigation, interrupt a drag, and
   return. No stuck movement, FIRE, skill press or camera spin. Resuming requires
   fresh touch-downs. Dragging off a gameplay control must not become camera look.
5. **Cutouts/rotation:** test a notched phone in both landscape orientations,
   including a 180-degree flip that does not change width/height. Show/hide system
   bars. Controls remain inside the safe area and held gestures are canceled when
   the controls move. Check text scales and actual physical touch-target sizes on
   high-DPI phones; logical geometry alone is not a dp measurement.
6. **Back/gesture Back:** gameplay → pause; pause → resume; settings/help → previous
   screen; game-over → menu; menu → save-guarded exit. Never exits mid-fight.
7. **Home/recents/lock/call:** background mid-encounter and return. Gameplay remains
   paused until RESUME. Audio stays muted until the activity is both resumed and
   focused; focus-in alone while paused must not unmute it. User mute stays set.
8. **Persistence:** buy an Armory upgrade/change settings, immediately background,
   force-stop and relaunch. Verify progression/settings survived and no false
   corruption warning appears. Also run the fault checks in SAVE_RESILIENCE.md.
9. **Full lifecycle:** menu → campaign → pause → menu → Continue, plus death/checkpoint retry.
   Touch, spatial Foley, camera, skills and upgrade effects bind to the new player.
10. **Rendering:** test Mobile/Vulkan on a supported phone, including shadows,
    materials and effects. Test the intended driver fallback separately; a
    host Compatibility-renderer test does not exercise the Android GPU driver.
11. **Performance/thermals:** play at least five minutes on a lower-end and a
    modern device. Record FPS, pacing, heat, memory and battery behavior. Android
    has a 60 FPS ceiling and starts at 2x MSAA; the governor may lower the tier.
12. **Haptics/privacy:** vibration on/off follows Settings with no dangerous
    permission prompt. Release permission policy is VIBRATE only; debug exports
    may add INTERNET for Godot's debugger. No external-storage permission is needed.
13. **Logs:** no SCRIPT ERROR, freed-object errors, duplicate UI activations or
    repeated touch-cancel spam during normal thumb lifts.

Record device model, Android version, display size/DPI/cutout, APK SHA-256,
renderer used and results. Optional Bluetooth controllers are secondary input;
no essential gameplay operation should require one.
