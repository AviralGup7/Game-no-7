#!/usr/bin/env bash
# Installs Godot's Android *build* template into the project so a Gradle-based Android
# export works in headless CI.
#
# Godot's Android export with gradle_build/use_gradle_build=true needs the Android build
# source template present IN THE PROJECT (normally Project menu -> "Install Android
# Build Template"). It lives in the export templates package as android_source.zip.
#
# This mirrors exactly what Godot's own installer does (see
# EditorExportTemplateManager::install_android_template_from_file):
#   - unzip android_source.zip into res://android/build
#   - add an empty .gdignore in res://android/build
#   - write the template identifier (VERSION_FULL_CONFIG, e.g. "4.4.1.stable")
#     into res://android/.build_version
# Godot validates export by checking for res://android/build/build.gradle. The generated
# files are build-time only and never committed.
set -euo pipefail

GODOT_VERSION="${GODOT_VERSION:?GODOT_VERSION must be set, e.g. 4.4.1-stable}"
VER_DIR="${GODOT_VERSION/-stable/.stable}"
SRC_ZIP="${HOME}/.local/share/godot/export_templates/${VER_DIR}/android_source.zip"
PROJECT_DIR="${1:-.}"

if [ ! -f "${SRC_ZIP}" ]; then
  echo "ERROR: android_source.zip not found at ${SRC_ZIP}. Run install_export_templates.sh first." >&2
  exit 1
fi

# Identifier stored in .build_version (VERSION_FULL_CONFIG for the official non-mono build).
BUILD_VERSION_ID="${VER_DIR}"

BUILD_DIR="${PROJECT_DIR}/android/build"
PARENT_DIR="${PROJECT_DIR}/android"
echo "Installing Android build template into ${BUILD_DIR} (from ${SRC_ZIP})"

rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

python3 - "${SRC_ZIP}" "${BUILD_DIR}" <<'PY'
import sys, zipfile, os
src, build = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(src) as z:
    for n in z.namelist():
        if n.endswith('/'):
            os.makedirs(os.path.join(build, n), exist_ok=True)
            continue
        data = z.read(n)
        target = os.path.join(build, n)
        os.makedirs(os.path.dirname(target) or build, exist_ok=True)
        with open(target, 'wb') as f:
            f.write(data)
print('extracted', len(z.namelist()), 'entries into', build)
PY

# Empty .gdignore so Godot never scans the gradle build as game content.
: > "${BUILD_DIR}/.gdignore"
# Version marker so the export version check passes (default template identifier).
echo "${BUILD_VERSION_ID}" > "${PARENT_DIR}/.build_version"

# Python's zipfile does not restore Unix executable bits, so make the Gradle wrapper
# (and any other launchers) executable -- Godot's own installer preserves these from
# the zip, but our extraction must restore them explicitly.
chmod +x "${BUILD_DIR}/gradlew" 2>/dev/null || true
find "${BUILD_DIR}" -type f \( -name 'gradlew*' -o -name '*.sh' \) -exec chmod +x {} + 2>/dev/null || true

if [ ! -f "${BUILD_DIR}/build.gradle" ]; then
  echo "ERROR: build.gradle not found after extraction; template layout unexpected." >&2
  echo "Contents of ${BUILD_DIR}:" >&2
  ls -1 "${BUILD_DIR}" | head -20 >&2
  exit 1
fi
echo "Android build template installed."
echo "- build dir:      ${BUILD_DIR} (build.gradle present)"
echo "- .build_version: ${PARENT_DIR}/.build_version = $(cat "${PARENT_DIR}/.build_version")"
