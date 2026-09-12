#!/usr/bin/env bash
# UI tests write only to a disposable Linux/macOS profile; never the player's save.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GODOT="${GODOT_BIN:-${GODOT:-godot}}"
cd "$ROOT"
mkdir -p "$ROOT/.cache/ui-validation" "$ROOT/build"
TEST_DATA="$(mktemp -d "$ROOT/.cache/ui-validation/profile.XXXXXX")"
source "$ROOT/scripts/godot_test_env.sh"
godot_test_profile "$TEST_DATA"
set +e
GODOT_BIN="$GODOT" bash "$ROOT/scripts/run_godot.sh" --path "$ROOT" --import > build/ui-import.log 2>&1
engine_status=$?
set -e
# Headless import only demotes the enumerated dummy-renderer preview pair.
python3 tool/check_godot_log.py build/ui-import.log --exit-code "$engine_status" \
  --allow-engine-noise
# Run twice against the same isolated profile: fresh, then saved ranks/settings.
for profile in fresh existing; do
  set +e
  GODOT_BIN="$GODOT" godot_test_timeout 90 bash "$ROOT/scripts/run_godot.sh" --path "$ROOT" res://tests/ui/ui_test_runner.tscn -- --isolated-ui-tests 2>&1 | tee "build/ui-tests-$profile.log"
  engine_status=${PIPESTATUS[0]}
  set -e
  # Native UI scenes tear down real viewports/materials under GLES3; demote
  # only the enumerated engine lifecycle reports, keep script errors fatal.
  python3 tool/check_godot_log.py "build/ui-tests-$profile.log" --exit-code "$engine_status" \
    --allow-engine-noise \
    --require '^UI TESTS: [1-9][0-9]* checks, 0 failed$'
done
printf 'UI validation complete. Isolated profile: %s\n' "$TEST_DATA"
