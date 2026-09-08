#!/usr/bin/env bash
# Installs the official Godot export templates into the directory Godot reads at
# export time, and FAILS LOUDLY if the download/extract/copy did not actually place
# the files (previously the step exited 0 even when no templates landed, which made
# `godot --export-*` fail later with "Android build template not installed").
#
# The folder must use Godot's *version string* (a dot before "stable"), e.g.
# 4.4.1.stable, NOT the release-tag name 4.4.1-stable.
set -euo pipefail

GODOT_VERSION="${GODOT_VERSION:?GODOT_VERSION must be set, e.g. 4.4.1-stable}"
VER_DIR="${GODOT_VERSION/-stable/.stable}"
URL="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_export_templates.tpz"
DEST="${HOME}/.local/share/godot/export_templates/${VER_DIR}"

REQUIRED=(android_debug.apk android_release.apk android_source.zip version.txt)

already_installed() {
  for f in "${REQUIRED[@]}"; do
    [ -f "${DEST}/${f}" ] || return 1
  done
  return 0
}

if already_installed; then
  echo "Export templates already present for ${VER_DIR}; skipping re-download."
  ls -1 "${DEST}"
  exit 0
fi

echo "Installing export templates ${VER_DIR} -> ${DEST}"
mkdir -p /tmp/tpl-extract "${DEST}"

# -f -> fail on HTTP errors instead of silently saving a 404 page.
curl -fsSL --retry 3 "${URL}" -o /tmp/templates.tpz
test -s /tmp/templates.tpz

# Extract with python's zipfile (always present on the runner), so a missing
# `unzip` cannot silently skip extraction.
python3 - <<'PY'
import zipfile
with zipfile.ZipFile('/tmp/templates.tpz') as z:
    z.extractall('/tmp/tpl-extract')
PY

# The tpz wraps everything in a top-level `templates/` folder; support both layouts.
SRC="/tmp/tpl-extract/templates"
if [ ! -d "${SRC}" ]; then
  SRC="/tmp/tpl-extract"
fi
cp -R "${SRC}/." "${DEST}/"

echo "Template dir contents:"
ls -1 "${DEST}"

# Godot's Android exporter requires these build templates to exist under <version>/.
for f in "${REQUIRED[@]}"; do
  if [ ! -f "${DEST}/${f}" ]; then
    echo "ERROR: expected export template missing: ${DEST}/${f}" >&2
    exit 1
  fi
done
echo "Export templates OK for ${VER_DIR}."
