"""Strict offline provenance for project-authored station outputs."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUTS = {'assets/environment/space_station/panel.png',
           'assets/environment/space_station/support.tscn'}

def load_station_manifest(root=ROOT):
    report = json.loads((root / 'assets/environment/space_station/build_report.json').read_text())
    if report.get('schema_version') != 1 or report.get('recipe') != 'station_environment_v1':
        raise ValueError('Invalid station recipe')
    recipe = root / 'tool/build_scifi_environment.py'
    if hashlib.sha256(recipe.read_bytes()).hexdigest() != report.get('recipe_sha256'):
        raise ValueError('Stale station recipe: rebuild environment')
    files = report.get('files', [])
    if len(files) != len(OUTPUTS) or {f['path'] for f in files} != OUTPUTS:
        raise ValueError('Incomplete station output inventory')
    for entry in files:
        path = root / entry['path']
        if path.is_symlink() or not path.resolve().is_relative_to(root.resolve()):
            raise ValueError('Unsafe station output')
        data = path.read_bytes()
        if len(data) != entry['bytes'] or hashlib.sha256(data).hexdigest() != entry['sha256']:
            raise ValueError('Changed station output: ' + entry['path'])
    return report
