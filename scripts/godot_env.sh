#!/usr/bin/env bash
# Shared by the local build and template installers; source, do not execute.
# No secrets are read or written here. CI's version must agree with .godot-version.
PINNED_GODOT="$(tr -d '\r\n' < "$(dirname "${BASH_SOURCE[0]}")/../.godot-version")"
export GODOT_VERSION="${GODOT_VERSION:-$PINNED_GODOT}"
if [[ ! "$GODOT_VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?-stable$ ]]; then
  echo "ERROR: expected a stable Godot version, got '$GODOT_VERSION'." >&2
  return 1
fi
VER_DIR="${GODOT_VERSION/-stable/.stable}"

# Match Godot's platform data directory, including an isolated XDG profile.
# GODOT_TEMPLATE_DIR overrides the complete per-version directory when needed.
if [ "$(uname -s)" = Darwin ]; then
  GODOT_DATA_DIR="${HOME}/Library/Application Support/Godot"
else
  GODOT_DATA_DIR="${XDG_DATA_HOME:-${HOME}/.local/share}/godot"
fi
GODOT_TEMPLATE_DIR="${GODOT_TEMPLATE_DIR:-${GODOT_DATA_DIR}/export_templates/${VER_DIR}}"
