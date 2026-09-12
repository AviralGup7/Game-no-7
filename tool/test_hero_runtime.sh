#!/usr/bin/env bash
# After Godot import: real Player + WeaponManager + animation/socket lifecycle.
# Use a disposable profile; never mutate the developer/player's saved progression.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT_BIN:-${GODOT:-godot}}"
cd "$ROOT"
mkdir -p .cache/hero-validation build
TEST_DATA="$(mktemp -d "$ROOT/.cache/hero-validation/profile.XXXXXX")"
source "$ROOT/scripts/godot_test_env.sh"
godot_test_profile "$TEST_DATA"
set +e
GODOT_BIN="$GODOT" godot_test_timeout 90 bash "$ROOT/scripts/run_godot.sh" --path "$ROOT" --script res://tests/run_player_tests.gd 2>&1 | tee build/hero-runtime-tests.log
engine_status=${PIPESTATUS[0]}
set -e
# Require a real completion summary AND a clean error channel.
python3 tool/check_godot_log.py build/hero-runtime-tests.log --exit-code "$engine_status" \
  --require '^Player tests: [1-9][0-9]* checks, 0 failed$'
printf 'Hero runtime validation passed. Isolated profile: %s\n' "$TEST_DATA"
