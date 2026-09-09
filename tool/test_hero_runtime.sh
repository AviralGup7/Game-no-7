#!/usr/bin/env bash
# After Godot import: real Player + WeaponManager + animation/socket lifecycle.
# Use a disposable profile; never mutate the developer/player's saved progression.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-godot}"
cd "$ROOT"
mkdir -p .cache/hero-validation build
TEST_DATA="$(mktemp -d "$ROOT/.cache/hero-validation/profile.XXXXXX")"
export XDG_DATA_HOME="$TEST_DATA"
set +e
timeout 90s "$GODOT" --headless --path "$ROOT" --script res://tests/run_player_tests.gd 2>&1 | tee build/hero-runtime-tests.log
engine_status=${PIPESTATUS[0]}
set -e
# Godot can exit zero after a script error: require both the summary and clean log.
if [ "$engine_status" -ne 0 ] \
  || ! grep -Eq 'Player tests: [0-9]+ checks, 0 failed' build/hero-runtime-tests.log \
  || grep -Eq 'SCRIPT ERROR:|Parse Error:|Failed to load script|^FAIL:' build/hero-runtime-tests.log; then
  # One annotation keeps the full diagnostic available through GitHub's checks
  # API even when the external Actions log/artifact storage is unreachable.
  if [ "${GITHUB_ACTIONS:-}" = true ]; then
    python3 - <<'ANNOTATION'
from pathlib import Path
text = Path('build/hero-runtime-tests.log').read_text(errors='replace')[-50000:]
text = text.replace('%', '%25').replace('\r', '%0D').replace('\n', '%0A')
print('::error title=Hero runtime validation::' + text)
ANNOTATION
  fi
  echo 'Hero runtime validation failed; see build/hero-runtime-tests.log' >&2
  exit 1
fi
printf 'Hero runtime validation passed. Isolated profile: %s\n' "$TEST_DATA"
