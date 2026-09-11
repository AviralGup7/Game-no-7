#!/usr/bin/env python3
"""Deterministic project-authored robot rigs, firearms, pickups, FX and electronic audio.
No downloaded geometry or motion. Run with optional authoring dependencies:
  .venv/bin/pip install -r tool/hero/requirements.txt soundfile
  .venv/bin/python tool/build_scifi_assets.py
All motion is cosmetic; no animation method tracks or runtime generation.
"""
from pathlib import Path
import hashlib
import json
import math
import sys
import struct
import wave

import numpy as np
from PIL import Image, ImageDraw
from scipy.spatial.transform import Rotation
import soundfile as sf

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tool'))
from hero.geometry import Geometry
from hero.rig import Writer, worlds
OUT = ROOT / 'assets/scifi'
CLIPS = {'Idle': 1.2, 'Walking_A': 1.0, 'Running_A': .7, 'Fire': .24,
         'Reload': 1.15, 'Hit_A': .3, 'Death_A': .85, 'Cast': .6, 'Cheer': 1.0,
         'Dodge_Forward': .45, 'Dodge_Backward': .45, 'Dodge_Left': .45, 'Dodge_Right': .45}
ROLES = {'player': (.12,.62,1), 'basic': (.85,.22,.12), 'fast': (1,.5,.08),
         'heavy': (.65,.12,.18), 'ranged': (.6,.3,1), 'dasher': (1,.75,.1),
         'splitter': (.35,.8,.25), 'exploder': (1,.25,.04), 'warlord': (.6,.1,.4)}
GUNS = ['gladius','sentinel_spear','stormhammer','sunbow','twinfangs','warreaxe','ember_scepter','moonlance','venom_chain']
OUTPUTS = []


def write(name, data):
    path = OUT / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    OUTPUTS.append(path)


def box(g, name, center, size, zone, bone='root'):
    # Separate face vertices preserve hard machined edges.
    corners = np.array([[-1,-1,-1],[1,-1,-1],[1,1,-1],[-1,1,-1],
                        [-1,-1,1],[1,-1,1],[1,1,1],[-1,1,1]], dtype=float)
    corners = corners * np.array(size) / 2 + center
    faces = [(0,3,2,1),(4,5,6,7),(0,4,7,3),(1,2,6,5),(0,1,5,4),(3,7,6,2)]
    vertices=[]; triangles=[]
    for f in faces:
        k=len(vertices); vertices.extend(corners[list(f)])
        triangles.extend([(k,k+1,k+2),(k,k+2,k+3)])
    g.add(name, vertices, [[0,0],[1,0],[1,1],[0,1]]*6, triangles, zone, bone)


def make_rig():
    nodes=[]; index={}
    def add(name, position, parent=None):
        index[name]=len(nodes)
        nodes.append({'name':name, 'translation':list(position), 'rotation':[0,0,0,1]})
        if parent is not None:
            nodes[index[parent]].setdefault('children',[]).append(index[name])
    add('root',(0,0,0)); add('hips',(0,.94,0),'root')
    add('chest',(0,.34,0),'hips'); add('head',(0,.35,0),'chest')
    for side, sign in [('l',1),('r',-1)]:
        add('upperarm.'+side,(sign*.27,.17,0),'chest')
        add('lowerarm.'+side,(0,-.24,0),'upperarm.'+side)
        add('hand.'+side,(0,-.24,0),'lowerarm.'+side)
        add('handslot.'+side,(0,-.04,0),'hand.'+side)
        add('upperleg.'+side,(sign*.13,-.02,0),'hips')
        add('lowerleg.'+side,(0,-.4,0),'upperleg.'+side)
        add('foot.'+side,(0,-.39,0),'lowerleg.'+side)
    return nodes,index


