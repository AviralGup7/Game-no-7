#!/usr/bin/env bash
# Sideload + smoke-check Last Stand: Arena on a USB-connected Android device.
# Does not require a Godot editor. Safe to run with no device attached: prints
# the checklist and exits 0 so CI can keep the script as documentation.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APK="${APK:-$ROOT/build/LastStandArena-debug.apk}"
# The launch package is read from the export preset, not hardcoded: a stale
# literal here (it once said com.laststand.arena while the preset shipped
# com.laststandarena.game) makes the smoke-launch target a package that was
# never installed. PKG env still overrides for preset experiments.
PRESET_PKG="$(grep -o 'package/unique_name="[^"]*"' "$ROOT/export_presets.cfg" 2>/dev/null | head -n 1 | cut -d'"' -f2)"
PKG="${PKG:-${PRESET_PKG:-com.laststandarena.game}}"

echo "== Last Stand: Arena device QA =="
echo "APK: $APK"

if ! command -v adb >/dev/null 2>&1; then
  echo "adb not on PATH. Install Android platform-tools, then:"
  echo "  adb install -r \"$APK\""
  echo "See docs/DEVICE_QA.md for the play checklist."
  exit 0
fi

DEVICES="$(adb devices | awk 'NR>1 && $2=="device" {print $1}')"
if [ -z "$DEVICES" ]; then
  echo "No USB device in 'device' state. Connect a phone, enable USB debugging."
  echo "Checklist (once installed): docs/DEVICE_QA.md"
  exit 0
fi

if [ ! -f "$APK" ]; then
  echo "APK missing. Build with: bash scripts/build_android.sh"
  exit 1
fi

echo "Installing on: $DEVICES"
adb install -r "$APK"
echo "Launch:"
adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 || true
echo
echo "Play the checklist in docs/DEVICE_QA.md (touch, pause→menu→restart, thermals)."
