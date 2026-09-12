#!/usr/bin/env bash
# Native campaign integration with a disposable profile and strict engine logs.
# Never load/overwrite the developer's or player's real save.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT_BIN:-${GODOT:-godot}}"
cd "$ROOT"
mkdir -p "$ROOT/.cache/campaign-validation" "$ROOT/build"
if ! command -v "$GODOT" >/dev/null 2>&1; then
  echo 'NOT TESTED: Native campaign validation requires the pinned Godot engine.' >&2
  exit 2
fi
TEST_DATA="$(mktemp -d "$ROOT/.cache/campaign-validation/profile.XXXXXX")"
source "$ROOT/scripts/godot_test_env.sh"
godot_test_profile "$TEST_DATA"
export STATION_ZERO_TEST_PROFILE=1
set +e
GODOT_BIN="$GODOT" godot_test_timeout 180 bash "$ROOT/scripts/run_godot.sh" --path "$ROOT" --import \
  > build/campaign-import.log 2>&1
code=$?
set -e
python3 tool/check_godot_log.py build/campaign-import.log --exit-code "$code"
set +e
GODOT_BIN="$GODOT" godot_test_timeout 180 bash "$ROOT/scripts/run_godot.sh" --path "$ROOT" \
  --script res://tests/verify_campaign.gd 2>&1 | tee build/campaign-tests.log
code=${PIPESTATUS[0]}
set -e
# Campaign scenes run native under GLES3; demote only the enumerated engine
# lifecycle reports (scene teardown / process exit), script errors stay fatal.
python3 tool/check_godot_log.py build/campaign-tests.log --exit-code "$code" \
  --allow-engine-noise \
  --require '^CAMPAIGN TESTS: [1-9][0-9]* checks, 0 failed$'
printf 'Native campaign validation complete. Isolated profile: %s\n' "$TEST_DATA"