def mesh(writer, g, accent, skin=False):
    arrays=g.arrays()
    palette=np.array([[.5,.58,.68],accent,[.035,.055,.085],[.2,.9,1],
                      [.14,.18,.23],[.75,.8,.85],accent,[.03,.05,.07]],dtype='<f4')
    uv=arrays['TEXCOORD_0']
    zones=np.minimum((uv[:,1]*2).astype(int),1)*4+np.minimum((uv[:,0]*4).astype(int),3)
    attrs={k:writer.add(arrays[k],kind,34962,k=='POSITION') for k,kind in
           [('POSITION','VEC3'),('NORMAL','VEC3')]}
    attrs['COLOR_0']=writer.add(palette[zones], 'VEC3', 34962)
    if skin:
        attrs['JOINTS_0']=writer.add(arrays['JOINTS_0'],'VEC4',34962)
        attrs['WEIGHTS_0']=writer.add(arrays['WEIGHTS_0'],'VEC4',34962)
    writer.doc['materials']=[{'name':'Shared alloy with vertex palette',
        'pbrMetallicRoughness':{'baseColorFactor':[1,1,1,1],'metallicFactor':.4,'roughnessFactor':.65}}]
    writer.doc['meshes']=[{'name':'Station hardware','primitives':[{'attributes':attrs,
        'indices':writer.add(arrays['indices'],'SCALAR',34963),'material':0}]}]
    return len(arrays['indices'])//3


def robot(role, accent):
    nodes,index=make_rig(); g=Geometry(index)
    wide=1.35 if role in ('heavy','warlord') else .8 if role in ('fast','dasher') else 1.0
    box(g,'pelvis',(0,.94,0),(.34,.18,.24),4,'hips')
    box(g,'sealed chest',(0,1.3,0),(.42*wide,.45,.29),0,'chest')
    box(g,'chest insignia',(0,1.32,.155),(.22*wide,.17,.025),1,'chest')
    box(g,'power cell',(0,1.35,-.19),(.24,.28,.13),4,'chest')
    box(g,'helmet',(0,1.69,0),(.3,.28,.26),0,'head')
    box(g,'visor',(0,1.72,.14),(.255,.075,.035),3 if role=='player' else 1,'head')
    box(g,'antenna',(.12,1.89,0),(.025,.16,.025),1,'head')
    for side,sign in [('l',1),('r',-1)]:
        x=sign*.27
        box(g,'shoulder.'+side,(x,1.45,0),(.22*wide,.18,.3),1,'upperarm.'+side)
        box(g,'bicep.'+side,(x,1.32,0),(.14,.22,.18),4,'upperarm.'+side)
        box(g,'forearm.'+side,(x,1.08,0),(.18,.22,.21),0,'lowerarm.'+side)
        box(g,'hand.'+side,(x,.95,0),(.13,.12,.16),2,'hand.'+side)
        x=sign*.13
        box(g,'thigh.'+side,(x,.72,0),(.19,.37,.24),0,'upperleg.'+side)
        box(g,'knee.'+side,(x,.51,.12),(.17,.13,.08),1,'lowerleg.'+side)
        box(g,'shin.'+side,(x,.33,0),(.16,.36,.2),4,'lowerleg.'+side)
        box(g,'boot.'+side,(x,.09,.055),(.2,.16,.32),2,'foot.'+side)
    # Enemy barrels are part of the skinned forearm; no unattached floating weapons.
    if role!='player':
        box(g,'arm cannon',(-.27,.96,.04),(.15,.36,.15),1,'lowerarm.r')
    if role in ('heavy','warlord'):
        for sign in [-1,1]:
            box(g,'shoulder pod',(sign*.37,1.58,-.02),(.24,.22,.42),4,'chest')
    writer=Writer();doc=writer.doc;doc['nodes']=nodes
    count=len(nodes); bind=np.linalg.inv(worlds(nodes))
    doc['skins']=[{'name':'StationRobotRig','skeleton':0,'joints':list(range(count)),
        'inverseBindMatrices':writer.add(np.asarray([m.flatten(order='F') for m in bind],dtype='<f4'),'MAT4')}]
    doc['nodes'].append({'name':'RobotShell','mesh':0,'skin':0})
    doc['scenes']=[{'nodes':[0,count]}];doc['scene']=0
    tris=mesh(writer,g,accent,True)
    doc['animations']=[]
    # Sparse fixed-rate keys, shared accessor deduplication, no duplicated texture atlases.
    for clip,duration in CLIPS.items():
        times=np.linspace(0,duration,9,dtype='<f4'); channels=[];samplers=[]
        def track(bone,path,values,kind):
            samplers.append({'input':writer.add(times,'SCALAR',bounds=True),
                             'output':writer.add(np.asarray(values,dtype='<f4'),kind),'interpolation':'LINEAR'})
            channels.append({'sampler':len(samplers)-1,'target':{'node':index[bone],'path':path}})
        for bone in index:
            angles=[]
            for t in times/duration:
                a=np.zeros(3);phase=float(t)*math.tau
                if bone.startswith('upperarm'):
                    a[0]=-math.pi/2  # steady forward gun-ready pose
                if bone.startswith('handslot'):
                    a[0]=math.pi/2   # cancel arm pitch: barrel points authored +Z
                if clip in ('Walking_A','Running_A') and ('leg.' in bone):
                    sign=1 if bone.endswith('.l') else -1
                    a[0]=(0.36 if clip=='Walking_A' else .55)*math.sin(phase)*sign
                    if bone.startswith('lower'):a[0]=max(0,-a[0])*.8
                if clip=='Fire' and bone=='upperarm.r':a[0]-=.12*math.sin(math.pi*t)
                if clip=='Reload' and bone=='upperarm.l':a[2]=.75*math.sin(math.pi*t)
                if clip=='Reload' and bone=='upperarm.r':a[0]+=.4*math.sin(math.pi*t)
                if clip=='Hit_A' and bone=='chest':a[0]=-.18*math.sin(math.pi*t)
                if clip=='Death_A' and bone=='hips':a[0]=-1.5*float(t)
                if clip.startswith('Dodge') and bone=='chest':
                    a[0]=.4*math.sin(math.pi*t)
                    if clip in ('Dodge_Left','Dodge_Right'):a[2]=(.4 if clip=='Dodge_Left' else -.4)*math.sin(math.pi*t)
                if clip in ('Cast','Cheer') and bone=='upperarm.l':a[2]=1.0*math.sin(math.pi*t)
                angles.append(a)
            track(bone,'rotation',Rotation.from_euler('xyz',angles).as_quat(),'VEC4')
        hips=np.tile(nodes[index['hips']]['translation'],(9,1)).astype(float)
        if clip=='Death_A':hips[:,1]-=np.linspace(0,.64,9)
        elif clip.startswith('Dodge'):hips[:,1]-=.16*np.sin(np.linspace(0,math.pi,9))
        track('hips','translation',hips,'VEC3')
        doc['animations'].append({'name':clip,'samplers':samplers,'channels':channels})
    doc['asset']['copyright']='Project-authored sci-fi geometry and animation. No third-party motion.'
    doc['extras']={'recipe':'station_shooter_v1','role':role,'triangles':tris,'texture_count':0}
    write('robots/'+role+'.glb',writer.finish())


