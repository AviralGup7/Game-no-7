#!/usr/bin/env bash
# Installs Godot's Android *build* template into the project (res://android) so that
# a Gradle-based Android export works in headless CI.
#
# Godot's Android export with gradle_build/use_gradle_build=true needs more than the
# runtime export templates in the user data dir: it also requires the Android build
# source template to be present IN THE PROJECT (normally installed from the Project
# menu -> "Install Android Build Template"). That template ships inside the export
# templates package as android_source.zip. This script extracts it into res://android
# at build time (ephemeral -- the generated files are never committed).
set -euo pipefail

GODOT_VERSION="${GODOT_VERSION:?GODOT_VERSION must be set, e.g. 4.4.1-stable}"
VER_DIR="${GODOT_VERSION/-stable/.stable}"
SRC_ZIP="${HOME}/.local/share/godot/export_templates/${VER_DIR}/android_source.zip"
PROJECT_DIR="${1:-.}"

if [ ! -f "${SRC_ZIP}" ]; then
  echo "ERROR: android_source.zip not found at ${SRC_ZIP}. Run install_export_templates.sh first." >&2
  exit 1
fi

DEST="${PROJECT_DIR}/android"
echo "Installing Android build template into ${DEST} (from ${SRC_ZIP})"

# Extract, unwrapping a single top-level wrapper folder if the zip has one, so the
# Gradle project files land directly under res://android.
rm -rf "${DEST}"
mkdir -p "${DEST}"
python3 - "${SRC_ZIP}" "${DEST}" <<'PY'
import sys, zipfile
src, dest = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(src) as z:
    names = z.namelist()
    top = {n.split('/')[0] for n in names if n.split('/')[0]}
    prefix = ''
    if len(top) == 1:
        only = next(iter(top))
        if any(n.startswith(only + '/') for n in names):
            prefix = only + '/'
    for n in names:
        rel = n[len(prefix):] if prefix and n.startswith(prefix) else n
        if not rel:
            continue
        target = f"{dest}/{rel}"
        if n.endswith('/'):
            import os
            os.makedirs(target, exist_ok=True)
            continue
        data = z.read(n)
        import os
        os.makedirs(os.path.dirname(target) or dest, exist_ok=True)
        with open(target, 'wb') as f:
            f.write(data)
print('extracted', len(names), 'entries, prefix=', prefix or '(none)')
PY

if [ ! -f "${DEST}/build.gradle" ] && [ ! -d "${DEST}/build" ] && [ ! -f "${DEST}/settings.gradle" ]; then
  echo "ERROR: Android build template did not expand as expected." >&2
  echo "Top-level entries under ${DEST}:" >&2
  ls -1 "${DEST}" | head -20 >&2
  exit 1
fi
echo "Android build template installed into ${DEST}:"
ls -1 "${DEST}" | head -20
