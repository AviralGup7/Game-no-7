#!/usr/bin/env bash
# Headless campaign runtime suite with a disposable profile and strict engine
# logs. Instantiates the shipping Station Zero world on the dummy renderer and
# drives all 13 missions, the save-write failure drill, the 20
# pause/map/back/checkpoint cycles and the defeat-persistence retry. Logic-only
# (no GL context, no sound): this is the fast entry documented in
# docs/BUILD.md; the same suite is also embedded in res://tests/run_tests.gd.
# Never load/overwrite the developer's or player's real save.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT_BIN:-${GODOT:-godot}}"
cd "$ROOT"
mkdir -p "$ROOT/.cache/campaign-runtime" "$ROOT/build"
if ! command -v "$GODOT" >/dev/null 2>&1; then
  echo 'NOT TESTED: Campaign runtime suite requires the pinned Godot engine.' >&2
  exit 2
fi
TEST_DATA="$(mktemp -d "$ROOT/.cache/campaign-runtime/profile.XXXXXX")"
source "$ROOT/scripts/godot_test_env.sh"
godot_test_profile "$TEST_DATA"
export STATION_ZERO_TEST_PROFILE=1
set +e
GODOT_BIN="$GODOT" godot_test_timeout 180 bash "$ROOT/scripts/run_godot.sh" --path "$ROOT" --import \
  > build/campaign-runtime-import.log 2>&1
code=$?
set -e
# Headless import only demotes the enumerated dummy-renderer preview pair.
python3 tool/check_godot_log.py build/campaign-runtime-import.log --exit-code "$code" \
  --allow-engine-noise
set +e
# 240 s logic-only budget: one world build, 32+ authored defeats, all 13
# missions, 21 pause/map/back/checkpoint cycles and two checkpoint retries.
# Host-harness budget, not an Android frame-time claim.
GODOT_BIN="$GODOT" godot_test_timeout 240 "$GODOT" --headless --path "$ROOT" \
  --script res://tests/run_campaign_runtime.gd > build/campaign-runtime-tests.log 2>&1
code=$?
set -e
tail -60 build/campaign-runtime-tests.log
python3 tool/check_godot_log.py build/campaign-runtime-tests.log --exit-code "$code" \
  --allow-engine-noise \
  --require '^CAMPAIGN RUNTIME: [1-9][0-9]* checks, 0 failed$'
printf 'Campaign runtime suite complete. Isolated profile: %s\n' "$TEST_DATA"
