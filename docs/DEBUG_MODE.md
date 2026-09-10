# Debug mode — freeze on error with a copyable report

On-device (APK) debugging aid. When debug mode is **ON**, any error reported
through `EventBus` freezes the game instead of crashing and shows a copyable
report with everything needed to file a bug. When **OFF** (the default), the
game behaves exactly as before.

## Turning it on

- **Main menu** (visible from the moment the game starts): the
  `Debug mode: freeze on error with a copyable report` switch under the records
  plate.
- **Settings > Debug**: the same switch, plus tools (below).
- The choice persists across launches in `user://debug_mode.cfg` (owned by the
  handler itself, not the save file, so it works even when saves are broken).
- QA automation flags (after `--`): `--debug-mode` forces ON,
  `--debug-mode=off` forces OFF, `--no-debug-freeze` keeps logging while never
  pausing (for scripted runs).

## What happens on an error (debug ON)

1. The tree pauses — the simulation, enemies, timers, everything stops.
2. A full-screen overlay shows the report: title, UTC timestamp, message, stack
   trace, device/game context (app + engine version, OS, device model, memory,
   FPS, game state, run/wave/score, scene), and the last 60 log lines.
3. Every capture is also auto-saved to `user://logs/crash_<UTC-timestamp>.log`
   (newest 5 kept).

## Overlay actions

| Button | Effect |
|---|---|
| `COPY REPORT` (or Ctrl+C) | Copies the whole block to the OS clipboard. The button confirms with the size (`COPIED ✓ (12.4 KB)`); if the clipboard round-trip fails it says so and the text stays selectable for a manual long-press copy. |
| `SAVE TO FILE` | Writes `user://logs/report_<timestamp>.txt` and shows the path. |
| `< PREV` / `NEXT >` | Steps through stacked errors (cascades are kept, newest 10). |
| `RESUME GAME` | Closes the overlay and restores the exact pre-freeze pause state. |
| `RESTART RUN` / `MAIN MENU` | Resume, then the matching `GameRoot` command. |

## Settings > Debug tools

- `TRIGGER TEST ERROR` — freezes with a sample report so testers can prove the
  copy path works on a device without waiting for a real bug. Requires debug
  mode ON (it says so if it is off).
- `VIEW LAST ERROR REPORT` — re-opens the newest kept report (visible only when
  at least one exists).
- `VIEW LAST SESSION LOG` — visible only when the previous session did not
  exit cleanly; presents its recovered log tail as a report.

## Files (all under the app's private `user://`)

- `debug_mode.cfg` — the persisted flag.
- `logs/session.log` — this session's diagnostics + breadcrumbs (state changes,
  run start/end, wave starts); rotated to `logs/session.previous.log` on boot,
  capped at 256 KiB.
- `logs/session.json` — `{"clean_exit": ...}` exit flag for crash recovery.
- `logs/crash_*.log` — auto-saved captures. `logs/report_*.txt` — explicit saves.

## Coverage and honest limitations

- **Covered:** every authored failure point — `EventBus.report_error` is what
  world build, arena load, player spawn, spawn/wave systems, and saves call on
  failure. Authored guards can also call
  `DebugErrorHandler.capture_error(message)` directly.
- **Hard native crashes** (segfault, OOM kill, force-stop) cannot be
  intercepted from GDScript. For those, each boot checks the previous
  session's exit flag; an unclean exit keeps its recovered log one click away
  in Settings > Debug. Note Android background kills also count as unclean —
  treat the flag as a hint, not proof of a crash.
- **Headless runs** (`--headless`, CI) never freeze — there is no screen to
  read the report on. They still log and still write crash files.
- The handler is declared directly after `EventBus` so it captures boot errors
  from every later singleton, and its own I/O failures use `push_warning`
  directly so error handling can never report an error about itself.

## Architecture pointers

- `scripts/debug/debug_error_handler.gd` — autoload (`DebugErrorHandler`,
  `class_name DebugErrorHandlerService`): flag, log ring, capture, freeze,
  files.
- `scripts/debug/debug_error_overlay.gd` — the overlay (presents text, emits
  intents; all actions stay in the handler).
- `scripts/debug/debug_mode_toggle.gd` — the shared switch (menu + settings).
- `scripts/debug/error_report.gd`, `scripts/debug/debug_log_buffer.gd` — pure,
  unit-tested formatting + ring buffer (`tests/unit/test_error_report.gd`).
