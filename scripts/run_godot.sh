#!/usr/bin/env bash
# Host-only rendering for import previews / logic tests. The Android application
# keeps project.godot's Mobile renderer and platform overrides. Export must never
# inherit the host's Compatibility override (or need an X server to package an APK).
#
# Routing rules (learned from 4.4.1 CI logs; keep strict check_godot_log.py clean):
#   * --import runs headless. Importing never touches a display or a GL context;
#     under xvfb the *editor* probes Vulkan (VK_KHR_surface) and host audio
#     (ALSA) and prints environment ERROR lines that fail the strict log gate
#     while exit status stays 0. The dummy drivers import identically.
#   * Scene-running invocations (--script, .tscn, no mode flag) stay native:
#     real GL via Mesa/xvfb so rendering regressions are exercised, but with
#     the Dummy audio driver and the opengl3 driver pinned so a host without
#     sound hardware or a Vulkan ICD prints the same log on every machine.
set -euo pipefail
GODOT_BIN="${GODOT_BIN:-${GODOT:-godot}}"
exporting=0
importing=0
renderer_override=0
for argument in "$@"; do
  case "$argument" in
    --export-debug|--export-release|--export-pack|--export-patch) exporting=1 ;;
    --import) importing=1 ;;
    --rendering-method|--rendering-method=*|--rendering-driver|--rendering-driver=*) renderer_override=1 ;;
  esac
done
if [ "$exporting" = 1 ]; then
  if [ "$renderer_override" = 1 ]; then
    echo 'ERROR: Renderer overrides are for host tests, not Android export. Configure the app in project.godot.' >&2
    exit 1
  fi
  exec "$GODOT_BIN" --headless "$@"
fi
if [ "$importing" = 1 ] || [ "${GODOT_HEADLESS:-0}" = 1 ]; then
  exec "$GODOT_BIN" --headless "$@"
fi
# Deterministic host audio: no ALSA/PulseAudio probe spam on machines without a
# sound device (CI runners). Pinned opengl3 keeps the Compatibility renderer
# from being re-derived per host. Both flags precede user args so an explicit
# later override still wins.
if [ "$(uname -s)" = Linux ] && [ -z "${DISPLAY:-}" ]; then
  if ! command -v xvfb-run >/dev/null 2>&1; then
    echo 'ERROR: Native Godot checks need a display or xvfb-run (install xvfb and libgl1-mesa-dri).' >&2
    exit 1
  fi
  export LIBGL_ALWAYS_SOFTWARE=1
  exec xvfb-run -a -s '-screen 0 1280x720x24' "$GODOT_BIN" \
    --rendering-method gl_compatibility --rendering-driver opengl3 \
    --audio-driver Dummy "$@"
fi
exec "$GODOT_BIN" --rendering-method gl_compatibility --rendering-driver opengl3 \
  --audio-driver Dummy "$@"
