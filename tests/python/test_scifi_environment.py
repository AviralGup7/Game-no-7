"""Station size/provenance/export regression gates, independent of Godot."""
import fnmatch
import json
from pathlib import Path
import re
import tempfile
import unittest
import zipfile

from tool.apk_size_report import report
from tool.station_assets import load_station_manifest

ROOT = Path(__file__).resolve().parents[2]

class StationTests(unittest.TestCase):
    def test_generated_outputs_are_verified(self):
        result = load_station_manifest(ROOT)
        self.assertEqual(len(result['files']), 2)
        self.assertLess(sum(f['bytes'] for f in result['files']), 4096)

    def test_selected_download_budget_and_licence(self):
        manifest = json.loads((ROOT / 'assets/manifest.json').read_text())
        files = [f for f in manifest['files'] if f['pack'] == 'kenney-space-station']
        self.assertGreater(len(files), 5)
        self.assertLess(sum(f['bytes'] for f in files), 200 * 1024)
        self.assertEqual(manifest['sources']['kenney-space-station']['license'], 'CC0-1.0')

    def test_excluded_textures_have_no_live_literal_references(self):
        preset = (ROOT / 'export_presets.cfg').read_text()
        patterns = [p for p in re.search(r'^exclude_filter="([^"]+)"', preset, re.M)[1].split(',')
                    if p.startswith('assets/textures/')]
        for folder in ('scripts', 'scenes', 'data', 'assets/materials'):
            for path in (ROOT / folder).rglob('*'):
                if path.suffix not in ('.gd', '.tscn', '.tres'):
                    continue
                for ref in re.findall(r'res://([^"\s]+)', path.read_text()):
                    self.assertFalse(any(fnmatch.fnmatchcase(ref, p) for p in patterns),
                                     f'{path}: live reference to excluded {ref}')

    def test_native_and_pack_sizes_are_separate(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'sample.apk'
            with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as archive:
                archive.writestr('lib/arm64-v8a/libgodot_android.so', b'a' * 1024)
                archive.writestr('assets/game.pck', b'b' * 2048)
            result = report(path)
            self.assertEqual(result['groups']['native_libraries']['uncompressed_bytes'], 1024)
            self.assertEqual(result['groups']['godot_pack']['uncompressed_bytes'], 2048)
            self.assertGreater(result['apk_bytes'], 0)

if __name__ == '__main__':
    unittest.main()
