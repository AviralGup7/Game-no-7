#!/usr/bin/env bash
# Host-only rendering for import previews / logic tests. The Android application
# keeps project.godot's Mobile renderer and platform overrides. Export must never
# inherit the host's Compatibility override (or need an X server to package an APK).
set -euo pipefail
GODOT_BIN="${GODOT_BIN:-${GODOT:-godot}}"
exporting=0
renderer_override=0
for argument in "$@"; do
  case "$argument" in
    --export-debug|--export-release|--export-pack|--export-patch) exporting=1 ;;
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
if [ "${GODOT_HEADLESS:-0}" = 1 ]; then
  exec "$GODOT_BIN" --headless "$@"
fi
if [ "$(uname -s)" = Linux ] && [ -z "${DISPLAY:-}" ]; then
  if ! command -v xvfb-run >/dev/null 2>&1; then
    echo 'ERROR: Native Godot checks need a display or xvfb-run (install xvfb and libgl1-mesa-dri).' >&2
    exit 1
  fi
  export LIBGL_ALWAYS_SOFTWARE=1
  exec xvfb-run -a -s '-screen 0 1280x720x24' "$GODOT_BIN" --rendering-method gl_compatibility "$@"
fi
exec "$GODOT_BIN" --rendering-method gl_compatibility "$@"
