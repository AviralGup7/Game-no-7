#!/usr/bin/env bash
# build_android.sh — reproducible Android APK build for "Last Stand: Arena".
#
#   BUILD_TYPE=debug   (default) export a debug-signed APK — no keystore needed.
#   BUILD_TYPE=release export a release APK (requires the Android export preset's
#                        release keystore to be configured — see docs/BUILD.md).
#
# Exits non-zero on any failure. See docs/BUILD.md.
set -euo pipefail

GODOT_BIN="${GODOT_BIN:-godot}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$PROJECT_DIR/build"
BUILD_TYPE="${BUILD_TYPE:-debug}"
PRESET_NAME="${PRESET_NAME:-Android}"
PINNED_GODOT="4.4"

export PATH="$PATH"

mkdir -p "$OUT_DIR"
REPORT="$OUT_DIR/BUILD_REPORT.txt"

case "$BUILD_TYPE" in
  debug)   APK="$OUT_DIR/LastStandArena-debug.apk"; EXPORT_ARGS=(--export-debug) ;;
  release) APK="$OUT_DIR/LastStandArena.apk";       EXPORT_ARGS=(--export-release) ;;
  *) echo "ERROR: BUILD_TYPE must be debug or release (got '$BUILD_TYPE')."; exit 1 ;;
esac

step() { echo ""; echo "==> $*"; }

step "Verify Godot exists"
if ! command -v "$GODOT_BIN" >/dev/null 2>&1; then
  echo "ERROR: godot binary not found (GODOT_BIN=${GODOT_BIN})." | tee "$REPORT"
  exit 1
fi
VERSION_RAW="$("$GODOT_BIN" --version 2>/dev/null || true)"

step "Verify Android export preset exists"
if ! grep -q "platform=\"Android\"" "$PROJECT_DIR/export_presets.cfg" 2>/dev/null; then
  echo "ERROR: export_presets.cfg missing an Android preset." | tee "$REPORT"
  exit 1
fi

step "Verify required project files"
for f in project.godot scenes/main/main.tscn export_presets.cfg; do
  if [ ! -f "$PROJECT_DIR/$f" ]; then
    echo "ERROR: required file missing: $f" | tee "$REPORT"
    exit 1
  fi
done

step "Verify documented Godot version"
if ! echo "$VERSION_RAW" | grep -q "$PINNED_GODOT"; then
  echo "WARNING: Godot version '$VERSION_RAW' does not match pinned '$PINNED_GODOT' (continuing)." | tee "$REPORT"
else
  echo "Godot version OK: $VERSION_RAW"
fi

step "Verify approved asset files (offline)"
(cd "$PROJECT_DIR" && python3 scripts/download_assets.py --verify)
(cd "$PROJECT_DIR" && python3 tool/validate_assets.py)
(cd "$PROJECT_DIR" && python3 -m unittest discover -s tests/python)

step "Import project"
(cd "$PROJECT_DIR" && "$GODOT_BIN" --headless --path . --import >/dev/null)

step "Validate native Godot asset imports"
(cd "$PROJECT_DIR" && "$GODOT_BIN" --headless --path . --script res://tests/validate_asset_imports.gd)

step "Run automated tests"
(cd "$PROJECT_DIR" && "$GODOT_BIN" --headless --path . --script res://tests/run_tests.gd)

step "Validate resources"
(cd "$PROJECT_DIR" && python3 tool/validate_resources.py)

step "Install Android build template into project"
# Godot's Gradle Android export needs the build template at res://android/build
# (normally the Project menu -> "Install Android Build Template"). Requires the
# matching export templates (android_source.zip) to be installed first.
(cd "$PROJECT_DIR" && bash scripts/install_android_build_template.sh)

step "Export Android APK ($BUILD_TYPE)"
(cd "$PROJECT_DIR" && "$GODOT_BIN" --headless --path . "${EXPORT_ARGS[@]}" "$PRESET_NAME" "$APK")

step "Verify APK"
if [ ! -f "$APK" ]; then
  echo "ERROR: APK not produced at $APK" | tee "$REPORT"
  exit 1
fi
SIZE=$(stat -c%s "$APK" 2>/dev/null || stat -f%z "$APK" 2>/dev/null || echo 0)
if [ "${SIZE:-0}" -le 0 ]; then
  echo "ERROR: APK is empty/zero-sized." | tee "$REPORT"
  exit 1
fi

step "Write build report"
{
  echo "Last Stand: Arena — Android build report"
  echo "Godot:  $VERSION_RAW"
  echo "Type:   $BUILD_TYPE"
  echo "APK:    $APK"
  echo "Size:   $SIZE bytes"
  echo "Result: SUCCESS"
} > "$REPORT"
cat "$REPORT"
echo ""
echo "APK ready: $APK"
