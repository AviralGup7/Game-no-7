"""Offline provenance and structural contracts for project-authored shooter assets."""
import hashlib
import json
from pathlib import Path
from scripts.download_assets import destination_for, verification_problem

ROOT = Path(__file__).resolve().parents[1]
RECIPE_FILES = {'tool/build_scifi_assets.py','tool/hero/geometry.py','tool/hero/rig.py','tool/scifi/requirements.txt'}
ROLES = {'player','basic','fast','heavy','ranged','dasher','splitter','exploder','warlord'}
CLIPS = {'Idle','Walking_A','Running_A','Fire','Reload','Hit_A','Death_A','Cast','Cheer',
         'Dodge_Forward','Dodge_Backward','Dodge_Left','Dodge_Right'}


def load_scifi_manifest(root=ROOT):
    report=json.loads((root/'assets/scifi/build_report.json').read_text())
    if report.get('schema_version')!=1 or report.get('recipe')!='station_shooter_v1':
        raise ValueError('Unknown shooter recipe')
    recipes=report.get('recipe_files',[])
    if len(recipes)!=len(RECIPE_FILES) or {r['path'] for r in recipes}!=RECIPE_FILES:
        raise ValueError('Incomplete shooter recipe inventory')
    for entry in recipes:
        path=root/entry['path']
        if path.is_symlink() or hashlib.sha256(path.read_bytes()).hexdigest()!=entry['sha256']:
            raise ValueError('Stale shooter recipe: '+entry['path'])
    files=report.get('files',[]);seen=set()
    for entry in files:
        path=entry.get('path','')
        destination_for(path,root)
        if not path.startswith('assets/scifi/') or path in seen:
            raise ValueError('Unsafe or duplicate shooter output')
        seen.add(path)
        problem=verification_problem(entry,root)
        if problem:raise ValueError(path+': '+problem)
    expected={f'assets/scifi/robots/{r}.glb' for r in ROLES}
    if not expected<=seen or len(files)<42:
        raise ValueError('Incomplete shooter output inventory')
    if sum(e['bytes'] for e in files)>2*1024*1024:
        raise ValueError('Shooter asset budget exceeded (2 MiB)')
    if report.get('license_notice')!='ASSET_LICENSES/station-shooter.txt' or not (root/report['license_notice']).is_file():
        raise ValueError('Missing authored-asset notice')
    return report


def check_robot(doc):
    if {a['name'] for a in doc.get('animations',[])}!=CLIPS:
        raise ValueError('Robot animation inventory mismatch')
    if doc.get('textures') or doc.get('images'):
        raise ValueError('Robot must use a shared vertex-color palette, not bitmap textures')
    bones={doc['nodes'][j]['name'] for skin in doc.get('skins',[]) for j in skin['joints']}
    if not {'hips','chest','head','handslot.l','handslot.r'}<=bones:
        raise ValueError('Robot missing firearm socket/rig contract')
    triangles=sum(doc['accessors'][p['indices']]['count']//3 for mesh in doc.get('meshes',[]) for p in mesh['primitives'])
    if not 0 < triangles <= 1500 or triangles != doc.get('extras',{}).get('triangles'):
        raise ValueError('Robot triangle budget exceeded')
    for anim in doc['animations']:
        if not anim.get('channels'):raise ValueError('Empty robot animation')
        for channel in anim['channels']:
            if channel['target']['path'] not in ('rotation','translation'):
                raise ValueError('Unexpected robot animation channel')
