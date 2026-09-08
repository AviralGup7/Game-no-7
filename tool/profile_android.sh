#!/usr/bin/env bash
# Desktop/headless lifecycle probe, NOT a substitute for physical Android profiling.
# GODOT_BIN=/path/to/godot bash tool/profile_android.sh [--low-tier]
# HEADLESS=0 uses the desktop renderer when a display/GPU is available.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-godot}"
command -v "$GODOT_BIN" >/dev/null || { echo "Godot 4.4.1 is required (set GODOT_BIN)." >&2; exit 2; }
cd "$ROOT"
mkdir -p .cache/performance build/perf
export XDG_DATA_HOME
XDG_DATA_HOME="$(mktemp -d "$ROOT/.cache/performance/profile.XXXXXX")"
# Import cache stays shared, but saves/settings never touch the player's profile.
timeout 180s "$GODOT_BIN" --headless --path "$ROOT" --import > build/perf/import.log 2>&1
if grep -Eq 'SCRIPT ERROR:|ERROR:|Parse Error:' build/perf/import.log; then
  cat build/perf/import.log
  exit 1
fi
args=()
if [[ "${HEADLESS:-1}" == 1 ]]; then args+=(--headless); fi
for profile in fresh existing; do
  timeout 180s "$GODOT_BIN" "${args[@]}" --path "$ROOT" res://tests/integration/android_performance.tscn \
    -- --isolated-performance-tests "$@" 2>&1 | tee "build/perf/$profile.log"
  if ! grep -Eq 'PERF TESTS: [0-9]+ checks, 0 failed' "build/perf/$profile.log" \
    || grep -Eq 'SCRIPT ERROR:|ERROR:|Parse Error:|PERF FAIL:' "build/perf/$profile.log"; then
    exit 1
  fi
done
printf 'Reports: build/perf/{fresh,existing}.log\nIsolated saves: %s\n' "$XDG_DATA_HOME"
