#!/usr/bin/env bash
# Android-only install/launch smoke check. The APK's actual package is verified
# against package/unique_name in export_presets.cfg before any device install.
# Requires platform-tools, SDK build-tools and Java; absence is NOT a pass.
# Use --checklist for a docs-only invocation, ANDROID_SERIAL for multiple devices.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec python3 "$ROOT/tool/android_device_qa.py" "$@"
