#!/usr/bin/env bash
# Reproducible Android APK build. Debug is the default; release credentials are
# supplied via Godot's environment variables or private editor export credentials.
# Never write signing secrets into a tracked export preset.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-godot}"
OUT_DIR="$PROJECT_DIR/build"
BUILD_TYPE="${BUILD_TYPE:-debug}"
PRESET_NAME="${PRESET_NAME:-Android}"
mkdir -p "$OUT_DIR"
REPORT="$OUT_DIR/BUILD_REPORT.txt"
CURRENT_STEP="initialization"
printf 'Result: IN PROGRESS\n' > "$REPORT"
report_failure() {
  local code=$?
  if [ "$code" -ne 0 ]; then
    printf 'Result: FAILED\nStep: %s\nExit: %s\n' "$CURRENT_STEP" "$code" > "$REPORT"
  fi
}
trap report_failure EXIT
step() { CURRENT_STEP="$*"; printf '\n==> %s\n' "$*"; }

step "Load pinned Godot environment"
source "$PROJECT_DIR/scripts/godot_env.sh"
source "$PROJECT_DIR/scripts/godot_test_env.sh"

case "$BUILD_TYPE" in
  debug) APK="$OUT_DIR/LastStandArena-debug.apk"; EXPORT_ARGS=(--export-debug) ;;
  release) APK="$OUT_DIR/LastStandArena.apk"; EXPORT_ARGS=(--export-release) ;;
  *) echo "ERROR: BUILD_TYPE must be debug or release." >&2; exit 1 ;;
esac

step "Verify pinned Godot engine"
if ! command -v "$GODOT_BIN" >/dev/null 2>&1; then
  echo "ERROR: Godot not found (GODOT_BIN=$GODOT_BIN)." >&2
  exit 1
fi
VERSION_RAW="$("$GODOT_BIN" --version)"
if [ "$GODOT_VERSION" != "$PINNED_GODOT" ]; then
  echo "ERROR: GODOT_VERSION must match .godot-version ($PINNED_GODOT)." >&2
  exit 1
fi
case "$VERSION_RAW" in
  "$VER_DIR"|"$VER_DIR".*) echo "Godot version OK: $VERSION_RAW" ;;
  *) echo "ERROR: Godot '$VERSION_RAW' does not match pinned '$PINNED_GODOT'." >&2; exit 1 ;;
esac

step "Verify required project files and selected Android preset"
for file in project.godot scenes/campaign/station_zero.tscn data/campaign/station_zero.json export_presets.cfg; do
  test -s "$PROJECT_DIR/$file" || { echo "ERROR: missing $file" >&2; exit 1; }
done
python3 - "$PROJECT_DIR/export_presets.cfg" "$PRESET_NAME" <<'PY'
import configparser
import re
import sys
config = configparser.ConfigParser(interpolation=None)
config.read(sys.argv[1])
valid = any(re.fullmatch(r'preset\.\d+', section)
            and config[section].get('name', '').strip('"') == sys.argv[2]
            and config[section].get('platform') == '"Android"'
            for section in config.sections())
if not valid:
    raise SystemExit('ERROR: selected preset is not an Android export preset.')
PY

# Backwards-compatible aliases for the previously documented signing variables.
# Godot Android requires the key and keystore to share one password.
if [ "$BUILD_TYPE" = release ]; then
  if [ -n "${KEY_PASSWORD:-}" ] && [ -n "${KEYSTORE_PASSWORD:-}" ] \
    && [ "$KEY_PASSWORD" != "$KEYSTORE_PASSWORD" ]; then
    echo "ERROR: Godot requires matching key and keystore passwords." >&2
    exit 1
  fi
  if [ -n "${KEYSTORE_PATH:-}" ]; then export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="${GODOT_ANDROID_KEYSTORE_RELEASE_PATH:-$KEYSTORE_PATH}"; fi
  if [ -n "${KEY_ALIAS:-}" ]; then export GODOT_ANDROID_KEYSTORE_RELEASE_USER="${GODOT_ANDROID_KEYSTORE_RELEASE_USER:-$KEY_ALIAS}"; fi
  if [ -n "${KEYSTORE_PASSWORD:-${KEY_PASSWORD:-}}" ]; then
    export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="${GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD:-${KEYSTORE_PASSWORD:-$KEY_PASSWORD}}"
  fi