def static_asset(name,g,accent):
    w=Writer();w.doc['nodes']=[{'name':'Hardware','mesh':0}]
    w.doc['scenes']=[{'nodes':[0]}];w.doc['scene']=0
    if name.startswith('guns/'):
        # Reconstruct endpoint from the authored barrel geometry.
        length=max(float(v[2]) for v in g.positions)
        w.doc['nodes'].append({'name':'Muzzle','translation':[0,.095,length]})
        w.doc['nodes'][0]['children']=[1]
    mesh(w,g,accent);write(name,w.finish())


def props():
    for i,name in enumerate(GUNS):
        g=Geometry({'root':0});length=[.55,.85,.7,.95,.4,.7,.6,.85,.55][i]
        box(g,'receiver',(0,.09,.12),(.13,.15,.3),0)
        box(g,'grip',(0,-.025,0),(.09,.18,.11),2)
        box(g,'stock',(0,.075,-.13),(.105,.14,.22),4)
        box(g,'barrel',(0,.095,.22+length/4),(.07,.07,length/2),2)
        box(g,'muzzle',(0,.095,.22+length/2),(.115,.1,.07),3)
        box(g,'energy magazine',(0,-.02,.17),(.09,.19,.13),1)
        if name in ('sunbow','sentinel_spear','moonlance'):
            box(g,'optic',(0,.21,.12),(.08,.09,.22),1)
        if name in ('stormhammer','warreaxe','ember_scepter'):
            box(g,'cooling jacket',(0,.1,.3),(.22,.18,.3),4)
        static_asset('guns/'+name+'.glb',g,ROLES['player'])
    for name,accent in {'health_orb':(.12,1,.45),'stamina_shard':(.15,.65,1),'antidote':(.6,1,.2),
                        'coin_cache':(1,.7,.12),'magnet':(.7,.2,1),'xp_gem':(.1,.9,.95)}.items():
        g=Geometry({'root':0});box(g,'sealed supply cell',(0,.2,0),(.38,.4,.28),4)
        box(g,'lit identification',(0,.24,.151),(.25,.08,.025),1)
        box(g,'vertical identification',(0,.24,.153),(.08,.25,.025),1)
        static_asset('pickups/'+name+'.glb',g,accent)
    g=Geometry({'root':0});box(g,'hazard emitter',(0,-.08,0),(4,.16,4),4)
    for x in (-1.6,-.8,0,.8,1.6):
        box(g,'emitter strip',(x,.012,0),(.12,.024,3.6),1)
    static_asset('hazard_tile.glb',g,(1,.3,.05))
    # New project-authored small sprites: no magic runes / dirt explosions.
    import io
    for name in ('spark','ring','flare','smoke','trace'):
        image=Image.new('RGBA',(64,64));d=ImageDraw.Draw(image)
        if name=='ring':d.ellipse((5,5,59,59),outline=(255,255,255,240),width=3)
        elif name=='spark':
            for a in range(0,360,45):
                r=math.radians(a);d.line((32,32,32+28*math.cos(r),32+28*math.sin(r)),fill='white',width=2)
        elif name=='trace':d.rectangle((27,3,37,61),fill=(255,255,255,220))
        else:
            for y in range(64):
                for x in range(64):
                    radius=math.hypot(x-31.5,y-31.5)/32
                    image.putpixel((x,y),(255,255,255,int(max(0,1-radius)**2*220)))
        b=io.BytesIO();image.save(b,format='PNG',optimize=True);write('fx/'+name+'.png',b.getvalue())


