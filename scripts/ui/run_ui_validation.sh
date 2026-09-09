#!/usr/bin/env bash
# UI tests write only to a disposable XDG data directory; never the player's save.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
GODOT="${GODOT:-godot}"
cd "$ROOT"
mkdir -p "$ROOT/.cache/ui-validation" "$ROOT/build"
TEST_DATA="$(mktemp -d "$ROOT/.cache/ui-validation/profile.XXXXXX")"
export XDG_DATA_HOME="$TEST_DATA"
"$GODOT" --headless --path "$ROOT" --import > build/ui-import.log 2>&1
# Run twice against the same isolated profile: first fresh, then saved ranks/settings.
for profile in fresh existing; do
  timeout 90s "$GODOT" --headless --path "$ROOT" res://tests/ui/ui_test_runner.tscn -- --isolated-ui-tests 2>&1 | tee "build/ui-tests-$profile.log"
  # Godot can return success despite script errors; treat these as failures too.
  # The gate is strict: the two pre-existing bugs this suite used to surface are
  # fixed (RunScorekeeper calls CombatLog.record(), not the nonexistent .log(),
  # and the UI player double provides a real typed ProgressionComponent instead
  # of a Dictionary), so no engine-level errors are allowed anymore.

  # 1. Every assertion must pass.
  if ! grep -Eq 'UI TESTS: [0-9]+ checks, 0 failed' "build/ui-tests-$profile.log"; then
    echo "UI validation failed: not all checks passed ($profile)." >&2
    exit 1
  fi

  # 2. No engine-level errors (Godot can exit 0 despite these).
  unexpected="$(grep -E 'SCRIPT ERROR:|Parse Error:|UI FAIL:|Failed to load script' \
    "build/ui-tests-$profile.log" || true)"
  if [ -n "$unexpected" ]; then
    echo "UI validation failed: unexpected errors ($profile):" >&2
    printf '%s\n' "$unexpected" >&2
    exit 1
  fi
done
printf 'UI validation complete. Isolated profile: %s\n' "$TEST_DATA"
