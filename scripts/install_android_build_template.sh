#!/usr/bin/env bash
# Install Godot's Gradle build template without deleting customized project files.
# A matching install is reused. A different/incomplete existing install must be
# moved aside explicitly by its owner; never silently rm -rf android/build.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/godot_env.sh"
PROJECT_DIR="${1:-$ROOT}"
BUILD_DIR="${PROJECT_DIR}/android/build"
PARENT_DIR="${PROJECT_DIR}/android"
SRC_ZIP="${GODOT_TEMPLATE_DIR}/android_source.zip"

if [ -s "${BUILD_DIR}/build.gradle" ] && [ -s "${BUILD_DIR}/gradlew" ] \
  && [ -f "${PARENT_DIR}/.build_version" ] \
  && [ "$(cat "${PARENT_DIR}/.build_version")" = "$VER_DIR" ]; then
  chmod +x "${BUILD_DIR}/gradlew"
  echo "Android build template already installed for $VER_DIR; preserving project customizations."
  exit 0
fi
if [ -e "$BUILD_DIR" ]; then
  echo "ERROR: $BUILD_DIR already exists but is incomplete or from another Godot version." >&2
  echo "Preserve any customizations and move it aside before installing $VER_DIR." >&2
  exit 1
fi
if [ ! -s "$SRC_ZIP" ]; then
  echo "ERROR: android_source.zip not found at $SRC_ZIP. Run scripts/install_export_templates.sh first." >&2
  exit 1
fi

mkdir -p "$PARENT_DIR"
STAGING="$(mktemp -d "${PARENT_DIR}/.template.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
python3 - "$SRC_ZIP" "$STAGING" "$BUILD_DIR" "$VER_DIR" <<'PY'
from pathlib import Path, PurePosixPath
import os
import stat
import sys
import zipfile

source, staging, destination, version = sys.argv[1:]
root = Path(staging)
with zipfile.ZipFile(source) as archive:
    # Validate EVERY member before extraction. Even a damaged/replaced local
    # template must not escape its staging directory or create a symlink.
    for entry in archive.infolist():
        path = PurePosixPath(entry.filename)
        if path.is_absolute() or '..' in path.parts or '\\' in entry.filename \
                or stat.S_ISLNK(entry.external_attr >> 16):
            raise ValueError(f'Unsafe Android template member: {entry.filename}')
    archive.extractall(root)
for required in ('build.gradle', 'gradlew'):
    path = root / required
    if not path.is_file() or path.stat().st_size == 0:
        raise ValueError(f'Incomplete Android template: missing {required}')
(root / '.gdignore').write_text('')
for path in root.rglob('*'):
    if path.is_file() and (path.name.startswith('gradlew') or path.suffix == '.sh'):
        path.chmod(path.stat().st_mode | 0o111)
os.rename(root, destination)
marker = Path(destination).parent / '.build_version'
temporary = marker.with_name(marker.name + '.tmp')
temporary.write_text(version + '\n')
os.replace(temporary, marker)
print(f'Android build template installed: {destination} ({version})')
PY
