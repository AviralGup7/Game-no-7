#!/usr/bin/env bash
# Install matching export templates. Temporary files are private to this run;
# no stale /tmp extraction can satisfy a missing file in a newer download.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/godot_env.sh"
DEST="$GODOT_TEMPLATE_DIR"
URL="https://github.com/godotengine/godot-builds/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_export_templates.tpz"
REQUIRED=(android_debug.apk android_release.apk android_source.zip version.txt)

already_installed() {
  for file in "${REQUIRED[@]}"; do
    [ -s "$DEST/$file" ] || return 1
  done
  [ "$(tr -d '\r\n' < "$DEST/version.txt")" = "$VER_DIR" ]
}
if already_installed; then
  echo "Export templates already present for $VER_DIR; skipping download."
  exit 0
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/godot-templates.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
curl -fsSL --retry 3 "$URL" -o "$WORK/templates.tpz"
python3 - "$WORK/templates.tpz" "$WORK/extracted" "$DEST" "$VER_DIR" <<'PY'
from pathlib import Path, PurePosixPath
import shutil
import stat
import sys
import zipfile

source, extracted, destination, version = sys.argv[1:]
root = Path(extracted)
with zipfile.ZipFile(source) as archive:
    for entry in archive.infolist():
        path = PurePosixPath(entry.filename)
        if path.is_absolute() or '..' in path.parts or '\\' in entry.filename \
                or stat.S_ISLNK(entry.external_attr >> 16):
            raise ValueError(f'Unsafe export template member: {entry.filename}')
    archive.extractall(root)
if (root / 'templates').is_dir():
    root = root / 'templates'
for required in ('android_debug.apk', 'android_release.apk', 'android_source.zip', 'version.txt'):
    path = root / required
    if not path.is_file() or path.stat().st_size == 0:
        raise ValueError(f'Export template missing or empty: {required}')
if (root / 'version.txt').read_text().strip() != version:
    raise ValueError('Export template version does not match the requested engine')
shutil.copytree(root, destination, dirs_exist_ok=True)
PY
already_installed || { echo "ERROR: export template verification failed." >&2; exit 1; }
echo "Export templates OK for $VER_DIR."
