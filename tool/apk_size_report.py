#!/usr/bin/env python3
"""Report APK ZIP compressed/uncompressed sizes without extracting or rewriting it.
Usage: python3 tool/apk_size_report.py build/LastStandArena-debug.apk
Godot PCK contents, if present, are reported as a container, not mislabelled assets.
"""
import argparse
from collections import defaultdict
import json
from pathlib import Path
import zipfile


def report(path):
    groups = defaultdict(lambda: {'compressed_bytes': 0, 'uncompressed_bytes': 0, 'files': 0})
    with zipfile.ZipFile(path) as archive:
        entries = [e for e in archive.infolist() if not e.is_dir()]
        for entry in entries:
            name = entry.filename
            group = ('native_libraries' if name.startswith('lib/') else
                     'godot_pack' if name.endswith('.pck') else
                     'assets' if name.startswith('assets/') else 'android_other')
            row = groups[group]
            row['compressed_bytes'] += entry.compress_size
            row['uncompressed_bytes'] += entry.file_size
            row['files'] += 1
        largest = [{'path': e.filename, 'compressed_bytes': e.compress_size,
                    'uncompressed_bytes': e.file_size}
                   for e in sorted(entries, key=lambda e: e.compress_size, reverse=True)[:20]]
    return {'apk': str(path), 'apk_bytes': Path(path).stat().st_size,
            'groups': dict(groups), 'largest_entries': largest,
            'note': 'ZIP sizes are not installed size or RAM. Compare same export type/engine/ABI.'}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk', type=Path)
    args = parser.parse_args()
    print(json.dumps(report(args.apk), indent=2))