fi

# Godot may exit zero after parse/runtime errors. Never accept that as success.
run_godot() {
  local log="$OUT_DIR/$1" summary="$2" code
  shift 2
  set +e
  (cd "$PROJECT_DIR" && GODOT_BIN="$GODOT_BIN" bash scripts/run_godot.sh --path . "$@") > "$log" 2>&1
  code=$?
  set -e
  tail -40 "$log"
  local checks=("$log" --exit-code "$code")
  if [ "$log" = "$OUT_DIR/godot-unit.log" ]; then checks+=(--allow-test-errors); fi
  # Every step only demotes the enumerated engine lifecycle reports: the
  # dummy-renderer preview pair on headless import, GLES3 teardown/shutdown
  # pairs on the native scene-running and export steps.
  checks+=(--allow-engine-noise)
  if [ -n "$summary" ]; then checks+=(--require "$summary"); fi
  python3 "$PROJECT_DIR/tool/check_godot_log.py" "${checks[@]}"
}

step "Run offline validation"
(cd "$PROJECT_DIR" && python3 scripts/download_assets.py --verify)
for check in validate_campaign validate_assets validate_resources check_typed_arch validate_guards check_engine_api check_scene_paths check_string_formats check_signals; do
  (cd "$PROJECT_DIR" && python3 "tool/$check.py")
done
(cd "$PROJECT_DIR" && python3 -m unittest discover -s tests/python)

step "Import project"
run_godot godot-import.log '' --import

# Tests must not consume or overwrite the developer/player's progression.
mkdir -p "$PROJECT_DIR/.cache/build-validation"
TEST_DATA="$(mktemp -d "$PROJECT_DIR/.cache/build-validation/profile.XXXXXX")"
run_isolated_godot() (
  godot_test_profile "$TEST_DATA"
  run_godot "$@"
)
step "Validate native Godot asset imports"
run_isolated_godot godot-assets.log '^Asset imports: [1-9][0-9]* resources, 0 failures$' --script res://tests/validate_asset_imports.gd
step "Run host Godot unit tests"
run_isolated_godot godot-unit.log '^GDScript tests: [1-9][0-9]* total, 0 failed$' --script res://tests/run_tests.gd
step "Validate player runtime and UI lifecycle"
(cd "$PROJECT_DIR" && GODOT="$GODOT_BIN" bash tool/test_hero_runtime.sh)
(cd "$PROJECT_DIR" && GODOT="$GODOT_BIN" bash scripts/ui/run_ui_validation.sh)

step "Validate the shipping campaign flow"
(cd "$PROJECT_DIR" && GODOT_BIN="$GODOT_BIN" bash scripts/run_campaign_validation.sh)

step "Install matching export and Android build templates"
(cd "$PROJECT_DIR" && bash scripts/install_export_templates.sh)
(cd "$PROJECT_DIR" && bash scripts/install_android_build_template.sh)

step "Export Android APK ($BUILD_TYPE)"
# An earlier successful build must never satisfy today's output check.
rm -f "$APK"
run_godot export.log '' "${EXPORT_ARGS[@]}" "$PRESET_NAME" "$APK"
step "Verify Android APK identity, ABI, permissions and signature"
python3 "$PROJECT_DIR/tool/check_android_apk.py" "$APK" \
  --presets "$PROJECT_DIR/export_presets.cfg" --preset "$PRESET_NAME" \
  --build-type "$BUILD_TYPE" --report "$OUT_DIR/apk-validation.json"
SIZE="$(wc -c < "$APK" | tr -d ' ')"
{
  echo "Last Stand: Station Zero — Android build report"
  echo "Godot: $VERSION_RAW"
  echo "Type: $BUILD_TYPE"
  echo "APK: $APK"
  echo "Size: $SIZE bytes"
  echo "Result: SUCCESS"
} > "$REPORT"
cat "$REPORT"
