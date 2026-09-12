#!/usr/bin/env bash
# Source in a test-only subshell. Godot uses XDG on Linux but HOME/Library on
# macOS; overriding XDG alone can destroy a Mac developer's real progression.
godot_test_profile() {
  local profile="$1"
  case "$(uname -s)" in
    Linux|Darwin) ;;
    *) echo 'ERROR: Safe test-profile isolation requires Linux/WSL or macOS.' >&2; return 1 ;;
  esac
  mkdir -p "$profile"
  profile="$(cd "$profile" && pwd)"
  export HOME="$profile/home"
  export XDG_DATA_HOME="$profile/data"
  export XDG_CONFIG_HOME="$profile/config"
  export XDG_CACHE_HOME="$profile/cache"
  mkdir -p "$HOME" "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"
}

# Python is already a build dependency; unlike GNU timeout it is available in
# the documented macOS setup too. Child output/exit status remain unchanged.
godot_test_timeout() {
  python3 - "$@" <<'PY'
import os
import signal
import subprocess
import sys
try:
    process = subprocess.Popen(sys.argv[2:], start_new_session=True, stdin=subprocess.DEVNULL)
except OSError as error:
    print(f'ERROR: Cannot start Godot test: {error}', file=sys.stderr)
    raise SystemExit(127)
try:
    raise SystemExit(process.wait(timeout=float(sys.argv[1])))
except subprocess.TimeoutExpired:
    # Includes the virtual display and any child engine processes; never leave
    # a hung test/preview consuming resources after the wrapper has returned.
    try:
        os.killpg(process.pid, signal.SIGTERM)
        process.wait(timeout=2)
    except ProcessLookupError:
        pass
    except subprocess.TimeoutExpired:
        pass
    # The immediate parent may exit while a child ignores SIGTERM.
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    process.wait()
    print('ERROR: Godot test timed out', file=sys.stderr)
    raise SystemExit(124)

PY
}
