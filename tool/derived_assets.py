"""Offline provenance for locally authored / retargeted assets.

Kept separate from the immutable upstream download manifest: generated files have
no invented upstream URL or blob hash, and the downloader must not overwrite them.
Only explicitly listed, checked derivatives join the approved source inventory.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path, PurePosixPath
import re

from scripts.download_assets import destination_for, load_manifest, verification_problem

ROOT = Path(__file__).resolve().parents[1]
HERO_REPORT = 'assets/characters/warden/build_report.json'
HERO_OUTPUTS = {
    'assets/characters/warden/' + name for name in
    ('ArenaWarden.glb', 'WardenGladius.glb', 'Warden_base_color.png', 'Warden_normal.png', 'Warden_ORM.png')
}
RECIPE_FILES = {'tool/build_hero.py', 'tool/hero/geometry.py', 'tool/hero/rig.py', 'tool/hero/requirements.txt'}
DONOR = 'assets/characters/adventurers/Knight.glb'


def _require(value, message):
    if not value:
        raise ValueError('Derived assets: ' + message)


def _verify_input(entry, root):
    relative = entry.get('path', '')
    path = PurePosixPath(relative)
    _require(not path.is_absolute() and '..' not in path.parts and str(path) == relative,
             'unsafe recipe/input path')
    actual = root / relative
    _require(actual.resolve().is_relative_to(root.resolve()) and not actual.is_symlink(),
             'recipe/input escapes repository')
    _require(re.fullmatch('[0-9a-f]{64}', entry.get('sha256', '')), 'missing input SHA-256')
    _require(actual.is_file(), 'missing input: ' + relative)
    _require(hashlib.sha256(actual.read_bytes()).hexdigest() == entry['sha256'],
             'stale recipe/input: ' + relative + ' (rebuild the hero)')


def load_derived_manifest(root: Path = ROOT) -> dict:
    report = json.loads((root / HERO_REPORT).read_text())
    _require(isinstance(report, dict) and report.get('schema_version') == 1, 'invalid report schema')
    _require(report.get('recipe') == 'arena_warden_v1', 'unknown recipe')
    _require(report.get('generator') == 'tool/build_hero.py', 'unreviewed generator')
    files = report.get('files', [])
    _require(isinstance(files, list) and len(files) == len(HERO_OUTPUTS), 'incomplete/duplicate output inventory')
    _require({f.get('path') for f in files} == HERO_OUTPUTS, 'unreviewed derivative output path')
    for entry in files:
        destination_for(entry['path'], root)  # canonical, local, symlink-safe
        _require(type(entry.get('bytes')) is int and 0 < entry['bytes'] <= 8 * 1024 * 1024,
                 'invalid derivative length')
        _require(re.fullmatch('[0-9a-f]{64}', entry.get('sha256', '')), 'missing output SHA-256')
        problem = verification_problem(entry, root)
        _require(not problem, entry['path'] + ': ' + problem)
    inputs = report.get('inputs', [])
    _require(len(inputs) == 1 and inputs[0].get('path') == DONOR, 'unreviewed motion donor')
    locked = load_manifest(root / 'assets/manifest.json', root)
    donor = next(entry for entry in locked['files'] if entry['path'] == DONOR)
    _require(inputs[0].get('sha256') == donor['sha256'] and inputs[0].get('license') == 'CC0-1.0',
             'motion donor differs from the reviewed licence/hash lock')
    _verify_input(inputs[0], root)
    recipes = report.get('recipe_files', [])
    _require(len(recipes) == len(RECIPE_FILES) and {r.get('path') for r in recipes} == RECIPE_FILES,
             'incomplete/unreviewed recipe inventory')
    for entry in recipes:
        _verify_input(entry, root)
    notice = 'ASSET_LICENSES/arena-warden.md'
    _require(report.get('license_notice') == notice and (root / notice).is_file(),
             'missing derivative licence/provenance notice')
    return report
