"""Shipping shooter asset, input and export contracts. No engine required."""
import copy
import fnmatch
import json
from pathlib import Path
import re
import unittest

from tool.scifi_assets import load_scifi_manifest, check_robot, CLIPS, ROLES
from tool.validate_assets import gltf_document
from tool.validate_hero import accessor

ROOT=Path(__file__).resolve().parents[2]

class ShooterTests(unittest.TestCase):
    def test_authored_bundle_is_verified_and_below_two_mib(self):
        report=load_scifi_manifest(ROOT)
        self.assertLess(sum(f['bytes'] for f in report['files']),2*1024*1024)
        self.assertGreaterEqual(len(report['files']),80)

    def test_every_robot_has_valid_skin_and_sparse_finite_motion(self):
        import math
        for role in ROLES:
            with self.subTest(role=role):
                doc,binary=gltf_document(ROOT/f'assets/scifi/robots/{role}.glb')
                check_robot(doc)
                joints=doc['skins'][0]['joints']
                attrs=doc['meshes'][0]['primitives'][0]['attributes']
                self.assertIn('COLOR_0',attrs)
                self.assertNotIn('TEXCOORD_0',attrs)
                for weights in accessor(doc,binary,attrs['WEIGHTS_0']):
                    self.assertAlmostEqual(sum(weights),1,places=5)
                for indices in accessor(doc,binary,attrs['JOINTS_0']):
                    self.assertTrue(all(0<=j<len(joints) for j in indices))
                for animation in doc['animations']:
                    for channel in animation['channels']:
                        self.assertIn(channel['target']['node'],joints)
                        sampler=animation['samplers'][channel['sampler']]
                        times=[v[0] for v in accessor(doc,binary,sampler['input'])]
                        self.assertTrue(all(b>a for a,b in zip(times,times[1:])))
                        self.assertLessEqual(len(times),9)
                        values=accessor(doc,binary,sampler['output'])
                        self.assertTrue(all(math.isfinite(v) for row in values for v in row))
                        if channel['target']['path']=='rotation':
                            for row in values:self.assertAlmostEqual(sum(v*v for v in row),1,places=5)

    def test_fire_reload_death_and_movement_are_not_idle_aliases(self):
        doc,binary=gltf_document(ROOT/'assets/scifi/robots/player.glb')
        for clip in ['Fire','Reload','Death_A','Walking_A','Running_A']:
            animation=next(a for a in doc['animations'] if a['name']==clip)
            changing=False
            for sampler in animation['samplers']:
                rows=accessor(doc,binary,sampler['output'])
                changing |= any(row!=rows[0] for row in rows[1:])
            self.assertTrue(changing,clip)

    def test_missing_shooter_clip_and_bitmap_regressions_fail(self):
        doc,_=gltf_document(ROOT/'assets/scifi/robots/player.glb')
        bad=copy.deepcopy(doc);bad['animations'].pop()
        with self.assertRaisesRegex(ValueError,'animation'):check_robot(bad)
        bad=copy.deepcopy(doc);bad['images']=[{'uri':'huge.png'}]
        with self.assertRaisesRegex(ValueError,'bitmap'):check_robot(bad)

    def test_live_contract_and_selected_clips_match_robot(self):
        contract=(ROOT/'scripts/visuals/hero_rig_contract.gd').read_text()
        block=contract.split('const REQUIRED_CLIPS:',1)[1].split('= [',1)[1].split(']',1)[0]
        self.assertEqual(set(re.findall(r'&"([^"]+)"',block)),CLIPS)
        animator=(ROOT/'scripts/player/player_animation.gd').read_text()
        selected=set(re.findall(r'&"([A-Z][^"]+)"',animator))
        self.assertLessEqual(selected,CLIPS)

    def test_every_enabled_gun_has_magazine_and_no_melee_resolver(self):
        configs=list((ROOT/'data/weapons').glob('*.tres'))
        self.assertEqual(len(configs),9)
        for cfg in configs:
            text=cfg.read_text()
            self.assertIn('kind = &"ranged"',text)
            self.assertIn('attack_pattern = &"volley"',text)
            self.assertIn('combo_damage_steps = PackedFloat32Array(1)',text)
            self.assertGreater(int(re.search(r'ammo_per_magazine = (\d+)',text)[1]),0)
            self.assertGreater(float(re.search(r'reload_seconds = ([\d.]+)',text)[1]),0)
            doc,_=gltf_document(ROOT/f'assets/scifi/guns/{cfg.stem}.glb')
            self.assertTrue(any(n.get('name')=='Muzzle' for n in doc['nodes']))

    def test_shipping_literals_never_reference_excluded_assets(self):
        preset=(ROOT/'export_presets.cfg').read_text()
        patterns=[p for p in re.search(r'exclude_filter="([^"]+)"',preset)[1].split(',') if p.startswith('assets/')]
        for folder in ('scripts','data','scenes','assets/materials'):
            for path in (ROOT/folder).rglob('*'):
                if path.suffix not in ('.gd','.tres','.tscn'):continue
                for ref in re.findall(r'"res://(assets/[^"\n]+)"',path.read_text()):
                    self.assertFalse(any(fnmatch.fnmatchcase(ref,p) for p in patterns),f'{path}: {ref}')
        catalog=json.loads((ROOT/'assets/catalog.json').read_text())
        for category in ['gameplay_weapons','gameplay_pickups','characters','audio_cues']:
            for entry in catalog[category].values():
                refs=entry.get('files',[entry.get('model','')])
                for ref in refs:self.assertTrue(ref.startswith('assets/scifi/'),ref)

    def test_hold_fire_has_no_repeat_buffer_or_toast(self):
        player=(ROOT/'scripts/player/player.gd').read_text()
        hold=player.split('func request_held_fire()',1)[1].split('\n\nfunc ',1)[0]
        self.assertIn('_try_attack()',hold)
        self.assertNotIn('_attack_buffer',hold)
        touch=(ROOT/'scripts/ui/touch_controls.gd').read_text()
        self.assertIn('button.fire_input_changed.connect(UiCommands.fire_input)',touch)
        self.assertNotIn('UiCommands.action(&"request_held_fire")',touch)
        physics=player.split('func _physics_process(',1)[1].split('\n\nfunc ',1)[0]
        self.assertIn('if _touch_fire_held:\n\t\t_try_attack()',physics)
        self.assertIn('button.cancel()',touch)
        action=(ROOT/'scripts/ui/touch_action_button.gd').read_text()
        self.assertIn('"attack": "FIRE"',action)

    def test_aim_is_selected_before_weapon_starts_and_3d_spread_is_used(self):
        player=(ROOT/'scripts/player/player.gd').read_text().split('func _try_attack()',1)[1].split('\n\nfunc ',1)[0]
        self.assertLess(player.index('_aim_attack()'),player.index('_combat.try_start()'))
        combat=(ROOT/'scripts/player/player_combat.gd').read_text()
        self.assertIn('_weapons.request_attack() > 0', combat)
        manager=(ROOT/'scripts/weapons/weapon_manager.gd').read_text()
        self.assertIn('RangedResolver.aimed_directions(_shot_direction',manager)
        self.assertIn('world.direct_space_state.intersect_ray(query)',manager)
        self.assertIn('CollisionLayers.OBSTRUCTORS',manager)

if __name__=='__main__':unittest.main()