def icons():
    import io
    for folder in ('icons','upgrades'):
        for source in sorted((ROOT/'assets/ui'/folder).glob('*.png')):
            image=Image.new('RGBA',(64,64));d=ImageDraw.Draw(image)
            color=(130,220,255,255);variant=int(hashlib.sha256(source.stem.encode()).hexdigest()[:2],16)%5
            d.rounded_rectangle((3,3,60,60),radius=9,outline=(65,135,170,255),width=2)
            if variant==0: # targeting optics
                d.ellipse((17,17,47,47),outline=color,width=3)
                for points in [(32,9,32,23),(32,41,32,55),(9,32,23,32),(41,32,55,32)]:d.line(points,fill=color,width=3)
            elif variant==1: # energy cartridge
                d.rectangle((22,18,42,49),outline=color,width=3);d.rectangle((27,12,37,17),fill=color)
                d.line((32,23,27,34,36,34,31,44),fill=color,width=3)
            elif variant==2: # shield generator
                d.polygon([(32,13),(48,21),(44,40),(32,51),(20,40),(16,21)],outline=color,width=3)
                d.line((24,32,30,38,41,25),fill=color,width=3)
            elif variant==3: # electronics
                d.rectangle((22,22,42,42),outline=color,width=3)
                for k in (23,32,41):
                    d.line((k,13,k,21),fill=color,width=2);d.line((k,43,k,51),fill=color,width=2)
                    d.line((13,k,21,k),fill=color,width=2);d.line((43,k,51,k),fill=color,width=2)
            else: # telemetry
                for i in range(4):d.rectangle((16+i*9,42-i*7,21+i*9,50),fill=color)
            buf=io.BytesIO();image.save(buf,format='PNG',optimize=True);write('ui/'+folder+'/'+source.name,buf.getvalue())


def canonical_ogg(blob, name):
    # libsndfile chooses a random Ogg stream serial. Normalize it and repair
    # each page CRC so identical authoring inputs yield byte-identical assets.
    data=bytearray(blob);offset=0
    serial=int.from_bytes(hashlib.sha256(name.encode()).digest()[:4],'little')
    while offset<len(data):
        if data[offset:offset+4]!=b'OggS':raise ValueError('Invalid Ogg page')
        segments=data[offset+26]
        end=offset+27+segments+sum(data[offset+27:offset+27+segments])
        struct.pack_into('<I',data,offset+14,serial)
        data[offset+22:offset+26]=b'\0'*4
        crc=0
        for value in data[offset:end]:
            crc ^= value<<24
            for _ in range(8):
                crc=((crc<<1)^0x04c11db7 if crc&0x80000000 else crc<<1)&0xffffffff
        struct.pack_into('<I',data,offset+22,crc)
        offset=end
    return bytes(data)


def audio():
    import io
    sr=22050;rng=np.random.default_rng(709)
    for name,duration in [('shot',.16),('reload',.55),('impact',.13),('pickup',.3),('step',.07),('alert',.4),('dash',.22)]:
        t=np.arange(int(sr*duration))/sr
        if name=='shot':signal=(.6*np.sin(2*np.pi*(1250*t-2600*t*t))+.25*rng.normal(size=len(t)))*np.exp(-t*28)
        elif name in ('impact','step'):signal=rng.normal(size=len(t))*.4*np.exp(-t*45)
        elif name=='reload':signal=np.sin(2*np.pi*650*t)*(.3*np.exp(-t*50)+.3*np.exp(-np.maximum(t-.35,0)*50)*(t>.35))
        else:signal=.4*np.sin(2*np.pi*(450*t+500*t*t))*np.sin(np.pi*t/duration)**2
        b=io.BytesIO()
        with wave.open(b,'wb') as w:
            w.setnchannels(1);w.setsampwidth(2);w.setframerate(sr);w.writeframes((np.clip(signal,-1,1)*32767).astype('<i2').tobytes())
        write('audio/'+name+'.wav',b.getvalue())
    # Short seamless electronic loops; integer-cycle oscillators, percussion
    # envelopes reach zero at each beat boundary. Vorbis, mono, low mobile footprint.
    for name,bpm in [('menu',90),('calm',90),('battle',120),('boss',120),('victory',120)]:
        beats=16; beat=60/bpm; t=np.arange(round(sr*beat*beats))/sr;mix=np.zeros(len(t))
        for b in range(beats):
            start=round(b*beat*sr);end=min(round((b+1)*beat*sr),len(t));u=np.arange(end-start)/sr
            progressions={'menu':[110,130.8128,146.8324,98], 'calm':[82.4069,98,110,73.4162],
                          'battle':[110,110,130.8128,98], 'boss':[55,58.2705,65.4064,51.9131],
                          'victory':[130.8128,164.8138,196,261.6256]}
            f=progressions[name][(b//4)%4]
            env=np.sin(np.pi*np.arange(len(u))/len(u))**2
            mix[start:end]+=.12*np.sin(2*np.pi*f*u)*env
            if name not in ('calm','menu'):
                mix[start:end]+=.3*np.sin(2*np.pi*(70*u-35*u*u))*np.exp(-u*30)*env**.15
            if b%2==0:mix[start:end]+=.06*np.sin(2*np.pi*f*4*u)*env
        buf=io.BytesIO();sf.write(buf,mix,sr,format='OGG',subtype='VORBIS');write('audio/'+name+'.ogg',canonical_ogg(buf.getvalue(),name))


def build():
    for role,accent in ROLES.items():robot(role,accent)
    props();icons();audio()
    recipe_files=['tool/build_scifi_assets.py','tool/hero/geometry.py','tool/hero/rig.py','tool/scifi/requirements.txt']
    report={'schema_version':1,'recipe':'station_shooter_v1','license_notice':'ASSET_LICENSES/station-shooter.txt',
        'recipe_files':[{'path':p,'sha256':hashlib.sha256((ROOT/p).read_bytes()).hexdigest()} for p in recipe_files],
        'files':[{'path':str(p.relative_to(ROOT)),'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in OUTPUTS],
        'clips':list(CLIPS), 'authoring':'Project-authored geometry, sparse mechanical animation, sprites and synthesized audio.'}
    (OUT/'build_report.json').write_text(json.dumps(report,indent=2)+'\n')
    print(f'Built {len(OUTPUTS)} assets: {sum(p.stat().st_size for p in OUTPUTS):,} bytes')

if __name__=='__main__':build()
